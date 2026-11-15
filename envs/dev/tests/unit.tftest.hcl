# Unit tests: mock provider, plan only. They check the wiring: labels inputs, the VPC modules'
# inputs, outputs and variable validation. tests/integration.tftest.hcl applies it all against Moto.
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"]
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
}

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

run "wires_a_three_az_vpc_with_one_shared_nat_gateway" {
  command = plan

  assert {
    condition     = output.vpc_cidr_block == "10.0.0.0/16" && length(output.public_subnet_ids) == 3
    error_message = "Dev should get the default CIDR across 3 AZs."
  }

  assert {
    condition     = length(output.nat_gateway_ids) == 1
    error_message = "Dev shares a single NAT gateway by default."
  }
}

run "one_nat_gateway_per_az_when_asked" {
  command = plan

  variables {
    single_nat_gateway = false
  }

  assert {
    condition     = length(output.nat_gateway_ids) == 3
    error_message = "single_nat_gateway = false should give one NAT gateway per AZ."
  }
}

run "two_azs" {
  command = plan

  variables {
    az_count = 2
  }

  assert {
    condition     = length(output.private_subnet_ids) == 2
    error_message = "az_count should reach the VPC module."
  }
}
