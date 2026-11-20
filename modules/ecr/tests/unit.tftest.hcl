# Unit tests: mock provider, plan only. No network, no emulator.
mock_provider "aws" {}

variables {
  project     = "platform"
  environment = "dev"
  owner       = "platform-team"
  kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"

  repositories = {
    api    = {}
    worker = { keep_last_images = 10, force_delete = true }
  }
}

run "repositories_are_immutable_scanned_and_kms_encrypted" {
  command = plan

  assert {
    condition     = length(aws_ecr_repository.this) == 2 && aws_ecr_repository.this["api"].name == "platform-dev-api" && aws_ecr_repository.this["worker"].name == "platform-dev-worker"
    error_message = "One repository per key, named by the labels module."
  }

  assert {
    condition = alltrue([
      for r in values(aws_ecr_repository.this) :
      r.image_tag_mutability == "IMMUTABLE" &&
      r.image_scanning_configuration[0].scan_on_push == true &&
      r.encryption_configuration[0].encryption_type == "KMS" &&
      r.encryption_configuration[0].kms_key == "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    ])
    error_message = "Every repository needs immutable tags, scan on push and the customer-managed key."
  }

  assert {
    condition     = aws_ecr_repository.this["api"].force_delete == false && aws_ecr_repository.this["worker"].force_delete == true
    error_message = "force_delete is off unless asked for."
  }

  assert {
    condition     = aws_ecr_repository.this["api"].tags["Name"] == "platform-dev-api" && aws_ecr_repository.this["api"].tags["managed-by"] == "terraform"
    error_message = "Name and standard tags come from the labels module."
  }
}

run "lifecycle_expires_untagged_then_keeps_the_last_n" {
  command = plan

  assert {
    condition = (
      jsondecode(aws_ecr_lifecycle_policy.this["api"].policy).rules[0].selection.tagStatus == "untagged" &&
      jsondecode(aws_ecr_lifecycle_policy.this["api"].policy).rules[0].selection.countNumber == 7 &&
      jsondecode(aws_ecr_lifecycle_policy.this["api"].policy).rules[0].rulePriority == 1
    )
    error_message = "Rule 1 should expire untagged images after the default 7 days."
  }

  assert {
    condition = (
      jsondecode(aws_ecr_lifecycle_policy.this["api"].policy).rules[1].selection.countType == "imageCountMoreThan" &&
      jsondecode(aws_ecr_lifecycle_policy.this["api"].policy).rules[1].selection.countNumber == 30 &&
      jsondecode(aws_ecr_lifecycle_policy.this["worker"].policy).rules[1].selection.countNumber == 10
    )
    error_message = "Rule 2 should keep 30 images by default and each repository's own keep_last_images when set."
  }
}

run "untagged_expiry_is_configurable" {
  command = plan

  variables {
    untagged_expiry_days = 1
  }

  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.this["api"].policy).rules[0].selection.countNumber == 1
    error_message = "untagged_expiry_days should feed rule 1."
  }
}

run "rejects_an_empty_repository_map" {
  command = plan

  variables {
    repositories = {}
  }

  expect_failures = [var.repositories]
}

run "rejects_a_bad_repository_key" {
  command = plan

  variables {
    repositories = { "Bad_Name" = {} }
  }

  expect_failures = [var.repositories]
}

run "rejects_keep_last_images_out_of_range" {
  command = plan

  variables {
    repositories = { api = { keep_last_images = 0 } }
  }

  expect_failures = [var.repositories]
}

run "rejects_a_key_alias_instead_of_an_arn" {
  command = plan

  variables {
    kms_key_arn = "alias/platform-dev-ecr"
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_untagged_expiry_out_of_range" {
  command = plan

  variables {
    untagged_expiry_days = 0
  }

  expect_failures = [var.untagged_expiry_days]
}
