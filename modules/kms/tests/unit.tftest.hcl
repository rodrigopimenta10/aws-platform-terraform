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
  project     = "platform"
  environment = "dev"
  owner       = "platform-team"
  purpose     = "logs"
  description = "Encrypts platform logs"
}

run "defaults_rotate_yearly_and_only_delegate_to_iam" {
  command = plan

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == true && aws_kms_key.this.rotation_period_in_days == 365 && aws_kms_key.this.deletion_window_in_days == 30
    error_message = "Rotation is always on, yearly, with the longest deletion window by default."
  }

  assert {
    condition     = aws_kms_alias.this.name == "alias/platform-dev-logs" && aws_kms_key.this.tags["Name"] == "platform-dev-logs"
    error_message = "Alias and Name tag should come from the labels module."
  }

  assert {
    condition = (
      length(jsondecode(aws_kms_key.this.policy).Statement) == 1 &&
      jsondecode(aws_kms_key.this.policy).Statement[0].Sid == "EnableIAMPolicies" &&
      jsondecode(aws_kms_key.this.policy).Statement[0].Principal.AWS == "arn:aws:iam::123456789012:root"
    )
    error_message = "With no administrators, users or services the policy should hold only the IAM delegation statement."
  }
}

run "administrators_cannot_use_the_key_and_users_cannot_manage_it" {
  command = plan

  variables {
    key_administrator_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
    key_user_arns          = ["arn:aws:iam::123456789012:role/app"]
  }

  assert {
    condition     = length(jsondecode(aws_kms_key.this.policy).Statement) == 3
    error_message = "Expect the root, administrator and user statements."
  }

  assert {
    condition = (
      !contains(jsondecode(aws_kms_key.this.policy).Statement[1].Action, "kms:Decrypt") &&
      !contains(jsondecode(aws_kms_key.this.policy).Statement[1].Action, "kms:Encrypt") &&
      !contains(jsondecode(aws_kms_key.this.policy).Statement[1].Action, "kms:GenerateDataKey*") &&
      !contains(jsondecode(aws_kms_key.this.policy).Statement[1].Action, "kms:*")
    )
    error_message = "Administrators must not be given any data-use action."
  }

  assert {
    condition = (
      contains(jsondecode(aws_kms_key.this.policy).Statement[2].Action, "kms:Decrypt") &&
      !contains(jsondecode(aws_kms_key.this.policy).Statement[2].Action, "kms:ScheduleKeyDeletion") &&
      !contains(jsondecode(aws_kms_key.this.policy).Statement[2].Action, "kms:Put*")
    )
    error_message = "Users may decrypt but must not manage the key."
  }
}

run "service_grants_carry_the_encryption_context_condition" {
  command = plan

  variables {
    service_grants = {
      CloudWatchLogs = {
        service            = "logs.us-east-1.amazonaws.com"
        encryption_context = { "aws:logs:arn" = "arn:aws:logs:us-east-1:123456789012:log-group:/platform/app" }
      }
      Ecr = {
        service = "ecr.amazonaws.com"
      }
    }
  }

  assert {
    condition = (
      jsondecode(aws_kms_key.this.policy).Statement[1].Sid == "ServiceCloudWatchLogs" &&
      jsondecode(aws_kms_key.this.policy).Statement[1].Principal.Service == "logs.us-east-1.amazonaws.com" &&
      jsondecode(aws_kms_key.this.policy).Statement[1].Condition.StringEquals["kms:EncryptionContext:aws:logs:arn"] == "arn:aws:logs:us-east-1:123456789012:log-group:/platform/app"
    )
    error_message = "A grant with an encryption context must be limited by that context."
  }

  assert {
    condition     = !can(jsondecode(aws_kms_key.this.policy).Statement[2].Condition)
    error_message = "A grant without an encryption context should have no condition."
  }
}

run "rotation_period_is_configurable" {
  command = plan

  variables {
    rotation_period_in_days = 90
    deletion_window_in_days = 7
  }

  assert {
    condition     = aws_kms_key.this.rotation_period_in_days == 90 && aws_kms_key.this.deletion_window_in_days == 7
    error_message = "Rotation period and deletion window should follow the variables."
  }
}

run "rejects_a_bad_purpose" {
  command = plan
  variables {
    purpose = "Logs"
  }
  expect_failures = [var.purpose]
}

run "rejects_an_administrator_that_is_not_an_iam_arn" {
  command = plan
  variables {
    key_administrator_arns = ["*"]
  }
  expect_failures = [var.key_administrator_arns]
}

run "rejects_a_user_that_is_not_an_iam_arn" {
  command = plan
  variables {
    key_user_arns = ["alice"]
  }
  expect_failures = [var.key_user_arns]
}

run "rejects_a_service_that_is_not_a_principal" {
  command = plan
  variables {
    service_grants = { Bad = { service = "everyone" } }
  }
  expect_failures = [var.service_grants]
}

run "rejects_a_grant_name_with_punctuation" {
  command = plan
  variables {
    service_grants = { "bad-name" = { service = "ecr.amazonaws.com" } }
  }
  expect_failures = [var.service_grants]
}

run "rejects_rotation_that_is_too_frequent" {
  command = plan
  variables {
    rotation_period_in_days = 30
  }
  expect_failures = [var.rotation_period_in_days]
}

run "rejects_a_short_deletion_window" {
  command = plan
  variables {
    deletion_window_in_days = 3
  }
  expect_failures = [var.deletion_window_in_days]
}

run "rejects_a_vague_description" {
  command = plan
  variables {
    description = "key"
  }
  expect_failures = [var.description]
}
