# Live-drill stack "m3": the milestone 3 container modules, applied for real for the length of a drill, then
# destroyed. Started only by .github/workflows/live-drill.yml. It grows with each M3 roadmap item;
# M3.1 adds two ECR repositories encrypted with a drill KMS key. M3.2 adds an EKS control plane in a small VPC.
# M3.3 adds managed node groups (one running on-demand node, one spot group scaled to zero) and a NAT gateway.
# M3.4 adds the five EKS add-ons and a Pod Identity role for the EBS CSI driver.
#
# Cost: repositories and the lifecycle policies are free while empty. Each KMS key bills about $1 a month
# prorated by the hour (a fraction of a cent for a drill) and is scheduled for deletion after 7 days.
# The EKS control plane is the one real charge: $0.10 an hour, so a drill of 20 to 40 minutes costs a few cents.
# M3.3 adds one NAT gateway ($0.045 an hour) and one t3.small node (about $0.02 an hour), plus its 30 GiB
# volume (fractions of a cent). The spot group is scaled to zero, so it costs nothing. A drill is a few cents.
# M3.4 adds nothing billable: add-ons are free and their pods run on the one node.

data "aws_caller_identity" "current" {}

locals {
  stack        = "m3"
  cluster_name = "platform-live-eks" # <project>-<environment>-<name> from modules/labels

  # One place for the Kubernetes minor version, so the control plane and the add-on lookups cannot disagree.
  kubernetes_version = "1.35"
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

# A small network for the cluster: 2 AZs and one NAT gateway. The nodes sit in private subnets and need a way
# out to pull the default add-on images and reach the EC2 and ECR APIs; the NAT gateway is the cheapest one.
# The cluster name tag lets EKS discover the subnets.
module "vpc" {
  source = "../../../modules/vpc"

  project     = "platform"
  environment = "live"
  owner       = var.owner
  az_count    = 2

  enable_nat_gateway = true
  single_nat_gateway = true
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

# Private endpoint only (the module default), all five log types. access_entries is empty:
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
  kubernetes_version   = local.kubernetes_version
}

# Worker nodes. "system" is one on-demand t3.small that really joins the cluster (the drill waits for the
# group to turn ACTIVE, which proves the launch template, the role and the network all work). "batch" is a
# spot group scaled to zero: it proves the spot and taint settings are accepted without starting a node.
# Together they allow 3 nodes at most, which is the plan gate's limit. Root volumes use the AWS-managed
# aws/ebs key: the drill role's EC2 permissions cover it and no key policy is needed.
# There is no depends_on = [module.vpc]: it would make every data source in the module wait for apply. The
# nodes already wait for the cluster, which takes about 10 minutes, long after the NAT route exists.
module "nodes" {
  source = "../../../modules/eks-node-group"

  project              = "platform"
  environment          = "live"
  owner                = var.owner
  cluster_name         = module.eks.cluster_name
  subnet_ids           = module.vpc.eks_subnet_ids
  permissions_boundary = var.permissions_boundary_arn

  node_groups = {
    system = {
      instance_types = ["t3.small"]
      min_size       = 1
      desired_size   = 1
      max_size       = 2
      disk_size_gib  = 20
      labels         = { workload = "system" }
    }

    batch = {
      capacity_type  = "SPOT"
      instance_types = ["t3.small", "t3a.small"]
      min_size       = 0
      desired_size   = 0
      max_size       = 1
      disk_size_gib  = 20
      labels         = { workload = "batch" }
      taints         = [{ key = "spot", value = "true", effect = "NO_SCHEDULE" }]
    }
  }
}

# The add-ons. A real stack writes the versions out (see modules/eks-addons/README.md). A drill asks EKS for
# each add-on's default version for this Kubernetes minor instead: version numbers cannot be checked offline,
# and a stale pin would fail the whole drill. Pods are cut to one replica each so everything fits on the one
# t3.small node (11 pods at most).
locals {
  addon_names = ["vpc-cni", "coredns", "kube-proxy", "eks-pod-identity-agent", "aws-ebs-csi-driver"]
}

data "aws_eks_addon_version" "this" {
  for_each = toset(local.addon_names)

  addon_name         = each.key
  kubernetes_version = local.kubernetes_version
  most_recent        = false # the version EKS marks as the default for this Kubernetes minor
}

# Add-ons need nodes (CoreDNS stays Degraded without them). A depends_on on the whole module would make its
# data sources wait for apply, which breaks the plan, so the dependency is carried by a value instead: this
# resource only exists once the node groups do, and the add-ons take the cluster name from it.
resource "terraform_data" "nodes_ready" {
  input            = module.eks.cluster_name
  triggers_replace = module.nodes.node_group_arns
}

module "addons" {
  source = "../../../modules/eks-addons"

  project              = "platform"
  environment          = "live"
  owner                = var.owner
  cluster_name         = terraform_data.nodes_ready.output
  permissions_boundary = var.permissions_boundary_arn

  addons = {
    for name in local.addon_names : name => {
      version = data.aws_eks_addon_version.this[name].version
      configuration_values = lookup({
        coredns              = jsonencode({ replicaCount = 1 })
        "aws-ebs-csi-driver" = jsonencode({ controller = { replicaCount = 1 } })
      }, name, null)
    }
  }
}

# One example workload: the service account orders-api in namespace orders gets read access to the api
# repository's metadata. No pod runs; the point is a real role and a real association, which the drill
# screenshots. Not a dependency of the add-ons: the association only needs the cluster to exist.
module "workload_identity" {
  source = "../../../modules/eks-pod-identity"

  project              = "platform"
  environment          = "live"
  owner                = var.owner
  name                 = "orders"
  cluster_name         = terraform_data.nodes_ready.output
  namespace            = "orders"
  service_account      = "orders-api"
  permissions_boundary = var.permissions_boundary_arn

  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ecr:DescribeRepositories", "ecr:DescribeImages"]
      Resource = [module.ecr.repository_arns["api"]]
    }]
  })
}
