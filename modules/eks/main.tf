# An EKS (Elastic Kubernetes Service) cluster: the managed Kubernetes control plane. AWS runs the API server
# and etcd (Kubernetes' database) for you; worker nodes come later (node groups, M3.3). Settings chosen here:
#   - the API endpoint is private by default; a public one needs an explicit, CIDR-restricted opt-in,
#   - Kubernetes Secrets are envelope-encrypted with your KMS key,
#   - all control-plane logs go to an encrypted CloudWatch log group,
#   - people and CI get in through access entries (an AWS API), not the legacy aws-auth ConfigMap.

module "labels" {
  source = "../labels"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  components  = [var.name]
}

locals {
  cluster_name = module.labels.names[var.name]
}

data "aws_partition" "current" {}

# The role the EKS service assumes to manage the control plane's network interfaces and load balancers.
module "cluster_role" {
  source = "../iam-role"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  name        = "${var.name}-cluster"
  description = "Assumed by the EKS service to run the ${local.cluster_name} control plane"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  permissions_boundary = var.permissions_boundary
  managed_policy_arns  = ["arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"]
}

# EKS writes to /aws/eks/<cluster>/cluster. Creating the group first, ourselves, lets us set retention and
# encryption; otherwise EKS creates it with no expiry and no key.
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = merge(module.labels.tags, { Name = "${local.cluster_name}-logs" })
}

resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  version  = var.kubernetes_version
  role_arn = module.cluster_role.role_arn

  enabled_cluster_log_types = var.enabled_log_types

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = var.additional_security_group_ids
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.public_access_cidrs : null
  }

  # API: only access entries grant Kubernetes access. The creator gets no hidden admin rights, so every
  # administrator is visible in code (see var.access_entries).
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  encryption_config {
    resources = ["secrets"]

    provider {
      key_arn = var.kms_key_arn
    }
  }

  dynamic "kubernetes_network_config" {
    for_each = var.service_ipv4_cidr == null ? [] : [var.service_ipv4_cidr]

    content {
      service_ipv4_cidr = kubernetes_network_config.value
    }
  }

  tags = merge(module.labels.tags, { Name = local.cluster_name })

  depends_on = [aws_cloudwatch_log_group.cluster]

  lifecycle {
    precondition {
      condition     = !var.endpoint_public_access || length(var.public_access_cidrs) > 0
      error_message = "endpoint_public_access is true but public_access_cidrs is empty. List the networks allowed to reach the API; the default would be the whole internet."
    }
  }
}

resource "aws_eks_access_entry" "this" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  type          = "STANDARD"

  tags = module.labels.tags
}

resource "aws_eks_access_policy_association" "this" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.this[each.key].principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = length(each.value.namespaces) == 0 ? "cluster" : "namespace"
    namespaces = length(each.value.namespaces) == 0 ? null : each.value.namespaces
  }
}
