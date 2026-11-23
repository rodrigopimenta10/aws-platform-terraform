# EKS add-ons: software AWS packages for the cluster and keeps patchable. A new cluster already runs default
# copies of vpc-cni, coredns and kube-proxy that EKS installed itself, with versions nobody wrote down.
# Declaring them as aws_eks_addon makes EKS take them over, so the versions live in code and an upgrade is a
# reviewed change. The EBS CSI driver is not installed by default; it lets pods use EBS volumes.

locals {
  ebs_csi_addon = "aws-ebs-csi-driver"
  agent_addon   = "eks-pod-identity-agent"

  # The module builds the EBS CSI role unless the caller brings one. Keys are known at plan time.
  create_ebs_csi_role = contains(keys(var.addons), local.ebs_csi_addon) ? var.addons[local.ebs_csi_addon].pod_identity_role_arn == null : false

  # Service account each add-on's pods run as, for the Pod Identity association.
  service_accounts = {
    (local.ebs_csi_addon) = "ebs-csi-controller-sa"
  }
}

module "labels" {
  source = "../labels"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  components  = [var.name]
}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

# Pod Identity: pods get their own role through the eks-pod-identity-agent add-on, with no OIDC provider to
# manage. The EKS service principal pods.eks.amazonaws.com is trusted, and the policy is the AWS-managed one
# written for this driver (create, attach, snapshot and delete volumes).
module "ebs_csi_role" {
  count  = local.create_ebs_csi_role ? 1 : 0
  source = "../iam-role"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  name        = "${var.name}-ebs-csi"
  description = "Assumed by the EBS CSI driver in ${var.cluster_name} through EKS Pod Identity"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })

  permissions_boundary = var.permissions_boundary
  managed_policy_arns  = ["arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
}

resource "aws_eks_addon" "this" {
  for_each = var.addons

  cluster_name  = var.cluster_name
  addon_name    = each.key
  addon_version = each.value.version

  configuration_values        = each.value.configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = each.value.resolve_conflicts_on_update

  dynamic "pod_identity_association" {
    for_each = contains(keys(local.service_accounts), each.key) ? [each.key] : []

    content {
      service_account = local.service_accounts[pod_identity_association.value]
      role_arn        = each.value.pod_identity_role_arn != null ? each.value.pod_identity_role_arn : module.ebs_csi_role[0].role_arn
    }
  }

  tags = merge(module.labels.tags, { Name = "${var.cluster_name}-${each.key}" })

  # The driver's role must have its policy before the driver starts; the Pod Identity agent must run before
  # anything uses an association.
  depends_on = [module.ebs_csi_role]

  lifecycle {
    precondition {
      condition     = !contains(keys(var.addons), local.ebs_csi_addon) || contains(keys(var.addons), local.agent_addon)
      error_message = "aws-ebs-csi-driver gets its credentials through Pod Identity, so eks-pod-identity-agent must be in addons too."
    }
  }
}
