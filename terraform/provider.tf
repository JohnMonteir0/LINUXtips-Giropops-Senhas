provider "aws" {
  # use var.region if you don’t actually have local.region defined
  region = local.region
}

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.37"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.19"
    }
  }

  backend "s3" {
    bucket         = "terraform-backend-statebucket-qb6ige25vfbv"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-backend-LockTable-1LREMK0HDUWWE"
    encrypt        = true
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks_bottlerocket.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_bottlerocket.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks_bottlerocket.cluster_name]
      command     = "aws"
    }
  }
}

provider "kubernetes" {
  host                   = module.eks_bottlerocket.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_bottlerocket.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", module.eks_bottlerocket.cluster_name]
    command     = "aws"
  }
}

provider "kubectl" {
  host                   = module.eks_bottlerocket.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_bottlerocket.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_bottlerocket.cluster_name]
  }
}




