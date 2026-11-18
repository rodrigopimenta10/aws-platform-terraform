# Integration test: applies the module against a local Moto server (see ADR 0001). No real AWS.
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true

  endpoints {
    iam = "http://127.0.0.1:5000"
    sts = "http://127.0.0.1:5000"
  }
}

variables {
  project          = "platform"
  environment      = "dev"
  owner            = "platform-team"
  allowed_services = ["s3", "logs"]
}

run "creates_the_boundary_policy" {
  command = apply

  assert {
    condition     = aws_iam_policy.boundary.name == "platform-dev-boundary" && can(regex("policy/platform-dev-boundary$", aws_iam_policy.boundary.arn))
    error_message = "The boundary policy should exist under the labels name."
  }

  assert {
    condition     = length(jsondecode(aws_iam_policy.boundary.policy).Statement) == 6
    error_message = "The stored document should keep all six statements."
  }
}
