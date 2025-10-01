resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  wait       = true
  timeout    = 900
  atomic     = true

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "region"
    value = data.aws_region.current.name
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.eks_load_balancer_controller.arn
  }

  depends_on = [
    aws_iam_role_policy_attachment.attach_load_balancer_policy
  ]
}

### External DNS ###
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = "1.15.0"
  namespace  = "kube-system"

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = "external-dns"
  }

  set {
    name  = "policy"
    value = "sync"
  }
}

### Ingress NGINX Controller ###
resource "helm_release" "ingress-nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.13.2"
  create_namespace = true
  namespace        = "ingress-nginx"
  replace          = true
  atomic           = true

  values = [
    yamlencode({
      controller = {
        service = {
          annotations = local.annotations
        }
      }
    })
  ]
  depends_on = [
    helm_release.aws_load_balancer_controller
  ]
}

### EBS CSI Driver Install ###
resource "helm_release" "ebs_csi_driver" {
  name       = "aws-ebs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart      = "aws-ebs-csi-driver"
  namespace  = "kube-system"
  version    = "2.30.0"

  set {
    name  = "controller.serviceAccount.create"
    value = "false"
  }

  set {
    name  = "controller.serviceAccount.name"
    value = "ebs-csi-controller-sa"
  }

  set {
    name  = "enableVolumeScheduling"
    value = "true"
  }

  set {
    name  = "enableVolumeResizing"
    value = "true"
  }

  set {
    name  = "enableVolumeSnapshot"
    value = "true"
  }

  # storageClasses[0]
  set {
    name  = "storageClasses[0].name"
    value = "ebs-csi"
  }
  set {
    name  = "storageClasses[0].annotations.storageclass\\.kubernetes\\.io/is-default-class"
    value = "\"true\"" # note the extra quotes inside
  }
  set {
    name  = "storageClasses[0].volumeBindingMode"
    value = "WaitForFirstConsumer"
  }
  set {
    name  = "storageClasses[0].reclaimPolicy"
    value = "Delete"
  }
  set {
    name  = "storageClasses[0].parameters.encrypted"
    value = "\"true\""
  }
  set {
    name  = "storageClasses[0].parameters.type"
    value = "gp3"
  }

  depends_on = [
    aws_iam_role_policy_attachment.attach_ebs_csi_policy
  ]
}

### Cert Manager ###
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.18.2"
  create_namespace = true
  timeout          = 900
  wait             = true
  replace          = true
  atomic           = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "prometheus.enabled"
    value = "true"
  }

  set {
    name  = "webhook.timeoutSeconds"
    value = "30"
  }

  set {
    name  = "replicaCount"
    value = "2"
  }
  depends_on = [
    helm_release.aws_load_balancer_controller,
    helm_release.ingress-nginx
  ]
}

### Argocd ###
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "5.51.6"
  create_namespace = true
  timeout          = 900
  wait             = true

  values = [
    yamlencode({
      global = {
        domain = "argocd.${data.aws_caller_identity.current.account_id}.realhandsonlabs.net"
      }

      configs = {
        params = {
          "server.insecure" = true
        }
      }

      server = {
        ingress = {
          enabled          = true
          ingressClassName = "nginx"
          annotations = {
            "nginx.ingress.kubernetes.io/force-ssl-redirect" = "false"
            "nginx.ingress.kubernetes.io/backend-protocol"   = "HTTP"
            "external-dns.alpha.kubernetes.io/hostname"      = "argocd.${data.aws_caller_identity.current.account_id}.realhandsonlabs.net"
            "cert-manager.io/cluster-issuer"                 = "letsencrypt-staging"
          }
          tls = [
            {
              hosts      = ["argocd.${data.aws_caller_identity.current.account_id}.realhandsonlabs.net"]
              secretName = "letsencrypt-staging"
            }
          ]
        }
      }
    })
  ]

  depends_on = [
    helm_release.aws_load_balancer_controller,
    helm_release.ingress-nginx,
    helm_release.cert_manager
  ]
}


### Karpenter ###
resource "helm_release" "karpenter" {
  namespace  = "kube-system"
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.1.6"
  atomic     = true
  timeout    = 900

  set {
    name  = "settings.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "settings.clusterEndpoint"
    value = var.cluster_endpoint
  }

  set {
    name  = "settings.interruptionQueue"
    value = var.queue_name
  }
}

