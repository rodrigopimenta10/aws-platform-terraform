# Integration test: applies the module against a local Moto server (see ADR 0001). No real AWS.
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  s3_use_path_style           = true

  endpoints {
    s3  = "http://127.0.0.1:5000"
    kms = "http://127.0.0.1:5000"
    sts = "http://127.0.0.1:5000"
  }
}

variables {
  project       = "platform"
  environment   = "dev"
  owner         = "platform-team"
  force_destroy = true
}

run "creates_state_backend" {
  command = apply

  assert {
    condition     = output.bucket_name == "platform-dev-tfstate-123456789012-us-east-1"
    error_message = "Unexpected bucket name."
  }

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning should be enabled after apply."
  }

  assert {
    condition     = output.backend_config.use_lockfile == true && output.backend_config.encrypt == true
    error_message = "backend_config should enable encryption and native locking."
  }

  assert {
    condition     = aws_kms_key.state.enable_key_rotation == true
    error_message = "Key rotation should be on after apply."
  }

  assert {
    condition     = can(regex("^arn:aws:kms:", output.kms_key_arn))
    error_message = "kms_key_arn should be a KMS ARN."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.state.block_public_policy == true
    error_message = "Public access block should be applied."
  }
}
