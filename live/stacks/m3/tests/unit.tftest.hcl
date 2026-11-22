# Unit tests: mock provider, plan only. modules/ecr and modules/kms have their own tests; these check what this
# root module decides: live tags, drill-friendly settings and the names the console links depend on.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"]
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/platform-live-eks-cluster"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }
}

variables {
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/platform-live-boundary"
}

run "repositories_follow_the_drill_conventions" {
  command = plan

  assert {
    condition     = output.ecr_api_repository_name == "platform-live-api" && output.ecr_worker_repository_name == "platform-live-worker"
    error_message = "Repositories should be named platform-live-<key> (ADR 0002)."
  }

  assert {
    condition     = output.tags["environment"] == "live" && output.tags["live-stack"] == "m3" && output.tags["project"] == "platform"
    error_message = "Every resource should carry the live tags plus live-stack = m3."
  }
}

run "eks_cluster_fits_the_drill_limits" {
  command = plan

  assert {
    condition     = output.eks_cluster_name == "platform-live-eks"
    error_message = "The cluster should be named platform-live-eks (ADR 0002); the log group grant and the VPC tags rely on it."
  }

  assert {
    condition     = length(module.vpc.eks_subnet_ids) == 2 && length(module.vpc.nat_gateway_ids) == 1
    error_message = "Two private subnets and exactly one NAT gateway: nodes need a way out, and the plan gate allows one."
  }

  assert {
    condition     = module.eks.log_group_name == "/aws/eks/platform-live-eks/cluster"
    error_message = "The log group name must match the one the KMS grant is limited to."
  }
}

run "node_groups_fit_the_drill_limits" {
  command = plan

  assert {
    condition     = output.eks_system_node_group_name == "platform-live-nodes-system" && length(output.eks_node_group_names) == 2
    error_message = "One system group and one batch group, named platform-live-nodes-<key>; the console links use the name."
  }

  assert {
    condition     = alltrue([for k, g in module.nodes.node_group_names : can(regex("^platform-live-nodes-", g))])
    error_message = "Node groups should follow the labels module naming."
  }
}

run "rejects_a_malformed_region" {
  command = plan

  variables {
    region = "mars"
  }

  expect_failures = [var.region]
}
