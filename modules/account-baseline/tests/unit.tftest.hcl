# Unit tests: mock provider, plan only. No network, no emulator.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

run "defaults_are_secure" {
  command = plan

  assert {
    condition     = aws_ebs_encryption_by_default.this.enabled == true
    error_message = "EBS encryption by default should be on by default."
  }

  assert {
    condition     = length(aws_ebs_default_kms_key.this) == 0
    error_message = "Without a key ARN the AWS-managed aws/ebs key stays the default."
  }

  assert {
    condition = alltrue([
      aws_s3_account_public_access_block.this.block_public_acls,
      aws_s3_account_public_access_block.this.block_public_policy,
      aws_s3_account_public_access_block.this.ignore_public_acls,
      aws_s3_account_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "All four S3 public access settings must be on, with no variable to loosen them."
  }

  assert {
    condition = (
      aws_iam_account_password_policy.this.minimum_password_length == 14 &&
      aws_iam_account_password_policy.this.max_password_age == 90 &&
      aws_iam_account_password_policy.this.password_reuse_prevention == 24 &&
      aws_iam_account_password_policy.this.require_symbols &&
      aws_iam_account_password_policy.this.require_numbers &&
      aws_iam_account_password_policy.this.require_uppercase_characters &&
      aws_iam_account_password_policy.this.require_lowercase_characters
    )
    error_message = "The default password policy should be 14 characters, all character classes, 90 days, 24 remembered."
  }
}

run "custom_kms_key_becomes_the_default_key" {
  command = plan

  variables {
    ebs_default_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  assert {
    condition     = length(aws_ebs_default_kms_key.this) == 1
    error_message = "A key ARN should create the default key resource."
  }
}

run "key_is_ignored_when_encryption_is_off" {
  command = plan

  variables {
    enable_ebs_encryption_by_default = false
    ebs_default_kms_key_arn          = "arn:aws:kms:us-east-1:123456789012:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  assert {
    condition     = length(aws_ebs_default_kms_key.this) == 0
    error_message = "A default key makes no sense while default encryption is off."
  }
}

run "rejects_an_alias_instead_of_a_key_arn" {
  command = plan

  variables {
    ebs_default_kms_key_arn = "alias/platform-dev-ebs"
  }

  expect_failures = [var.ebs_default_kms_key_arn]
}

run "rejects_a_short_password_length" {
  command = plan

  variables {
    password_minimum_length = 8
  }

  expect_failures = [var.password_minimum_length]
}

run "rejects_reuse_prevention_out_of_range" {
  command = plan

  variables {
    password_reuse_prevention = 0
  }

  expect_failures = [var.password_reuse_prevention]
}

run "rejects_max_age_out_of_range" {
  command = plan

  variables {
    password_max_age_days = 2000
  }

  expect_failures = [var.password_max_age_days]
}
