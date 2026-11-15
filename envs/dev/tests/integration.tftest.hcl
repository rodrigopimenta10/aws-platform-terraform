# Integration test: applies the whole dev root module against a local Moto server (see ADR 0001).
# No real AWS. The provider block here replaces the one in main.tf, pointing every service at Moto.
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true

  endpoints {
    ec2  = "http://127.0.0.1:5000"
    iam  = "http://127.0.0.1:5000"
    kms  = "http://127.0.0.1:5000"
    logs = "http://127.0.0.1:5000"
    sts  = "http://127.0.0.1:5000"
  }
}

run "dev_network_has_the_expected_shape" {
  command = apply

  assert {
    condition = (
      length(output.public_subnet_ids) == 3 &&
      length(output.private_subnet_ids) == 3 &&
      length(output.isolated_subnet_ids) == 3
    )
    error_message = "Three AZs and three tiers should give 3 + 3 + 3 subnets."
  }

  assert {
    condition     = length(output.private_route_table_ids) == 3 && length(output.nat_gateway_ids) == 1
    error_message = "One private route table per AZ and a single shared NAT gateway expected."
  }

  assert {
    condition     = output.vpc_cidr_block == "10.0.0.0/16" && can(regex("^vpc-", output.vpc_id))
    error_message = "The VPC should exist with the default CIDR."
  }

  assert {
    condition     = output.flow_log_group_name == "/aws/vpc/flow-logs/platform-dev-flow-logs"
    error_message = "The flow log group should be named from the labels module."
  }
}

run "each_az_gets_its_own_nat_gateway_when_single_is_off" {
  command = apply

  variables {
    single_nat_gateway = false
  }

  assert {
    condition     = length(output.nat_gateway_ids) == 3
    error_message = "single_nat_gateway = false should create one NAT gateway per AZ."
  }
}
