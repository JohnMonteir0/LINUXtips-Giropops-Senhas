data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  filter {
    name   = "tag:kubernetes.io/role/elb"
    values = ["1"]
  }

  filter {
    name   = "tag:kubernetes.io/cluster/${var.cluster_name}"
    values = ["shared"]
  }
}
