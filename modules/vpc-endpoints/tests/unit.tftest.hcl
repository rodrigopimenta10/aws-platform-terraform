# Unit tests: mock provider, plan only. No network, no emulator.
mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }
}

variables {
  project             = "platform"
  environment         = "dev"
  owner               = "platform-team"
  vpc_id              = "vpc-0123456789abcdef0"
  allowed_cidr_blocks = ["10.0.0.0/16"]
  subnet_ids          = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2", "subnet-0ccccccccccccccc3"]
  route_table_ids     = ["rtb-0aaaaaaaaaaaaaaa1", "rtb-0bbbbbbbbbbbbbbb2"]
}

run "defaults_create_s3_gateway_and_four_interface_endpoints" {
  command = plan

  assert {
    condition     = length(aws_vpc_endpoint.s3) == 1 && aws_vpc_endpoint.s3[0].vpc_endpoint_type == "Gateway"
    error_message = "One S3 gateway endpoint expected by default."
  }

  assert {
    condition     = aws_vpc_endpoint.s3[0].service_name == "com.amazonaws.us-east-1.s3"
    error_message = "S3 service name should include the region."
  }

  assert {
    condition     = join(",", sort(keys(aws_vpc_endpoint.interface))) == "ecr_api,ecr_dkr,logs,sts"
    error_message = "ECR api, ECR dkr, STS and CloudWatch Logs endpoints expected."
  }

  assert {
    condition = (
      aws_vpc_endpoint.interface["ecr_api"].service_name == "com.amazonaws.us-east-1.ecr.api" &&
      aws_vpc_endpoint.interface["ecr_dkr"].service_name == "com.amazonaws.us-east-1.ecr.dkr" &&
      aws_vpc_endpoint.interface["sts"].service_name == "com.amazonaws.us-east-1.sts" &&
      aws_vpc_endpoint.interface["logs"].service_name == "com.amazonaws.us-east-1.logs"
    )
    error_message = "Interface service names are wrong."
  }

  assert {
    condition     = alltrue([for e in aws_vpc_endpoint.interface : e.vpc_endpoint_type == "Interface" && e.private_dns_enabled == true])
    error_message = "Interface endpoints should use private DNS."
  }
}

run "each_interface_endpoint_has_its_own_security_group" {
  command = plan

  assert {
    condition     = length(aws_security_group.interface) == 4
    error_message = "One security group per interface endpoint."
  }

  assert {
    condition     = aws_security_group.interface["ecr_api"].name == "platform-dev-ecr-api-vpce"
    error_message = "Security group names should come from the labels module."
  }

  assert {
    condition = alltrue([
      for r in aws_vpc_security_group_ingress_rule.https :
      r.from_port == 443 && r.to_port == 443 && r.ip_protocol == "tcp" && r.cidr_ipv4 == "10.0.0.0/16"
    ])
    error_message = "Ingress should be TCP 443 from the allowed CIDR only."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.https) == 4
    error_message = "One ingress rule per endpoint and CIDR block."
  }
}

run "multiple_cidrs_multiply_rules" {
  command = plan

  variables {
    allowed_cidr_blocks = ["10.0.0.0/20", "10.0.16.0/20"]
    interface_endpoints = ["sts", "logs"]
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.https) == 4
    error_message = "2 endpoints x 2 CIDRs = 4 rules."
  }
}

run "subset_of_interface_endpoints" {
  command = plan

  variables {
    interface_endpoints = ["sts"]
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 1 && length(aws_security_group.interface) == 1
    error_message = "Only the requested interface endpoint should exist."
  }
}

run "s3_endpoint_can_be_disabled" {
  command = plan

  variables {
    enable_s3_gateway_endpoint = false
  }

  assert {
    condition     = length(aws_vpc_endpoint.s3) == 0
    error_message = "No S3 endpoint when disabled."
  }

  assert {
    condition     = output.s3_gateway_endpoint_id == null
    error_message = "The S3 endpoint output should be null when disabled."
  }
}

run "s3_endpoint_policy_is_applied" {
  command = plan

  variables {
    s3_endpoint_policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::example-bucket/*\"}]}"
  }

  assert {
    condition     = can(jsondecode(aws_vpc_endpoint.s3[0].policy).Statement)
    error_message = "The custom policy should be set on the gateway endpoint."
  }
}

run "rejects_unknown_endpoint" {
  command = plan

  variables {
    interface_endpoints = ["ec2"]
  }

  expect_failures = [var.interface_endpoints]
}

run "rejects_duplicate_endpoints" {
  command = plan

  variables {
    interface_endpoints = ["sts", "sts"]
  }

  expect_failures = [var.interface_endpoints]
}

run "rejects_open_to_the_world" {
  command = plan

  variables {
    allowed_cidr_blocks = ["0.0.0.0/0"]
  }

  expect_failures = [var.allowed_cidr_blocks]
}

run "rejects_empty_cidr_list" {
  command = plan

  variables {
    allowed_cidr_blocks = []
  }

  expect_failures = [var.allowed_cidr_blocks]
}

run "rejects_bad_vpc_id" {
  command = plan

  variables {
    vpc_id = "not-a-vpc"
  }

  expect_failures = [var.vpc_id]
}

run "rejects_empty_subnets" {
  command = plan

  variables {
    subnet_ids = []
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_bad_route_table_id" {
  command = plan

  variables {
    route_table_ids = ["nope"]
  }

  expect_failures = [var.route_table_ids]
}

run "rejects_invalid_policy_json" {
  command = plan

  variables {
    s3_endpoint_policy = "{not json"
  }

  expect_failures = [var.s3_endpoint_policy]
}
