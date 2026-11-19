# Unit tests: mock provider, plan only. modules/kms has its own unit and Moto tests; these check what this root
# module decides: live tags, an alias that follows the naming ADR, and the log group the key is scoped to.
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
}

variables {
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/platform-live-drill-boundary"
}

run "key_and_log_group_follow_the_drill_conventions" {
  command = plan

  assert {
    condition     = output.kms_alias_name == "alias/platform-live-logs"
    error_message = "The alias should be alias/platform-live-logs (ADR 0002)."
  }

  assert {
    condition     = aws_cloudwatch_log_group.app.name == "/aws/platform-live/app" && aws_cloudwatch_log_group.app.retention_in_days == 365
    error_message = "The log group the key is scoped to should have a fixed name and one year of retention."
  }

  assert {
    condition     = output.tags["environment"] == "live" && output.tags["live-stack"] == "m2" && output.tags["project"] == "platform"
    error_message = "Every resource should carry the live tags plus live-stack = m2."
  }
}

run "rejects_a_malformed_region" {
  command = plan

  variables {
    region = "mars"
  }

  expect_failures = [var.region]
}

run "worker_role_carries_the_drill_boundary" {
  command = plan

  assert {
    condition     = output.worker_role_name == "platform-live-worker" && module.worker_role.permissions_boundary == "arn:aws:iam::123456789012:policy/platform-live-drill-boundary"
    error_message = "The worker role should carry the boundary passed in by the workflow."
  }

  assert {
    condition     = output.boundary_policy_name == "platform-live-boundary"
    error_message = "The boundary policy follows the naming ADR."
  }
}

run "account_baseline_is_on" {
  command = plan

  assert {
    condition     = output.ebs_encryption_by_default_enabled == "true"
    error_message = "The drill should turn EBS encryption by default on."
  }
}
