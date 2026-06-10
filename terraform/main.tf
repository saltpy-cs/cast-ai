terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    castai = {
      source  = "castai/castai"
      version = "~> 8.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  cluster_endpoint = try(module.eks.cluster_endpoint, "")
  cluster_ca       = try(module.eks.cluster_certificate_authority_data, "")
  k8s_host         = local.cluster_endpoint != "" ? local.cluster_endpoint : "https://localhost:6443"
  k8s_ca           = local.cluster_ca != "" ? base64decode(local.cluster_ca) : ""
}

provider "kubernetes" {
  host                   = local.k8s_host
  cluster_ca_certificate = local.k8s_ca
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region, "--role-arn", aws_iam_role.eks_admin.arn]
  }
}

provider "helm" {
  kubernetes = {
    host                   = local.k8s_host
    cluster_ca_certificate = local.k8s_ca
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region, "--role-arn", aws_iam_role.eks_admin.arn]
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# KMS key for encrypting Kubernetes secrets at rest
resource "aws_kms_key" "eks" {
  description             = "${var.cluster_name} EKS secrets encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = var.tags
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}"
  target_key_id = aws_kms_key.eks.key_id
}

# Dedicated IAM role for kubectl admin access.
# AWSReservedSSO_ roles cannot be EKS access entry principals, so we create a
# plain IAM role and allow the caller (SSO or otherwise) to assume it.
resource "aws_iam_role" "eks_admin" {
  name = "${var.cluster_name}-admin"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = data.aws_caller_identity.current.arn }
      Action    = "sts:AssumeRole"
    }]
  })
}

# VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.cluster_name
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = "1.35"

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.allowed_cidrs

  enabled_log_types = ["audit", "authenticator"]

  encryption_config = {
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    default = {
      name           = "default"
      instance_types = ["t3.medium"]
      capacity_type  = "SPOT"

      min_size     = 1
      max_size     = 3
      desired_size = 1

      disk_size = 20

      # Pods need hop limit > 1 to reach IMDS (default of 1 blocks pod-level access)
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
      }
    }
  }

  access_entries = {
    admin = {
      principal_arn = aws_iam_role.eks_admin.arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  tags = var.tags
}
