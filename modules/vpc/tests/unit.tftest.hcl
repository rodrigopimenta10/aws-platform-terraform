# Unit tests: mock provider, plan only. No network, no emulator.
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"]
    }
  }
}

variables {
  project     = "platform"
  environment = "dev"
  owner       = "platform-team"
}

run "defaults_build_three_subnets_per_tier" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 3 && length(aws_subnet.private) == 3 && length(aws_subnet.isolated) == 3
    error_message = "Each tier should have one subnet per AZ (3 by default)."
  }

  assert {
    condition     = join(",", output.availability_zones) == "us-east-1a,us-east-1b,us-east-1c"
    error_message = "Should use the first three AZs."
  }

  assert {
    condition     = aws_vpc.this.tags["Name"] == "platform-dev-vpc"
    error_message = "VPC name should come from the labels module."
  }

  assert {
    condition     = aws_vpc.this.enable_dns_support == true && aws_vpc.this.enable_dns_hostnames == true
    error_message = "DNS support and hostnames must be on (EKS and interface endpoints need them)."
  }
}

run "default_address_plan" {
  command = plan

  assert {
    condition     = join(",", output.private_subnet_cidrs) == "10.0.0.0/20,10.0.16.0/20,10.0.32.0/20"
    error_message = "Private subnets should be /20s carved from 10.0.0.0/18."
  }

  assert {
    condition     = join(",", output.public_subnet_cidrs) == "10.0.64.0/22,10.0.68.0/22,10.0.72.0/22"
    error_message = "Public subnets should be /22s carved from 10.0.64.0/18."
  }

  assert {
    condition     = join(",", output.isolated_subnet_cidrs) == "10.0.128.0/22,10.0.132.0/22,10.0.136.0/22"
    error_message = "Isolated subnets should be /22s carved from 10.0.128.0/18."
  }
}

run "subnets_do_not_overlap_with_large_newbits" {
  command = plan

  variables {
    private_subnet_newbits  = 8
    public_subnet_newbits   = 8
    isolated_subnet_newbits = 8
  }

  assert {
    condition     = length(distinct(concat(output.private_subnet_cidrs, output.public_subnet_cidrs, output.isolated_subnet_cidrs))) == 9
    error_message = "All nine subnet CIDRs must be distinct."
  }

  assert {
    condition     = output.public_subnet_cidrs[0] == "10.0.64.0/26" && output.private_subnet_cidrs[0] == "10.0.0.0/26"
    error_message = "newbits 8 on a /16 should give /26 subnets inside their own tier block."
  }
}

run "two_az_variant" {
  command = plan

  variables {
    az_count = 2
  }

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_route_table.private) == 2 && length(output.eks_subnet_ids) == 2
    error_message = "az_count = 2 should create two of everything per AZ."
  }
}

run "routing_per_tier" {
  command = plan

  assert {
    condition     = aws_route.public_internet.destination_cidr_block == "0.0.0.0/0"
    error_message = "Public route table must send 0.0.0.0/0 to the internet gateway."
  }

  assert {
    condition     = length(aws_route_table.private) == 3
    error_message = "There must be one private route table per AZ."
  }

  assert {
    condition     = length(aws_route_table_association.isolated) == 3
    error_message = "Every isolated subnet must be associated with the isolated route table."
  }
}

# aws_default_security_group.this has no rules in config; its (empty) ingress/egress sets are only known after
# apply, so that assertion lives in tests/integration.tftest.hcl.

run "no_public_ips_by_default_on_any_tier" {
  command = plan

  assert {
    condition = alltrue(concat(
      [for s in aws_subnet.public : s.map_public_ip_on_launch == false],
      [for s in aws_subnet.private : s.map_public_ip_on_launch == false],
      [for s in aws_subnet.isolated : s.map_public_ip_on_launch == false],
    ))
    error_message = "No subnet should auto-assign public IPs."
  }
}

