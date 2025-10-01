
module "network" {
  source = "./module-network"

  depends_on = [module.eks_bottlerocket]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = module.eks_bottlerocket.cluster_name
  addon_name                  = "coredns"
  addon_version               = "v1.12.3-eksbuild.1"
  tags                        = local.tags
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    tolerations = [
      { key = "node.kubernetes.io/not-ready", operator = "Exists" },
      { key = "node.cilium.io/agent-not-ready", operator = "Exists" }
    ]
  })

  depends_on = [module.network]
}
module "helm" {
  source                  = "./module-apps"
  cluster_oidc_issuer_url = module.eks_bottlerocket.cluster_oidc_issuer_url
  cluster_name            = module.eks_bottlerocket.cluster_name
  vpc_id                  = module.vpc.vpc_id
  cluster_endpoint        = module.eks_bottlerocket.cluster_endpoint
  queue_name              = module.karpenter.queue_name

  public_subnet_ids_csv = join(",", module.vpc.public_subnets)

  depends_on = [aws_eks_addon.coredns]
}

resource "kubectl_manifest" "karpenter" {
  for_each  = data.kubectl_file_documents.karpenter.manifests
  yaml_body = each.value

  depends_on = [module.helm]
}

resource "kubectl_manifest" "letsencrypt" {
  for_each  = data.kubectl_file_documents.letsencrypt.manifests
  yaml_body = each.value

  depends_on = [module.helm]
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name  = module.eks_bottlerocket.cluster_name
  addon_name    = "eks-pod-identity-agent"
  addon_version = "v1.3.8-eksbuild.2"
}

