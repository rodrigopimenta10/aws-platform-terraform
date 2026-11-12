# Unit tests: mock provider, plan only. No network, no emulator. modules/vpc has its own unit and Moto
# tests; these check what this root module decides: 2 AZs, live naming and tags, the drill region.
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"]
    }
  }
}

run "two_azs_three_tiers" {
  command = plan

  assert {
    condition     = length(module.vpc.public_subnet_cidrs) == 2 && length(module.vpc.private_subnet_cidrs) == 2 && length(module.vpc.isolated_subnet_cidrs) == 2
    error_message = "The drill VPC should have one subnet per tier in each of 2 AZs (6 in all)."
  }

  assert {
    condition     = join(",", output.availability_zones) == "us-east-1a,us-east-1b"
    error_message = "Should use the first two AZs of us-east-1."
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
    condition     = output.tags["live-stack"] == "vpc"
    error_message = "The live-stack tag is what the destroy verification looks up."
  }
}

run "rejects_bad_region" {
  command = plan

  variables {
    region = "Virginia"
  }

  expect_failures = [var.region]
}
