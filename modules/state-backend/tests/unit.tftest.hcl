# Unit tests: mock provider, plan only. No network, no emulator.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
}

variables {
  project     = "platform"
  environment = "dev"
  owner       = "platform-team"
}

run "names_bucket_after_account_and_region" {
  command = plan

  assert {
    condition     = aws_s3_bucket.state.bucket == "platform-dev-tfstate-123456789012-us-east-1"
    error_message = "Bucket name should be <prefix>-tfstate-<account>-<region>."
  }

  assert {
    condition     = aws_kms_alias.state.name == "alias/platform-dev-tfstate"
    error_message = "KMS alias should be alias/<prefix>-tfstate."
  }
}

run "bucket_is_not_force_destroyable_by_default" {
  command = plan

  assert {
    condition     = aws_s3_bucket.state.force_destroy == false
    error_message = "force_destroy must default to false."
  }
}

run "versioning_and_encryption_are_on" {
  command = plan

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be enabled."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.state.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms"
    error_message = "Default encryption must be SSE-KMS."
  }

  assert {
    condition     = aws_kms_key.state.enable_key_rotation == true
    error_message = "KMS key rotation must be enabled."
  }
}

run "public_access_is_fully_blocked" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.state.block_public_acls,
      aws_s3_bucket_public_access_block.state.block_public_policy,
      aws_s3_bucket_public_access_block.state.ignore_public_acls,
      aws_s3_bucket_public_access_block.state.restrict_public_buckets,
    ])
    error_message = "All four public access block settings must be true."
  }
}

run "bucket_policy_denies_plain_http" {
  command = plan

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.state.policy).Statement[0].Effect == "Deny"
    error_message = "The TLS statement must be a Deny."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.state.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "The Deny must apply when aws:SecureTransport is false."
  }
}

run "lifecycle_expires_noncurrent_versions" {
  command = plan

  variables {
    noncurrent_version_expiration_days = 30
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.state.rule).noncurrent_version_expiration[0].noncurrent_days == 30
    error_message = "noncurrent_days should follow the variable."
  }

}

run "tags_come_from_labels" {
  command = plan

  assert {
    condition     = aws_s3_bucket.state.tags["managed-by"] == "terraform" && aws_s3_bucket.state.tags["owner"] == "platform-team"
    error_message = "Bucket should carry the standard tags."
  }
}

run "rejects_short_retention" {
  command = plan

  variables {
    noncurrent_version_expiration_days = 3
  }

  expect_failures = [var.noncurrent_version_expiration_days]
}

run "rejects_short_kms_deletion_window" {
  command = plan

  variables {
    kms_deletion_window_in_days = 3
  }

  expect_failures = [var.kms_deletion_window_in_days]
}
