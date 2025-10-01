module "karpenter" {
  source = "git::https://github.com/JohnMonteir0/terraform-eks-module.git//modules/karpenter?ref=main"

  cluster_name = module.eks_bottlerocket.cluster_name

  # Name needs to match role name passed to the EC2NodeClass
  node_iam_role_use_name_prefix   = false
  node_iam_role_name              = local.name
  create_pod_identity_association = true

  # Used to attach additional IAM policies to the Karpenter node IAM role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags
}

module "karpenter_disabled" {
  source = "git::https://github.com/JohnMonteir0/terraform-eks-module.git//modules/karpenter?ref=main"

  create = false
}