### Kube Prometheus ###
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "77.9.1"
  namespace        = "monitoring"
  create_namespace = true
  atomic           = true
  timeout          = 300

  values = [
    yamlencode({
      prometheus = {
        # Ingress for the Prometheus UI
        ingress = {
          enabled          = true
          ingressClassName = "nginx"
          annotations = {
            "nginx.ingress.kubernetes.io/force-ssl-redirect" = "false"
            "nginx.ingress.kubernetes.io/backend-protocol"   = "HTTP"
            "external-dns.alpha.kubernetes.io/hostname"      = "prometheus.${data.aws_caller_identity.current.account_id}.realhandsonlabs.net"
            "cert-manager.io/cluster-issuer"                 = "letsencrypt-staging"
          }
          hosts    = ["prometheus.${data.aws_caller_identity.current.account_id}.realhandsonlabs.net"]
          paths    = ["/"]
          pathType = "Prefix"
          tls = [{
            hosts      = ["prometheus.${data.aws_caller_identity.current.account_id}.realhandsonlabs.net"]
            secretName = "letsencrypt-staging"
          }]
        }

        # Your existing prometheusSpec stays as-is
        prometheusSpec = {
          serviceMonitorSelector                  = {}
          serviceMonitorNamespaceSelector         = {}
          podMonitorSelector                      = {}
          podMonitorNamespaceSelector             = {}
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
        }
      }

      grafana = {
        # Ingress for Grafana
        ingress = {
          enabled          = true
          ingressClassName = "nginx"
          annotations = {
            "nginx.ingress.kubernetes.io/force-ssl-redirect" = "false"
            "nginx.ingress.kubernetes.io/backend-protocol"   = "HTTP"
            "external-dns.alpha.kubernetes.io/hostname"      = "grafana.${data.aws_caller_identity.current.account_id}.realhandsonlabs.net"
            "cert-manager.io/cluster-issuer"                 = "letsencrypt-staging"
          }
          hosts    = ["grafana.${data.aws_caller_identity.current.account_id}.realhandsonlabs.net"]
          path     = "/"
          pathType = "Prefix"
          tls = [{
            hosts      = ["grafana.${data.aws_caller_identity.current.account_id}.realhandsonlabs.net"]
            secretName = "letsencrypt-staging"
          }]
        }

        # Grafana datasources
        additionalDataSources = [
          {
            name      = "Loki"
            type      = "loki"
            access    = "proxy"
            url       = "http://loki.monitoring.svc.cluster.local:3100"
            isDefault = false
            jsonData = {
              maxLines = 1000
              timeout  = 60
              derivedFields = [
                {
                  name         = "trace_id"
                  matcherRegex = "trace_id=(\\w+)"
                  url          = "$${__url}/explore?orgId=1&left=[\"now-15m\",\"now\",\"tempo\",{\"query\":\"$${__value.raw}\"}]"
                }
              ]
            }
          },
          {
            name     = "Tempo"
            type     = "tempo"
            access   = "proxy"
            url      = "http://tempo.monitoring.svc.cluster.local:3200"
            editable = true
            jsonData = {
              nodeGraph = { enabled = true }
              tracesToLogs = {
                datasourceUid      = "Loki"
                spanStartTimeShift = "1h"
                spanEndTimeShift   = "1h"
                filterByTraceID    = true
                filterBySpanID     = false
                tags               = ["job", "instance", "pod", "namespace", "container"]
              }
            }
          }
        ]
      }
    })
  ]
  depends_on = [
    helm_release.aws_load_balancer_controller,
    helm_release.ingress-nginx,
    helm_release.cert_manager
  ]
}

