# Integration test: applies the module against a local Moto server (see ADR 0001). No real AWS.
# Builds a small VPC with modules/vpc first, then the endpoints on top of it, the way a root module would.
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true

  endpoints {
    ec2 = "http://127.0.0.1:5000"
    sts = "http://127.0.0.1:5000"
  }
}

variables {
  project     = "platform"
  environment = "dev"
  owner       = "platform-team"
}

run "network" {
  command = apply

  module {
    source = "../vpc"
  }

  variables {
    az_count           = 2
    enable_nat_gateway = false
  }
}

run "endpoints_on_the_vpc" {
  command = apply

  variables {
    vpc_id              = run.network.vpc_id
    allowed_cidr_blocks = [run.network.vpc_cidr_block]
    subnet_ids          = run.network.private_subnet_ids
    route_table_ids     = concat(run.network.private_route_table_ids, [run.network.isolated_route_table_id])
  }

  assert {
    condition     = aws_vpc_endpoint.s3[0].vpc_endpoint_type == "Gateway" && aws_vpc_endpoint.s3[0].vpc_id == run.network.vpc_id
    error_message = "The S3 gateway endpoint should exist in the VPC."
  }

  assert {
    condition     = length(aws_vpc_endpoint.s3[0].route_table_ids) == 3
    error_message = "The S3 endpoint should be attached to 2 private route tables and the isolated one."
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 4 && alltrue([for e in aws_vpc_endpoint.interface : e.vpc_endpoint_type == "Interface"])
    error_message = "Four interface endpoints expected."
  }

  assert {
    condition     = alltrue([for e in aws_vpc_endpoint.interface : length(e.subnet_ids) == 2])
    error_message = "Each interface endpoint should cover both private subnets."
  }

  assert {
    condition     = length(distinct(values(output.security_group_ids))) == 4
    error_message = "Each interface endpoint needs its own, distinct security group."
  }

  assert {
    condition     = alltrue([for k, e in aws_vpc_endpoint.interface : contains(e.security_group_ids, aws_security_group.interface[k].id)])
    error_message = "Each endpoint should use its own security group."
  }

  # A security group's own ingress and egress attributes stay empty when the rules are separate resources,
  # so the rules are checked directly.
  assert {
    condition = alltrue([
      for k, r in aws_vpc_security_group_ingress_rule.https :
      r.from_port == 443 && r.to_port == 443 && r.ip_protocol == "tcp" && r.cidr_ipv4 == run.network.vpc_cidr_block
    ]) && length(aws_vpc_security_group_ingress_rule.https) == 4
    error_message = "Each endpoint should allow only TCP 443 from the VPC CIDR."
  }

  assert {
    condition     = alltrue([for k, r in aws_vpc_security_group_ingress_rule.https : r.security_group_id == aws_security_group.interface[split("|", k)[0]].id])
    error_message = "Every rule should belong to its own endpoint's security group."
  }
}
