# Live-drill stack "m3": the milestone 3 container modules, applied for real for the length of a drill, then
# destroyed. Started only by .github/workflows/live-drill.yml. It grows with each M3 roadmap item;
# M3.1 adds two ECR repositories encrypted with a drill KMS key. M3.2 adds an EKS control plane in a small VPC.
#
# Cost: repositories and the lifecycle policies are free while empty. Each KMS key bills about $1 a month
# prorated by the hour (a fraction of a cent for a drill) and is scheduled for deletion after 7 days.
# The EKS control plane is the one real charge: $0.10 an hour, so a drill of 20 to 40 minutes costs a few cents.
# The VPC has no NAT gateway and there are no nodes, so nothing else bills by the hour.

data "aws_caller_identity" "current" {}

locals {
  stack        = "m3"
  cluster_name = "platform-live-eks" # <project>-<environment>-<name> from modules/labels
}

module "labels" {
  source = "../../../modules/labels"

  project     = "platform"
  environment = "live"
  owner       = var.owner

  # live-stack lets the workflow find anything this stack left behind with one tag lookup after destroy.
  extra_tags = { "live-stack" = local.stack }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = module.labels.tags
  }
}

module "kms_ecr" {
  source = "../../../modules/kms"

  project     = "platform"
  environment = "live"
  owner       = var.owner
  purpose     = "ecr"
  description = "Drill key: encrypts the platform-live container image repositories"

  deletion_window_in_days = 7
}

module "ecr" {
  source = "../../../modules/ecr"

  project     = "platform"
  environment = "live"
  owner       = var.owner
  kms_key_arn = module.kms_ecr.key_arn

  repositories = {
    api    = { force_delete = true }
    worker = { keep_last_images = 10, force_delete = true }
  }
}

# A small network for the control plane: 2 AZs, no NAT gateway (the control plane and, until M3.3, the
# lack of nodes mean nothing needs outbound internet). The cluster name tag lets EKS discover the subnets.
module "vpc" {
  source = "../../../modules/vpc"

  project     = "platform"
  environment = "live"
  owner       = var.owner
  az_count    = 2

  enable_nat_gateway = false
  eks_cluster_names  = [local.cluster_name]
}

# One key for Kubernetes Secrets and the control-plane log group. CloudWatch Logs may use it only for the
# cluster's own log group; EKS reaches the key through a grant made by whoever creates the cluster.
module "kms_eks" {
  source = "../../../modules/kms"

  project     = "platform"
  environment = "live"
  owner       = var.owner
  purpose     = "eks"
  description = "Drill key: encrypts Kubernetes secrets and the control-plane logs of platform-live-eks"

  service_grants = {
    CloudWatchLogs = {
      service = "logs.${var.region}.amazonaws.com"
      encryption_context = {
        "aws:logs:arn" = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/eks/${local.cluster_name}/cluster"
      }
    }
  }

  deletion_window_in_days = 7
}

# Private endpoint only (the module default), all five log types, no nodes yet. access_entries is empty:
# nobody needs kubectl during a drill, and the creator gets no hidden admin rights.
module "eks" {
  source = "../../../modules/eks"

  project              = "platform"
  environment          = "live"
  owner                = var.owner
  subnet_ids           = module.vpc.eks_subnet_ids
  kms_key_arn          = module.kms_eks.key_arn
  logs_kms_key_arn     = module.kms_eks.key_arn
  permissions_boundary = var.permissions_boundary_arn
  log_retention_days   = 365 # the module's default; stated here because the group lives minutes
}
