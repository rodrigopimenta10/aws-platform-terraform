# Unit tests: mock provider, plan only. No network, no emulator. modules/vpc and modules/vpc-endpoints have
# their own unit and Moto tests; these check what this root module decides: 2 AZs, live tags, and an
# endpoint set small enough for the drill's plan gate.
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
}

run "endpoints_fit_the_drill_limits" {
  command = plan

  assert {
    condition     = length(module.vpc_endpoints.interface_endpoint_ids) == 4
    error_message = "ECR api, ECR dkr, STS and Logs interface endpoints expected."
  }

  assert {
    condition     = length(module.vpc.private_subnet_ids) == 2
    error_message = "Interface endpoints use the private subnets, and the plan gate allows at most 2 per endpoint."
  }

  assert {
    condition     = output.region == "us-east-1"
    error_message = "The drill region is us-east-1."
  }
}

run "live_names_and_tags" {
  command = plan

  assert {
    condition     = output.tags["environment"] == "live" && output.tags["project"] == "platform" && output.tags["managed-by"] == "terraform"
    error_message = "Standard tags should mark the stack as platform/live, managed by Terraform."
  }

  assert {
    condition     = output.tags["live-stack"] == "m1"
    error_message = "The live-stack tag is what the destroy verification looks up."
  }
}

run "rejects_malformed_region" {
  command = plan

  variables {
    region = "useast1"
  }

  expect_failures = [var.region]
}
