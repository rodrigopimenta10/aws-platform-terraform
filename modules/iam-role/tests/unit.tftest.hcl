# Unit tests: mock provider, plan only. No network, no emulator.
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
  project              = "platform"
  environment          = "dev"
  owner                = "platform-team"
  name                 = "worker"
  description          = "Example worker role"
  permissions_boundary = "arn:aws:iam::123456789012:policy/platform-dev-boundary"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

run "role_carries_the_boundary" {
  command = plan

  assert {
    condition     = aws_iam_role.this.name == "platform-dev-worker" && aws_iam_role.this.permissions_boundary == "arn:aws:iam::123456789012:policy/platform-dev-boundary"
    error_message = "Role name comes from labels and the boundary is set on the role."
  }

  assert {
    condition     = aws_iam_role.this.max_session_duration == 3600
    error_message = "Sessions last an hour by default."
  }
}

run "role_without_a_boundary_is_rejected" {
  command = plan

  variables {
    permissions_boundary = null
  }

  expect_failures = [aws_iam_role.this]
}

run "attaches_managed_policies" {
  command = plan

  variables {
    managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.this) == 1
    error_message = "Each managed policy gets an attachment."
  }
}

run "rejects_malformed_boundary_arn" {
  command = plan
  variables {
    permissions_boundary = "not-an-arn"
  }
  expect_failures = [var.permissions_boundary]
}

run "rejects_trust_policy_that_is_not_a_policy" {
  command = plan
  variables {
    assume_role_policy = "{}"
  }
  expect_failures = [var.assume_role_policy]
}

run "rejects_bad_session_duration" {
  command = plan
  variables {
    max_session_duration = 60
  }
  expect_failures = [var.max_session_duration]
}
