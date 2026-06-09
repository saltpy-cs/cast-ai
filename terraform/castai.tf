provider "castai" {
  api_token = var.castai_api_token
}

# Step 1: register the cluster with CAST.ai to obtain a cluster ID
resource "castai_eks_clusterid" "cluster_id" {
  account_id   = data.aws_caller_identity.current.account_id
  region       = var.region
  cluster_name = var.cluster_name
}

# Step 2: get the CAST.ai IAM user ARN for this cluster
resource "castai_eks_user_arn" "castai_user_arn" {
  cluster_id = castai_eks_clusterid.cluster_id.id
}

# Step 3: create IAM role + instance profile that CAST.ai will assume
module "castai_eks_role_iam" {
  source  = "castai/eks-role-iam/castai"
  version = "~> 2.0"

  aws_account_id     = data.aws_caller_identity.current.account_id
  aws_cluster_region = var.region
  aws_cluster_name   = var.cluster_name
  aws_cluster_vpc_id = module.vpc.vpc_id

  castai_user_arn = castai_eks_user_arn.castai_user_arn.arn

  create_iam_resources_per_cluster = true
}

# Step 4: allow the CAST.ai instance profile role as an EC2 node identity
resource "aws_eks_access_entry" "castai" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.castai_eks_role_iam.instance_profile_role_arn
  type          = "EC2_LINUX"
}

# Step 5: connect the cluster and install CAST.ai Helm components
module "castai_eks_cluster" {
  source  = "castai/eks-cluster/castai"
  version = "~> 14.1"

  castai_api_token       = var.castai_api_token
  wait_for_cluster_ready = true

  aws_account_id     = data.aws_caller_identity.current.account_id
  aws_cluster_region = var.region
  aws_cluster_name   = var.cluster_name

  aws_assume_role_arn        = module.castai_eks_role_iam.role_arn
  delete_nodes_on_disconnect = false

  default_node_configuration = module.castai_eks_cluster.castai_node_configurations["default"]

  node_configurations = {
    default = {
      subnets              = module.vpc.private_subnets
      instance_profile_arn = module.castai_eks_role_iam.instance_profile_arn
      security_groups      = [module.eks.cluster_primary_security_group_id]
    }
  }

  install_workload_autoscaler = true
  install_pod_mutator         = true
  install_security_agent      = true

  overwrite_existing_helm_releases = true

  autoscaler_settings = {
    enabled = true
    unschedulable_pods = {
      enabled = true
    }
    node_downscaler = {
      enabled    = true
      empty_nodes = {
        enabled = false
      }
      evictor = {
        enabled                   = true
        aggressive_mode           = true
        cycle_interval            = "60s"
        node_grace_period_minutes = 5
        scoped_mode               = false
      }
    }
  }

  node_templates = {
    live_tmpl = {
      name             = "live_tmpl"
      configuration_id = module.castai_eks_cluster.castai_node_configurations["default"]
      is_default       = false
      is_enabled       = true
      should_taint     = true

      clm_enabled = true

      constraints = {
        spot               = true
        use_spot_fallbacks = true
        on_demand          = false
        min_cpu            = 2
        max_cpu            = 8
        min_memory         = 4096
        max_memory         = 16384
      }
    }
  }

  depends_on = [module.castai_eks_role_iam, aws_eks_access_entry.castai]
}
