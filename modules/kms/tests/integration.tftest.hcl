# Integration test: applies the module against a local Moto server (see ADR 0001). No real AWS.
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true

  endpoints {
    kms = "http://127.0.0.1:5000"
    sts = "http://127.0.0.1:5000"
  }
}

variables {
  project     = "platform"
  environment = "dev"
  owner       = "platform-team"
  purpose     = "data"
  description = "Encrypts platform data stores"

  key_administrator_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
  key_user_arns          = ["arn:aws:iam::123456789012:role/app"]
  service_grants = {
    CloudWatchLogs = {
      service            = "logs.us-east-1.amazonaws.com"
      encryption_context = { "aws:logs:arn" = "arn:aws:logs:us-east-1:123456789012:log-group:/platform/app" }
    }
  }
}

run "creates_a_rotating_key_with_an_alias" {
  command = apply

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == true && aws_kms_key.this.is_enabled == true
    error_message = "The key should be enabled with rotation on."
  }

  assert {
    condition     = aws_kms_alias.this.name == "alias/platform-dev-data" && aws_kms_alias.this.target_key_id == aws_kms_key.this.key_id
    error_message = "The alias should point at the key."
  }

  assert {
    condition     = length(jsondecode(aws_kms_key.this.policy).Statement) == 4
    error_message = "Root, administrator, user and one service statement expected."
  }

  assert {
    condition     = output.key_arn == aws_kms_key.this.arn && output.key_id == aws_kms_key.this.key_id && output.alias_name == "alias/platform-dev-data" && output.alias_arn == aws_kms_alias.this.arn
    error_message = "Outputs should expose the key and its alias."
  }
}
