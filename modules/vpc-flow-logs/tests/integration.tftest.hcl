# Integration test: applies the module against a local Moto server (see ADR 0001). No real AWS.
# Builds a small VPC with modules/vpc first, then the flow log on top of it, the way a root module would.
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

run "flow_logs_on_the_vpc" {
  command = apply

  variables {
    vpc_id            = run.network.vpc_id
    retention_in_days = 14
  }

  assert {
    condition     = aws_flow_log.this.vpc_id == run.network.vpc_id && aws_flow_log.this.traffic_type == "ALL"
    error_message = "The flow log should be attached to the VPC and record all traffic."
  }

  assert {
    condition     = aws_flow_log.this.log_destination == aws_cloudwatch_log_group.this.arn && aws_flow_log.this.iam_role_arn == aws_iam_role.this.arn
    error_message = "The flow log should write to the module's log group through the module's role."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 14 && aws_cloudwatch_log_group.this.kms_key_id == aws_kms_key.this.arn
    error_message = "The log group should use the retention given and the module's key."
  }

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == true
    error_message = "Key rotation should be on."
  }

  assert {
    condition     = output.flow_log_id == aws_flow_log.this.id && output.log_group_name == "/aws/vpc/flow-logs/platform-dev-flow-logs"
    error_message = "Outputs should expose the flow log and the log group name."
  }
}
