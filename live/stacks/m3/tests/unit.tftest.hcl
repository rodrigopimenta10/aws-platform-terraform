# Unit tests: mock provider, plan only. modules/ecr and modules/kms have their own tests; these check what this
# root module decides: live tags, drill-friendly settings and the names the console links depend on.
mock_provider "aws" {
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

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }
}

run "repositories_follow_the_drill_conventions" {
  command = plan

  assert {
    condition     = output.ecr_api_repository_name == "platform-live-api" && output.ecr_worker_repository_name == "platform-live-worker"
    error_message = "Repositories should be named platform-live-<key> (ADR 0002)."
  }

  assert {
    condition     = output.tags["environment"] == "live" && output.tags["live-stack"] == "m3" && output.tags["project"] == "platform"
    error_message = "Every resource should carry the live tags plus live-stack = m3."
  }
}

run "rejects_a_malformed_region" {
  command = plan

  variables {
    region = "mars"
  }

  expect_failures = [var.region]
}
