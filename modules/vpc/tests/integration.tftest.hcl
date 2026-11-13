# Integration test: applies the module against a local Moto server (see ADR 0001). No real AWS.
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
  project           = "platform"
  environment       = "dev"
  owner             = "platform-team"
  eks_cluster_names = ["platform-dev"]
}

run "creates_three_tier_network" {
  command = apply

  assert {
    condition     = length(output.availability_zones) == 3 && length(distinct(output.availability_zones)) == 3
    error_message = "Three distinct AZs expected."
  }

  assert {
    condition     = length(output.public_subnet_ids) == 3 && length(output.private_subnet_ids) == 3 && length(output.isolated_subnet_ids) == 3
    error_message = "Three subnets per tier expected."
  }

  assert {
    condition     = aws_vpc.this.cidr_block == "10.0.0.0/16" && can(regex("^vpc-", output.vpc_id))
    error_message = "VPC should exist with the default CIDR."
  }

  assert {
    condition     = length(output.private_route_table_ids) == 3 && length(distinct(output.private_route_table_ids)) == 3
    error_message = "Three distinct private route tables expected."
  }

  assert {
    condition     = aws_subnet.private[0].tags["kubernetes.io/role/internal-elb"] == "1" && aws_subnet.public[1].tags["kubernetes.io/role/elb"] == "1"
    error_message = "Subnets should carry the EKS role tags after apply."
  }

  assert {
    condition     = aws_route.public_internet.gateway_id == output.internet_gateway_id
    error_message = "Public default route should target the internet gateway."
  }

  assert {
    condition     = aws_subnet.private[0].availability_zone == output.availability_zones[0]
    error_message = "Subnets should be placed in the AZs listed in the output."
  }

  assert {
    condition     = length(aws_default_security_group.this.ingress) == 0 && length(aws_default_security_group.this.egress) == 0
    error_message = "The default security group must be emptied."
  }
}

run "nat_per_az_routes_each_az_to_its_own_nat" {
  command = apply

  assert {
    condition     = length(output.nat_gateway_ids) == 3 && length(distinct(output.nat_gateway_ids)) == 3
    error_message = "Three distinct NAT gateways expected by default."
  }

  assert {
    condition     = aws_nat_gateway.this[1].subnet_id == aws_subnet.public[1].id
    error_message = "Each NAT gateway must live in the public subnet of its own AZ."
  }

  assert {
    condition     = aws_route.private_nat[2].nat_gateway_id == aws_nat_gateway.this[2].id && aws_route.private_nat[0].nat_gateway_id != aws_route.private_nat[1].nat_gateway_id
    error_message = "Each private route table should point at the NAT gateway of its own AZ."
  }
}

run "single_nat_shared_by_all_private_route_tables" {
  command = apply

  variables {
    single_nat_gateway = true
  }

  assert {
    condition     = length(output.nat_gateway_ids) == 1 && length(output.nat_public_ips) == 1
    error_message = "One NAT gateway and one Elastic IP expected."
  }

  assert {
    condition     = alltrue([for r in aws_route.private_nat : r.nat_gateway_id == aws_nat_gateway.this[0].id])
    error_message = "All private route tables should share the single NAT gateway."
  }
}

run "no_nat_means_no_private_egress_route" {
  command = apply

  variables {
    enable_nat_gateway = false
  }

  assert {
    condition     = length(output.nat_gateway_ids) == 0 && length(aws_route.private_nat) == 0
    error_message = "No NAT gateway or private default route expected when NAT is disabled."
  }
}
