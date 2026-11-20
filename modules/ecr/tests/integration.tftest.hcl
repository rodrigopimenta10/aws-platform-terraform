# Integration test: applies the module against a local Moto server (see ADR 0001). No real AWS.
# Builds a KMS key with modules/kms first, then the registry on top of it, the way a root module would.
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true

  endpoints {
    ecr = "http://127.0.0.1:5000"
    kms = "http://127.0.0.1:5000"
    sts = "http://127.0.0.1:5000"
  }
}

variables {
  project     = "platform"
  environment = "dev"
  owner       = "platform-team"
}

run "key" {
  command = apply

  module {
    source = "../kms"
  }

  variables {
    purpose     = "ecr"
    description = "Encrypts platform container images"
  }
}

run "repositories_exist_with_the_safe_settings" {
  command = apply

  variables {
    kms_key_arn = run.key.key_arn
    repositories = {
      api    = {}
      worker = { keep_last_images = 5, force_delete = true }
    }
  }

  assert {
    condition     = aws_ecr_repository.this["api"].image_tag_mutability == "IMMUTABLE" && aws_ecr_repository.this["api"].image_scanning_configuration[0].scan_on_push == true
    error_message = "Moto should report immutable tags and scan on push."
  }

  assert {
    condition     = aws_ecr_repository.this["api"].encryption_configuration[0].encryption_type == "KMS" && aws_ecr_repository.this["api"].encryption_configuration[0].kms_key == run.key.key_arn
    error_message = "The repository should be encrypted with the key from modules/kms."
  }

  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.this["worker"].policy).rules[1].selection.countNumber == 5
    error_message = "The stored lifecycle policy should keep the worker's last 5 images."
  }

  assert {
    condition     = output.repository_names["api"] == "platform-dev-api" && can(regex("platform-dev-worker$", output.repository_urls["worker"])) && can(regex(":repository/platform-dev-api$", output.repository_arns["api"]))
    error_message = "Outputs should expose names, URLs and ARNs for each repository."
  }
}
