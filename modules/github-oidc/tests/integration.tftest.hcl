# Integration test (Moto has no AWS-managed policies such as ReadOnlyAccess, so attachments are covered by
# the unit tests only): applies the module against a local Moto server (see ADR 0001). No real AWS.
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
  github_repository    = "example-org/example-repo"
  allowed_environments = ["production"]
}

run "creates_provider_and_role_with_a_scoped_trust_policy" {
  command = apply

  assert {
    condition     = aws_iam_openid_connect_provider.github[0].url == "token.actions.githubusercontent.com" && contains(aws_iam_openid_connect_provider.github[0].client_id_list, "sts.amazonaws.com")
    error_message = "The provider should exist for GitHub with the STS audience."
  }

  assert {
    condition     = aws_iam_role.deploy.name == "platform-dev-github-deploy" && output.role_arn == aws_iam_role.deploy.arn
    error_message = "The role should exist under its labelled name."
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.deploy.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == [
        "repo:example-org/example-repo:ref:refs/heads/main",
        "repo:example-org/example-repo:environment:production",
      ]
    )
    error_message = "Stored trust policy should hold the two exact subjects."
  }
}
