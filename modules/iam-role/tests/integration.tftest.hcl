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
  project              = "platform"
  environment          = "dev"
  owner                = "platform-team"
  name                 = "worker"
  description          = "Example worker role"
  permissions_boundary = "arn:aws:iam::123456789012:policy/platform-dev-boundary"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

run "creates_role_with_boundary" {
  command = apply

  assert {
    condition     = aws_iam_role.this.name == "platform-dev-worker" && endswith(aws_iam_role.this.permissions_boundary, "policy/platform-dev-boundary")
    error_message = "The stored role should carry the boundary."
  }
}
