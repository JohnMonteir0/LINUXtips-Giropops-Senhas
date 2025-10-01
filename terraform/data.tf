data "aws_availability_zones" "available" {
  # Exclude local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "kubectl_file_documents" "karpenter" {
  content = file("${path.root}/karpenter.yaml")
}

data "kubectl_file_documents" "letsencrypt" {
  content = file("${path.root}/letsencrypt.yaml")
}

data "aws_caller_identity" "current" {}