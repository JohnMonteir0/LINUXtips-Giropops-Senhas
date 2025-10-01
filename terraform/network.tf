################################################################################
# VPC
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 52)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    # Tags subnets for Karpenter auto-discovery
    "karpenter.sh/discovery" = local.name
  }

  tags = local.tags
}

################################################################################
# Secondary VPC CIDR for Pods
################################################################################
resource "aws_vpc_ipv4_cidr_block_association" "pods" {
  vpc_id     = module.vpc.vpc_id
  cidr_block = local.pod_cidr
}

################################################################################
# Pod subnets (1 per AZ)
################################################################################
resource "aws_subnet" "pods" {
  for_each = local.az_index_map

  vpc_id                  = module.vpc.vpc_id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(local.pod_cidr, 3, each.value)
  map_public_ip_on_launch = false

  # Ensure the secondary CIDR is attached first
  depends_on = [aws_vpc_ipv4_cidr_block_association.pods]

  tags = merge(
    local.tags,
    {
      Name                                        = "cilium-pod-${each.key}"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
      "cilium-pod-subnet"                         = "true"
    }
  )
}

################################################################################
# Attach pod subnets to the *matching* private route tables
################################################################################
resource "aws_route_table_association" "pods" {
  for_each = local.az_index_map

  subnet_id      = aws_subnet.pods[each.key].id
  route_table_id = module.vpc.private_route_table_ids[0]
}
