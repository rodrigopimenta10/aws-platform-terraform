# Unit tests: mock provider, plan only. No network, no emulator.
mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

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

  # The flow log points at a log group and a role by ARN, and the AWS provider checks that both
  # values are ARNs. A mock provider makes up a random string for a value only AWS would know.
  # Under OpenTofu 1.13 the plan then failed with "invalid ARN" for both; under Terraform 1.17 it
  # did not. With these two stand-ins the tests pass under both tools.
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/vpc/flow-logs/platform-dev-flow-logs"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/platform-dev-flow-logs"
    }
  }
}

variables {
  project     = "platform"
  environment = "dev"
  owner       = "platform-team"
  vpc_id      = "vpc-0123456789abcdef0"
}

run "defaults_record_all_traffic_into_an_encrypted_30_day_log_group" {
  command = plan

  assert {
    condition     = aws_flow_log.this.log_destination_type == "cloud-watch-logs" && aws_flow_log.this.traffic_type == "ALL" && aws_flow_log.this.max_aggregation_interval == 600
    error_message = "Defaults: CloudWatch Logs destination, ALL traffic, 600 second aggregation."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/vpc/flow-logs/platform-dev-flow-logs" && aws_cloudwatch_log_group.this.retention_in_days == 365
    error_message = "Log group name comes from the labels module and retention defaults to one year."
  }

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == true && aws_kms_key.this.deletion_window_in_days == 30
    error_message = "The key rotates yearly and keeps the longest deletion window by default."
  }

  assert {
    condition     = aws_kms_alias.this.name == "alias/platform-dev-flow-logs"
    error_message = "The alias should come from the labels module."
  }
}

run "key_policy_limits_cloudwatch_logs_to_this_log_group" {
  command = plan

  assert {
    condition = (
      length(jsondecode(aws_kms_key.this.policy).Statement) == 2 &&
      jsondecode(aws_kms_key.this.policy).Statement[1].Principal.Service == "logs.us-east-1.amazonaws.com" &&
      jsondecode(aws_kms_key.this.policy).Statement[1].Condition.ArnEquals["kms:EncryptionContext:aws:logs:arn"] == "arn:aws:logs:us-east-1:123456789012:log-group:/aws/vpc/flow-logs/platform-dev-flow-logs"
    )
    error_message = "The CloudWatch Logs statement must be tied to this log group's ARN through the encryption context."
  }
}

run "role_is_least_privilege" {
  command = plan

  assert {
    condition = (
      jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.Service == "vpc-flow-logs.amazonaws.com" &&
      jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    )
    error_message = "Only the flow logs service, for this account, may assume the role."
  }

  assert {
    condition = (
      !contains(jsondecode(aws_iam_role_policy.this.policy).Statement[0].Resource, "*") &&
      length(jsondecode(aws_iam_role_policy.this.policy).Statement[0].Resource) == 2 &&
      alltrue([for a in jsondecode(aws_iam_role_policy.this.policy).Statement[0].Action : startswith(a, "logs:")])
    )
    error_message = "The role may only use a few logs actions on the one log group, never Resource *."
  }

  assert {
    condition     = aws_iam_role.this.permissions_boundary == null
    error_message = "No boundary by default."
  }
}

run "boundary_is_attached_when_given" {
  command = plan

  variables {
    permissions_boundary = "arn:aws:iam::123456789012:policy/platform-live-drill-boundary"
  }

  assert {
    condition     = aws_iam_role.this.permissions_boundary == "arn:aws:iam::123456789012:policy/platform-live-drill-boundary"
    error_message = "The permissions boundary should be set on the role."
  }
}

run "options_flow_through" {
  command = plan

  variables {
    retention_in_days           = 7
    traffic_type                = "REJECT"
    max_aggregation_interval    = 60
    kms_deletion_window_in_days = 7
  }

  assert {
    condition = (
      aws_cloudwatch_log_group.this.retention_in_days == 7 &&
      aws_flow_log.this.traffic_type == "REJECT" &&
      aws_flow_log.this.max_aggregation_interval == 60 &&
      aws_kms_key.this.deletion_window_in_days == 7
    )
    error_message = "Variables should reach the resources."
  }
}

run "rejects_never_expire_retention" {
  command = plan

  variables {
    retention_in_days = 0
  }

  expect_failures = [var.retention_in_days]
}

run "rejects_odd_retention" {
  command = plan

  variables {
    retention_in_days = 45
  }

  expect_failures = [var.retention_in_days]
}

run "rejects_bad_traffic_type" {
  command = plan

  variables {
    traffic_type = "some"
  }

  expect_failures = [var.traffic_type]
}

run "rejects_bad_aggregation_interval" {
  command = plan

  variables {
    max_aggregation_interval = 300
  }

  expect_failures = [var.max_aggregation_interval]
}

run "rejects_bad_deletion_window" {
  command = plan

  variables {
    kms_deletion_window_in_days = 3
  }

  expect_failures = [var.kms_deletion_window_in_days]
}

run "rejects_bad_vpc_id" {
  command = plan

  variables {
    vpc_id = "not-a-vpc"
  }

  expect_failures = [var.vpc_id]
}

run "rejects_bad_boundary" {
  command = plan

  variables {
    permissions_boundary = "boundary"
  }

  expect_failures = [var.permissions_boundary]
}
