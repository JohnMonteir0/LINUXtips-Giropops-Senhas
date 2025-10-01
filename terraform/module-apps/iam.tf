resource "aws_iam_role" "eks_load_balancer_controller" {
  name = "eks-load-balancer-controller-role"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/${local.oidc}"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:kube-system:aws-load-balancer-controller"
            "${replace(var.cluster_oidc_issuer_url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "load_balancer_controller_policy" {
  name = "eks-load-balancer-controller-policy"

  policy = data.aws_iam_policy_document.lb_controller_policy.json
}

resource "aws_iam_role_policy_attachment" "attach_load_balancer_policy" {
  role       = aws_iam_role.eks_load_balancer_controller.name
  policy_arn = aws_iam_policy.load_balancer_controller_policy.arn
}

### EBS CSI Controller ###
resource "aws_iam_role" "eks_ebs_csi_controller" {
  name = "ebs-csi-controller-role"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/${local.oidc}"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:kube-system:ebs-csi-controller-sa"
            "${replace(var.cluster_oidc_issuer_url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "attach_ebs_csi_policy" {
  role       = aws_iam_role.eks_ebs_csi_controller.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

### External DNS ###
resource "aws_iam_role" "eks_external_dns" {
  name = "eks-external-dns-role"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/${local.oidc}"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:kube-system:external-dns"
            "${replace(var.cluster_oidc_issuer_url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "external_dns_policy" {
  name = "eks-external-dns-policy"

  policy = data.aws_iam_policy_document.external_dns_policy.json
}

resource "aws_iam_role_policy_attachment" "attach_external_dns_policy" {
  role       = aws_iam_role.eks_external_dns.name
  policy_arn = aws_iam_policy.external_dns_policy.arn
}