### Jaeger ###
resource "helm_release" "jaeger" {
  name             = "jaeger"
  namespace        = "monitoring"
  repository       = "https://jaegertracing.github.io/helm-charts"
  chart            = "jaeger"
  version          = "3.4.1"
  create_namespace = true
  atomic           = true

  values = [
    yamlencode({
      fullnameOverride   = "jaeger"
      provisionDataStore = { cassandra = false, elasticsearch = false }
      storage            = { type = "memory" }

      # Run everything in one pod so memory storage works
      allInOne = {
        enabled = true

        # Expose OTLP listeners directly on the all-in-one process
        extraArgs = [
          "--collector.otlp.enabled=true",
          "--collector.otlp.grpc.host-port=:4317",
          "--collector.otlp.http.host-port=:4318",
        ]

        service = {
          ports = {
            http      = 16686 # Jaeger UI
            otlp-grpc = 4317  # OTLP gRPC ingest
            otlp-http = 4318  # OTLP HTTP ingest
            grpc      = 14250 # Classic Jaeger gRPC ingest (optional)
          }
        }

        # UI ingress (lives under allInOne, not query)
        ingress = {
          enabled          = true
          ingressClassName = "nginx"
          annotations = {
            "nginx.ingress.kubernetes.io/force-ssl-redirect" = "false"
            "nginx.ingress.kubernetes.io/backend-protocol"   = "HTTP"
            "external-dns.alpha.kubernetes.io/hostname"      = "jaeger.${data.aws_caller_identity.current.account_id}.realhandsonlabs.net"
            "cert-manager.io/cluster-issuer"                 = "letsencrypt-staging"
          }
          hosts = ["jaeger.${data.aws_caller_identity.current.account_id}.realhandsonlabs.net"]
          tls = [{
            hosts      = ["jaeger.${data.aws_caller_identity.current.account_id}.realhandsonlabs.net"]
            secretName = "letsencrypt-staging"
          }]
        }
      }

      # Turn off split components to avoid duplicate Services
      query     = { enabled = false }
      collector = { enabled = false }
      agent     = { enabled = false }

      cassandra     = { enabled = false }
      elasticsearch = { enabled = false }
      kafka         = { enabled = false }
      indexCleaner  = { enabled = false }
      esRollover    = { enabled = false }
    })
  ]

  depends_on = [
    helm_release.aws_load_balancer_controller,
    helm_release.ingress-nginx,
    helm_release.cert_manager
  ]
}

## Opentelemetry ###
resource "helm_release" "otel_collector" {
  name             = "otel-collector"
  namespace        = "monitoring"
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-collector"
  version          = "0.132.0"
  create_namespace = false
  atomic           = true

  values = [
    yamlencode({
      mode    = "deployment"
      image   = { repository = "otel/opentelemetry-collector-contrib" }
      service = { type = "ClusterIP" }

      config = {
        receivers = {
          otlp = {
            protocols = {
              grpc = { endpoint = "0.0.0.0:4317" }
              http = { endpoint = "0.0.0.0:4318" }
            }
          }
        }

        processors = {
          batch = {}
          # memory_limiter = { check_interval = "5s", limit_percentage = 80, spike_limit_percentage = 25 }
        }

        exporters = {
          "otlp/jaeger" = {
            endpoint = "jaeger-collector:4317"
            tls      = { insecure = true }
          }
          "otlp/tempo" = {
            endpoint = "tempo:4317"
            tls      = { insecure = true }
          }
          prometheus = { endpoint = "0.0.0.0:9464" }
          debug      = { verbosity = "normal" }
        }

        service = {
          pipelines = {
            traces  = { receivers = ["otlp"], processors = ["batch"], exporters = ["otlp/jaeger", "otlp/tempo", "debug"] }
            metrics = { receivers = ["otlp"], processors = ["batch"], exporters = ["prometheus", "debug"] }
            logs    = { receivers = ["otlp"], processors = ["batch"], exporters = ["debug"] }
          }
          telemetry = { logs = { level = "info" } }
        }
      }

      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    })
  ]

  depends_on = [
    helm_release.jaeger,
    helm_release.ingress-nginx,
    helm_release.cert_manager,
    helm_release.aws_load_balancer_controller,
    helm_release.kube_prometheus_stack
  ]
}


