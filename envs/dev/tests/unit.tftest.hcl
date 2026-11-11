# Unit tests: mock provider, plan only. The root module creates no resources yet, so these check
# the wiring: labels inputs, outputs and variable validation. No Moto test: nothing to apply.
mock_provider "aws" {}

run "wires_labels_with_defaults" {
  command = plan

  assert {
    condition     = output.prefix == "platform-dev"
    error_message = "prefix should be platform-dev."
  }

  assert {
    condition     = output.names["vpc"] == "platform-dev-vpc" && output.names["tfstate"] == "platform-dev-tfstate"
    error_message = "Component names should come from the labels module."
  }

  assert {
    condition     = output.tags["environment"] == "dev" && output.tags["managed-by"] == "terraform"
    error_message = "Standard tags are missing or wrong."
  }

  assert {
    condition     = output.region == "us-east-1" && output.environment == "dev"
    error_message = "Unexpected default region or environment."
  }
}

run "overrides_project_owner_and_region" {
  command = plan

  variables {
    project = "demo"
    owner   = "data-team"
    region  = "eu-west-2"
  }

  assert {
    condition     = output.prefix == "demo-dev" && output.tags["owner"] == "data-team" && output.region == "eu-west-2"
    error_message = "Variables should flow through to labels and the provider."
  }
}

run "rejects_bad_region" {
  command = plan

  variables {
    region = "Virginia"
  }

  expect_failures = [var.region]
}
