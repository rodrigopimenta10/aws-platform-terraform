# Integration test: applies the module against a local Moto server (see ADR 0001). No real AWS.
# Moto parses the policy documents it is given and refuses malformed ones, so a successful apply proves the
# documents are valid IAM JSON. Moto does not enforce the 6144-character limit; the unit test does.
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
  project                 = "platform"
  environment             = "dev"
  owner                   = "platform-team"
  cluster_name            = "platform-dev-eks"
  region                  = "us-east-1"
  karpenter_node_role_arn = "arn:aws:iam::123456789012:role/platform-dev-nodes"
}

run "creates_both_policies" {
  command = apply

  assert {
    condition     = can(regex("policy/platform-dev-lb-controller$", output.lb_controller_policy_arn)) && can(regex("policy/platform-dev-karpenter$", output.karpenter_policy_arn))
    error_message = "Both managed policies should exist under the labels names."
  }

  assert {
    condition     = jsondecode(aws_iam_policy.karpenter[0].policy).Statement[0].Sid == "AllowScopedEC2InstanceAccessActions"
    error_message = "Moto should store the Karpenter document as given."
  }

  assert {
    condition     = length(jsondecode(aws_iam_policy.lb_controller[0].policy).Statement) >= 10
    error_message = "The Load Balancer Controller document should keep all its statements."
  }
}
