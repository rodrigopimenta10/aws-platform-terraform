# Unit tests: mock provider, plan only. No network, no emulator.
mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/platform-dev-orders-role"
    }
  }
}

variables {
  project              = "platform"
  environment          = "dev"
  owner                = "platform-team"
  name                 = "orders"
  cluster_name         = "platform-dev-eks"
  namespace            = "orders"
  service_account      = "orders-api"
  permissions_boundary = "arn:aws:iam::123456789012:policy/platform-dev-boundary"
}

run "associates_the_role_with_one_service_account" {
  command = plan

  assert {
    condition     = aws_eks_pod_identity_association.this.cluster_name == "platform-dev-eks" && aws_eks_pod_identity_association.this.namespace == "orders" && aws_eks_pod_identity_association.this.service_account == "orders-api"
    error_message = "The association names exactly one cluster, namespace and service account."
  }

  assert {
    condition     = aws_eks_pod_identity_association.this.tags["managed-by"] == "terraform" && aws_eks_pod_identity_association.this.tags["Name"] == "platform-dev-eks-orders-orders-api"
    error_message = "The association carries the standard tags and a Name."
  }
}

run "role_trusts_only_the_pods_service_for_this_cluster" {
  command = plan

  assert {
    condition     = jsondecode(output.trust_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com"
    error_message = "Only the EKS pods service may assume the role, not an OIDC provider or an account."
  }

  assert {
    condition     = jsondecode(output.trust_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    error_message = "The trust policy pins the source account (confused-deputy guard)."
  }

  assert {
    condition     = endswith(jsondecode(output.trust_policy).Statement[0].Condition.ArnEquals["aws:SourceArn"], ":cluster/platform-dev-eks")
    error_message = "The trust policy pins the cluster."
  }

  assert {
    condition     = contains(jsondecode(output.trust_policy).Statement[0].Action, "sts:TagSession")
    error_message = "sts:TagSession is required for Pod Identity."
  }
}

run "the_role_has_the_boundary" {
  command = plan

  assert {
    condition     = module.role.permissions_boundary == "arn:aws:iam::123456789012:policy/platform-dev-boundary"
    error_message = "The role is created through iam-role, so it carries the boundary."
  }
}

run "no_inline_policy_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_role_policy.this) == 0
    error_message = "Without policy_json there is no inline policy."
  }
}

run "inline_policy_is_attached_to_the_role" {
  command = plan

  variables {
    policy_json = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["arn:aws:s3:::example-orders-bucket/*"]
      }]
    })
  }

  assert {
    condition     = length(aws_iam_role_policy.this) == 1 && aws_iam_role_policy.this[0].name == "orders-inline"
    error_message = "policy_json becomes one inline policy on the role."
  }
}

run "rejects_bad_names" {
  command = plan

  variables {
    name = "Orders"
  }

  expect_failures = [var.name]
}

run "rejects_a_bad_cluster_name" {
  command = plan

  variables {
    cluster_name = "bad name"
  }

  expect_failures = [var.cluster_name]
}

run "rejects_a_bad_namespace" {
  command = plan

  variables {
    namespace = "Orders_NS"
  }

  expect_failures = [var.namespace]
}

run "rejects_a_wildcard_service_account" {
  command = plan

  variables {
    service_account = "*"
  }

  expect_failures = [var.service_account]
}

run "rejects_a_non_json_policy" {
  command = plan

  variables {
    policy_json = "not json"
  }

  expect_failures = [var.policy_json]
}

run "rejects_a_bad_boundary_arn" {
  command = plan

  variables {
    permissions_boundary = "boundary"
  }

  expect_failures = [var.permissions_boundary]
}
