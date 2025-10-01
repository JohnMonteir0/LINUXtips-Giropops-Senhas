locals {
  oidc = split("/", var.cluster_oidc_issuer_url)[4]
}

locals {
  public_subnet_ids_csv = join(",", data.aws_subnets.public.ids)
  annotations = {
    "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-subnets"         = var.public_subnet_ids_csv
    "service.beta.kubernetes.io/aws-load-balancer-type"            = "nlb"
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
  }

}
