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
  project          = "platform"
  environment      = "dev"
  owner            = "platform-team"
  allowed_services = ["s3", "logs", "kms"]
}

run "allows_listed_services_and_denies_escalation" {
  command = plan

  assert {
    condition     = aws_iam_policy.boundary.name == "platform-dev-boundary"
    error_message = "Name comes from labels."
  }

  assert {
    condition     = local.statements[0].Effect == "Allow" && local.statements[0].Action == ["kms:*", "logs:*", "s3:*"]
    error_message = "The Allow lists exactly the allowed services as <service>:*, sorted."
  }

  assert {
    condition     = contains(jsondecode(aws_iam_policy.boundary.policy).Statement[1].Action, "iam:CreateUser") && contains(jsondecode(aws_iam_policy.boundary.policy).Statement[1].Action, "iam:CreateAccessKey")
    error_message = "Long-lived identities must be denied."
  }
}

run "new_roles_must_carry_this_same_boundary" {
  command = plan

  assert {
    condition = (
      local.statements[2].Effect == "Deny" &&
      contains(local.statements[2].Action, "iam:CreateRole") &&
      contains(local.statements[2].Action, "iam:PutRolePermissionsBoundary") &&
      local.statements[2].Condition.StringNotEquals["iam:PermissionsBoundary"] == "arn:aws:iam::123456789012:policy/platform-dev-boundary"
    )
    error_message = "CreateRole and PutRolePermissionsBoundary are denied unless the boundary is this policy's own ARN."
  }

  assert {
    condition     = local.statements[3].Action == "iam:DeleteRolePermissionsBoundary" && local.statements[4].Resource == "arn:aws:iam::123456789012:policy/platform-dev-boundary"
    error_message = "The boundary can't be removed from a role or edited."
  }
}

run "region_deny_exempts_global_services" {
  command = plan

  variables {
    allowed_regions = ["us-east-1", "eu-west-1"]
  }

  assert {
    condition     = local.statements[5].Effect == "Deny" && jsonencode(local.statements[5].Condition.StringNotEquals["aws:RequestedRegion"]) == jsonencode(["us-east-1", "eu-west-1"])
    error_message = "Requests outside the allowed regions are denied."
  }

  assert {
    condition     = contains(local.statements[5].NotAction, "iam:*") && contains(local.statements[5].NotAction, "sts:*") && !contains(local.statements[5].NotAction, "s3:*")
    error_message = "IAM and STS are global and exempt; regional services are not."
  }
}

run "rejects_empty_service_list" {
  command = plan
  variables {
    allowed_services = []
  }
  expect_failures = [var.allowed_services]
}

run "rejects_service_wildcards" {
  command = plan
  variables {
    allowed_services = ["*"]
  }
  expect_failures = [var.allowed_services]
}

run "rejects_bad_region" {
  command = plan
  variables {
    allowed_regions = ["moon-1"]
  }
  expect_failures = [var.allowed_regions]
}
