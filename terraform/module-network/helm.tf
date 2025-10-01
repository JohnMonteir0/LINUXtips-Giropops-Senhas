### Cilium ###
resource "helm_release" "cilium" {
  name        = "cilium"
  description = "A Helm chart to deploy cilium"
  namespace   = "kube-system"
  chart       = "cilium"
  version     = "1.18.1"
  repository  = "https://helm.cilium.io"
  wait        = true
  replace     = true
  timeout     = 900

  # --- API server host/port for kube-proxy replacement ---
  set {
    name  = "k8sServiceHost"
    value = replace(data.aws_eks_cluster.this.endpoint, "https://", "")
  }
  set {
    name  = "k8sServicePort"
    value = "443"
  }

  # --- EKS ENI IPAM (native routing, no tunneling) ---
  set {
    name  = "eni.enabled"
    value = "true"
  }
  set {
    name  = "ipam.mode"
    value = "eni"
  }
  set {
    name  = "routingMode"
    value = "native"
  }
  set {
    name  = "endpointRoutes.enabled"
    value = "true"
  }
  set {
    name  = "egressMasqueradeInterfaces"
    value = "eth+"
  }
  set {
    name  = "kubeProxyReplacement"
    value = "true"
  }

  # --- Filter: only use your pod subnets (100.64.0.0/16) ---
  set {
    name  = "eni.subnetTagsFilter[0]"
    value = "cilium-pod-subnet=true"
  }

  # Optional: higher pod density
  set {
    name  = "eni.awsEnablePrefixDelegation"
    value = "true"
  }

  # =============================
  # Hubble (relay + UI)
  # =============================
  set {
    name  = "hubble.enabled"
    value = "true"
  }
  set {
    name  = "hubble.tls.auto.enabled"
    value = "true"
  }
  set {
    name  = "hubble.tls.auto.method"
    value = "helm"
  }

  set {
    name  = "hubble.relay.enabled"
    value = "true"
  }

  set {
    name  = "hubble.ui.enabled"
    value = "true"
  }
  set {
    name  = "hubble.ui.ingress.enabled"
    value = "true"
  }
  set {
    name  = "hubble.ui.ingress.className"
    value = "nginx"
  }
  set {
    name  = "hubble.ui.ingress.hosts[0]"
    value = "hubble.${data.aws_caller_identity.current.account_id}.realhandsonlabs.net"
  }
  set {
    name  = "hubble.ui.ingress.paths[0].path"
    value = "/"
  }
  set {
    name  = "hubble.ui.ingress.paths[0].pathType"
    value = "Prefix"
  }

  # =============================
  # Hubble (metrics)
  # =============================
  # set {
  #   name  = "hubble.metrics.enabled[0]"
  #   value = "dns"
  # }
  # set {
  #   name  = "hubble.metrics.enabled[1]"
  #   value = "drop"
  # }
  # set {
  #   name  = "hubble.metrics.enabled[2]"
  #   value = "tcp"
  # }
  # set {
  #   name  = "hubble.metrics.enabled[3]"
  #   value = "flow"
  # }
  # set {
  #   name  = "hubble.metrics.enabled[4]"
  #   value = "port-distribution"
  # }
  # set {
  #   name  = "hubble.metrics.enabled[5]"
  #   value = "icmp"
  # }
  # set {
  #   name  = "hubble.metrics.enabled[6]"
  #   value = "httpV2:exemplars=true;labelsContext=source_ip\\,source_namespace\\,source_workload\\,destination_ip\\,destination_namespace\\,destination_workload\\,traffic_direction"
  # }
  # set {
  #   name  = "hubble.metrics.serviceMonitor.enabled"
  #   value = "true"
  # }

  # set {
  #   name  = "prometheus.enabled"
  #   value = "true"
  # }

  # set {
  #   name  = "prometheus.serviceMonitor.enabled"
  #   value = "true"
  # }
  # set {
  #   name  = "operator.prometheus.enabled"
  #   value = "true"
  # }

  # set {
  #   name  = "operator.prometheus.serviceMonitor.enabled"
  #   value = "true"
  # }

  # set {
  #   name  = "hubble.metrics.enableOpenMetrics"
  #   value = "true"
  # }
}

resource "helm_release" "tetragon" {
  name             = "tetragon"
  namespace        = "kube-system"
  repository       = "https://helm.cilium.io/"
  chart            = "tetragon"
  version          = "1.5.0"
  create_namespace = false
  wait             = true
  timeout          = 600

  values = [
    yamlencode({
      tetragon = {
        # Prometheus metrics optons
        prometheus = {
          enabled = false
          serviceMonitor = {
            enabled = false
          }
        }

        # Enable tracing of process execution
        tracingPolicy = {
          enabled = true
        }
      }
    })
  ]
  depends_on = [helm_release.cilium]
}