## Loki Stack ###
resource "helm_release" "loki" {
  name             = "loki"
  namespace        = "monitoring"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki-stack"
  version          = "2.10.2"
  create_namespace = false
  atomic           = true
  timeout          = 300

  values = [yamlencode({
    grafana = { enabled = false }

    loki = {
      enabled        = true
      auth_enabled   = false
      serviceMonitor = { enabled = true }
      singleBinary   = { enabled = true }
      commonConfig   = { replication_factor = 1 }
      storage        = { type = "filesystem" }
      schemaConfig = {
        configs = [{
          from         = "2024-01-01"
          store        = "tsdb"
          object_store = "filesystem"
          schema       = "v13"
          index        = { prefix = "index_", period = "24h" }
        }]
      }
      service = { type = "ClusterIP", port = 3100 }
    }

    promtail = {
      enabled = true

      # use the chart's default /run/promtail (already mounted & writable)
      config = {
        server    = { http_listen_port = 3101, grpc_listen_port = 0 }
        positions = { filename = "/run/promtail/positions.yaml" }

        clients = [{
          url = "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push"
        }]

        scrape_configs = [{
          job_name = "kubernetes-pods"
          pipeline_stages = [
            { cri = {} },
            { regex = { expression = ".*(?:trace[id|_id|Id]|otel.trace_id)=(?P<trace_id>[A-Za-z0-9]+).*" } },
            { labels = { trace_id = "" } }
          ]
          kubernetes_sd_configs = [{ role = "pod" }]
          relabel_configs = [
            { source_labels = ["__meta_kubernetes_pod_node_name"], target_label = "node" },
            { source_labels = ["__meta_kubernetes_namespace"], target_label = "namespace" },
            { source_labels = ["__meta_kubernetes_pod_name"], target_label = "pod" },
            { source_labels = ["__meta_kubernetes_pod_container_name"], target_label = "container" },
            { source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name"], target_label = "app" },
            { source_labels = ["__meta_kubernetes_pod_label_app"], target_label = "app", regex = "(.+)", action = "replace" },
            { action       = "replace",
              replacement  = "/var/log/pods/*$1/*.log",
              target_label = "__path__",
            source_labels = ["__meta_kubernetes_pod_uid", "__meta_kubernetes_pod_container_name"] }
          ]
        }]
      }

      serviceMonitor = {
        enabled = true
        labels  = { release = "kube-prometheus-stack" }
      }
    }
  })]

  depends_on = [
    helm_release.jaeger,
    helm_release.kube_prometheus_stack
  ]
}

### Tempo ###
resource "helm_release" "tempo" {
  name             = "tempo"
  namespace        = "monitoring"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "tempo"
  version          = "1.23.3"
  create_namespace = false
  atomic           = true
  timeout          = 600

  values = [yamlencode({
    fullnameOverride = "tempo"

    tempo = {
      config = <<-EOT
        server:
          http_listen_port: 3200

        distributor:
          receivers:
            otlp:
              protocols:
                http: {}   # :4318
                grpc: {}   # :4317

        # Simple local storage good for labs. No WAL settings needed.
        storage:
          trace:
            backend: local
            local:
              path: /var/tempo

      EOT
    }

    service = {
      type = "ClusterIP"
    }

    # Let kube-prometheus-stack auto-discover Tempo metrics
    serviceMonitor = { enabled = true }
  })]

  depends_on = [
    helm_release.otel_collector,
    helm_release.kube_prometheus_stack
  ]
}

### Sonarqube ###
# Optional: generate a strong passcode (or use a TF var)
resource "helm_release" "sonarqube" {
  name             = "sonarqube"
  namespace        = "sonarqube"
  create_namespace = true
  repository       = "https://SonarSource.github.io/helm-chart-sonarqube"
  chart            = "sonarqube"
  version          = "2025.5.0"
  timeout          = 300
  atomic           = true

  values = [
    yamlencode({
      monitoringPasscode = var.db_password

      service = {
        type = "ClusterIP"
        port = 9000
      }

      persistence = {
        enabled      = true
        storageClass = "gp3"
        accessMode   = "ReadWriteOnce"
        size         = "20Gi"
      }

      resources = {
        requests = { cpu = "500m", memory = "2Gi" }
        limits   = { cpu = "2",    memory = "4Gi" }
      }

      initSysctl = { enabled = true }

      sonarProperties = {
        "sonar.core.serverBaseURL" = "https://sonarqube.${data.aws_caller_identity.current.account_id}.realhandsonlabs.net"
      }

      postgresql = {
        enabled = true
        auth = {
          username = var.db_username
          password = var.db_password
          database = "sonarqube"
        }
        primary = {
          persistence = {
            enabled      = true
            storageClass = "gp3"
            size         = "20Gi"
          }
        }
      }

      ingress = {
        enabled          = true
        ingressClassName = "nginx"
        annotations = {
          "external-dns.alpha.kubernetes.io/hostname"      = "sonarqube.${data.aws_caller_identity.current.account_id}.realhandsonlabs.net"
          "cert-manager.io/cluster-issuer"                 = "letsencrypt-staging"
          "nginx.ingress.kubernetes.io/force-ssl-redirect" = "true"
          "nginx.ingress.kubernetes.io/backend-protocol"   = "HTTP"
        }
        hosts = [
          {
            name     = "sonarqube.${data.aws_caller_identity.current.account_id}.realhandsonlabs.net"
            path     = "/"
            pathType = "Prefix"
          }
        ]
        tls = [
          {
            secretName = "letsencrypt-staging"
            hosts      = ["sonarqube.${data.aws_caller_identity.current.account_id}.realhandsonlabs.net"]
          }
        ]
      }
    })
  ]

  depends_on = [
    helm_release.ingress-nginx,
    helm_release.cert_manager,
    helm_release.aws_load_balancer_controller,
    helm_release.external_dns
  ]
}






















