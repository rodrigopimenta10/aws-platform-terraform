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
}

variables {
  project                          = "platform"
  environment                      = "dev"
  owner                            = "platform-team"
  cluster_name                     = "platform-dev-eks"
  region                           = "eu-west-1"
  karpenter_node_role_arn          = "arn:aws:iam::123456789012:role/platform-dev-nodes"
  karpenter_interruption_queue_arn = "arn:aws:sqs:eu-west-1:123456789012:platform-dev-karpenter"
}

run "creates_both_policies_with_labels_names" {
  command = plan

  assert {
    condition     = aws_iam_policy.lb_controller[0].name == "platform-dev-lb-controller" && aws_iam_policy.karpenter[0].name == "platform-dev-karpenter"
    error_message = "Policies are named <project>-<environment>-<component>."
  }

  assert {
    condition     = aws_iam_policy.karpenter[0].tags["managed-by"] == "terraform" && aws_iam_policy.lb_controller[0].tags["owner"] == "platform-team"
    error_message = "Policies carry the standard tags."
  }
}

run "policies_fit_the_managed_policy_size_limit" {
  command = plan

  # IAM rejects a managed policy over 6,144 characters (whitespace does not count; jsonencode has none).
  assert {
    condition     = length(output.lb_controller_policy_json) <= 6144
    error_message = "The Load Balancer Controller policy exceeds the 6144-character managed policy limit."
  }

  assert {
    condition     = length(output.karpenter_policy_json) <= 6144
    error_message = "The Karpenter policy exceeds the 6144-character managed policy limit."
  }
}

run "lb_controller_mutations_are_limited_by_cluster_tag" {
  command = plan

  assert {
    condition = length([
      for s in jsondecode(output.lb_controller_policy_json).Statement : s
      if contains(s.Action, "elasticloadbalancing:DeleteLoadBalancer") && try(s.Condition.Null["aws:ResourceTag/elbv2.k8s.aws/cluster"], "") == "false"
    ]) == 1
    error_message = "Deleting or changing a load balancer must require the controller's cluster tag on the resource."
  }

  assert {
    condition = length([
      for s in jsondecode(output.lb_controller_policy_json).Statement : s
      if contains(s.Action, "elasticloadbalancing:CreateLoadBalancer") && try(s.Condition.Null["aws:RequestTag/elbv2.k8s.aws/cluster"], "") == "false"
    ]) == 1
    error_message = "A new load balancer must be created with the cluster tag."
  }
}

run "lb_controller_has_no_wildcard_service_or_admin_action" {
  command = plan

  assert {
    condition     = length([for s in jsondecode(output.lb_controller_policy_json).Statement : s if anytrue([for a in s.Action : endswith(a, "*")])]) == 0
    error_message = "No statement may use a wildcard action."
  }
}

run "karpenter_is_scoped_to_the_cluster_and_region" {
  command = plan

  assert {
    condition = length([
      for s in jsondecode(output.karpenter_policy_json).Statement : s
      if s.Sid == "AllowScopedDeletion" && s.Condition.StringEquals["aws:ResourceTag/kubernetes.io/cluster/platform-dev-eks"] == "owned"
    ]) == 1
    error_message = "Terminating instances must require the cluster-owned tag."
  }

  assert {
    condition = alltrue([
      for s in jsondecode(output.karpenter_policy_json).Statement :
      !contains(["ec2:RunInstances", "ec2:TerminateInstances"], try(s.Action[0], "")) || can(regex("arn:aws:ec2:eu-west-1", jsonencode(s.Resource)))
    ])
    error_message = "EC2 launch and terminate resources are pinned to the cluster's region."
  }

  assert {
    condition     = length([for s in jsondecode(output.karpenter_policy_json).Statement : s if s.Sid == "AllowRegionalReadActions" && s.Condition.StringEquals["aws:RequestedRegion"] == "eu-west-1"]) == 1
    error_message = "Describe calls are limited to the cluster's region."
  }
}

run "karpenter_can_only_pass_the_node_role_to_ec2" {
  command = plan

  assert {
    condition = length([
      for s in jsondecode(output.karpenter_policy_json).Statement : s
      if s.Sid == "AllowPassingInstanceRole" && s.Resource == "arn:aws:iam::123456789012:role/platform-dev-nodes" && s.Condition.StringEquals["iam:PassedToService"][0] == "ec2.amazonaws.com"
    ]) == 1
    error_message = "iam:PassRole must name the node role and only EC2."
  }

  assert {
    condition     = length([for s in jsondecode(output.karpenter_policy_json).Statement : s if contains(s.Action, "iam:PassRole") && s.Resource == "*"]) == 0
    error_message = "iam:PassRole on * would let Karpenter escalate privileges."
  }
}

run "interruption_queue_statement_is_optional" {
  command = plan

  variables {
    karpenter_interruption_queue_arn = null
  }

  assert {
    condition     = length([for s in jsondecode(output.karpenter_policy_json).Statement : s if s.Sid == "AllowInterruptionQueueActions"]) == 0
    error_message = "Without a queue there must be no SQS statement."
  }
}

run "policies_can_be_switched_off" {
  command = plan

  variables {
    create_lb_controller_policy = false
    create_karpenter_policy     = false
  }

  assert {
    condition     = output.lb_controller_policy_arn == null && output.karpenter_policy_arn == null
    error_message = "Switched-off policies output null ARNs."
  }
}

run "karpenter_needs_a_node_role" {
  command = plan

  variables {
    karpenter_node_role_arn = null
  }
  expect_failures = [aws_iam_policy.karpenter]
}

run "rejects_bad_region" {
  command = plan

  variables {
    region = "europe"
  }
  expect_failures = [var.region]
}

run "rejects_bad_cluster_name" {
  command = plan

  variables {
    cluster_name = "bad name!"
  }
  expect_failures = [var.cluster_name]
}

run "rejects_non_role_node_arn" {
  command = plan

  variables {
    karpenter_node_role_arn = "arn:aws:iam::123456789012:user/bob"
  }
  expect_failures = [var.karpenter_node_role_arn]
}

run "rejects_non_sqs_queue_arn" {
  command = plan

  variables {
    karpenter_interruption_queue_arn = "arn:aws:s3:::bucket"
  }
  expect_failures = [var.karpenter_interruption_queue_arn]
}
