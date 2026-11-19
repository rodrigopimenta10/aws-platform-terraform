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
    ec2       = "http://127.0.0.1:5000"
    iam       = "http://127.0.0.1:5000"
    s3        = "http://127.0.0.1:5000"
    s3control = "http://127.0.0.1:5000"
    sts       = "http://127.0.0.1:5000"
  }
}

run "applies_the_baseline" {
  command = apply

  # The S3 account public access block is left out: the provider reaches the S3 Control API at
  # <account-id>.<endpoint>, a hostname that cannot point at a local Moto server. That resource is
  # covered by the unit tests only (see the module README).
  plan_options {
    target = [aws_ebs_encryption_by_default.this, aws_iam_account_password_policy.this]
  }

  assert {
    condition     = aws_ebs_encryption_by_default.this.enabled == true
    error_message = "EBS default encryption should be on after apply."
  }

  assert {
    condition     = aws_iam_account_password_policy.this.minimum_password_length == 14 && aws_iam_account_password_policy.this.max_password_age == 90
    error_message = "The password policy should be stored as configured."
  }
}
