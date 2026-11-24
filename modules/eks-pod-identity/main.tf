# One workload's AWS identity on EKS, through Pod Identity: an IAM role that only the EKS pods service may
# assume, an optional inline policy, and the association that ties the role to one Kubernetes service
# account. The cluster needs the eks-pod-identity-agent add-on (modules/eks-addons) for the credentials to
# reach the pod. There is no OIDC provider and no annotation on the service account: see ADR 0005.

module "labels" {
  source = "../labels"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  components  = [var.name]
}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

# The trust policy is the same for every cluster and workload. aws:SourceAccount stops the EKS service from
# being tricked into acting for another account (the confused-deputy problem); aws:SourceArn narrows it to
# associations on this one cluster. sts:TagSession lets the service tag the session with the cluster,
# namespace and service account, which policies can use as conditions.
locals {
  trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnEquals    = { "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:eks:*:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}" }
      }
    }]
  })
}

module "role" {
  source = "../iam-role"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  name        = var.name
  description = "Assumed by ${var.namespace}/${var.service_account} in ${var.cluster_name} through EKS Pod Identity"

  assume_role_policy = local.trust_policy

  permissions_boundary = var.permissions_boundary
  managed_policy_arns  = var.managed_policy_arns
}

# Inline, not a separate managed policy: it lives and dies with this one workload's role, and its ARN would
# be unknown at plan time, which a for_each over attachments cannot accept.
resource "aws_iam_role_policy" "this" {
  count = var.policy_json == null ? 0 : 1

  name   = "${var.name}-inline"
  role   = module.role.role_name
  policy = var.policy_json
}

resource "aws_eks_pod_identity_association" "this" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = module.role.role_arn

  tags = merge(module.labels.tags, { Name = "${var.cluster_name}-${var.namespace}-${var.service_account}" })
}