run "eks_discovery_tags" {
  command = plan

  variables {
    eks_cluster_names = ["platform-dev"]
  }

  assert {
    condition     = aws_subnet.public[0].tags["kubernetes.io/role/elb"] == "1" && aws_subnet.public[0].tags["kubernetes.io/cluster/platform-dev"] == "shared"
    error_message = "Public subnets need the elb role tag and the cluster tag."
  }

  assert {
    condition     = aws_subnet.private[2].tags["kubernetes.io/role/internal-elb"] == "1" && aws_subnet.private[2].tags["kubernetes.io/cluster/platform-dev"] == "shared"
    error_message = "Private subnets need the internal-elb role tag and the cluster tag."
  }

  assert {
    condition     = !contains(keys(aws_subnet.isolated[0].tags), "kubernetes.io/role/elb") && !contains(keys(aws_subnet.isolated[0].tags), "kubernetes.io/role/internal-elb")
    error_message = "Isolated subnets must not be offered to load balancers."
  }
}

run "no_cluster_tags_without_clusters" {
  command = plan

  assert {
    condition     = length([for k in keys(aws_subnet.private[0].tags) : k if startswith(k, "kubernetes.io/cluster/")]) == 0
    error_message = "No cluster tags expected when eks_cluster_names is empty."
  }
}

run "rejects_too_big_vpc" {
  command = plan

  variables {
    vpc_cidr = "10.0.0.0/8"
  }

  expect_failures = [var.vpc_cidr]
}

run "rejects_tiny_vpc" {
  command = plan

  variables {
    vpc_cidr = "10.0.0.0/24"
  }

  expect_failures = [var.vpc_cidr]
}

run "rejects_non_network_cidr" {
  command = plan

  variables {
    vpc_cidr = "10.0.1.5/16"
  }

  expect_failures = [var.vpc_cidr]
}

run "rejects_invalid_az_count" {
  command = plan

  variables {
    az_count = 4
  }

  expect_failures = [var.az_count]
}

run "rejects_newbits_too_small" {
  command = plan

  variables {
    public_subnet_newbits = 1
  }

  expect_failures = [var.public_subnet_newbits]
}

run "rejects_subnets_smaller_than_a_slash_28" {
  command = plan

  variables {
    vpc_cidr                = "10.0.0.0/20"
    private_subnet_newbits  = 8
    public_subnet_newbits   = 8
    isolated_subnet_newbits = 8
  }

  expect_failures = [aws_vpc.this]
}

run "rejects_bad_cluster_name" {
  command = plan

  variables {
    eks_cluster_names = ["bad name!"]
  }

  expect_failures = [var.eks_cluster_names]
}

run "nat_per_az_by_default" {
  command = plan

  assert {
    condition     = length(aws_nat_gateway.this) == 3 && length(aws_eip.nat) == 3 && length(aws_route.private_nat) == 3
    error_message = "By default there is one NAT gateway, one Elastic IP and one private default route per AZ."
  }
}

run "single_nat_gateway" {
  command = plan

  variables {
    single_nat_gateway = true
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1 && length(aws_eip.nat) == 1
    error_message = "single_nat_gateway should create exactly one NAT gateway and one Elastic IP."
  }

  assert {
    condition     = length(aws_route.private_nat) == 3
    error_message = "Every private route table still needs its default route, all pointing at the one NAT."
  }
}

run "two_az_nat_per_az" {
  command = plan

  variables {
    az_count = 2
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 2 && length(aws_route.private_nat) == 2
    error_message = "Two AZs should get two NAT gateways."
  }
}

run "nat_disabled" {
  command = plan

  variables {
    enable_nat_gateway = false
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0 && length(aws_eip.nat) == 0 && length(aws_route.private_nat) == 0
    error_message = "No NAT resources or private default routes when enable_nat_gateway is false."
  }

  assert {
    condition     = length(output.nat_gateway_ids) == 0
    error_message = "nat_gateway_ids should be empty when NAT is disabled."
  }
}

run "single_nat_ignored_when_nat_disabled" {
  command = plan

  variables {
    enable_nat_gateway = false
    single_nat_gateway = true
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0
    error_message = "single_nat_gateway must not create anything when NAT is disabled."
  }
}
