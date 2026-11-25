# IAM policies for the two controllers that most clusters run next to the control plane: the AWS Load Balancer
# Controller (turns Ingress and Service objects into load balancers) and Karpenter (starts and stops EC2
# nodes as pods need them). Each is a customer-managed policy with its JSON also exposed as an output.
#
# This module makes policies and nothing else. It makes no role, so it needs no permissions boundary: a policy
# grants nothing until a role carries it. A consumer attaches the policy ARN to a role made with
# modules/eks-pod-identity (managed_policy_arns), which is where the boundary is enforced.

module "labels" {
  source = "../labels"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  components  = ["lb-controller", "karpenter"]
}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
}
