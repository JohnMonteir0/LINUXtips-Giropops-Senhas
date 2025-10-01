locals {
  name   = "cilium"
  region = "us-east-1"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Cluster     = local.name
    GithubRepo  = "terraform-aws-eks"
    Environment = "Dev"
  }
}

locals {
  pod_cidr     = "100.64.0.0/16"
  az_index_map = { for idx, az in local.azs : az => idx }
}