# Live-drill stack "m2": the milestone 2 identity and security modules, applied for real for the length of a
# drill, then destroyed. Started only by .github/workflows/live-drill.yml. It grows with each M2 roadmap item;
# M2.1 adds the KMS key, shown in use by encrypting one CloudWatch log group. M2.2 adds a GitHub OIDC deploy
# role (the account's provider already exists from live/bootstrap, so it is not created again).
#
# Cost: a KMS key bills about $1 a month prorated by the hour (a fraction of a cent for a drill), and it is
# scheduled for deletion after the shortest window (7 days). The empty log group and
# the IAM role are free.

locals {
  stack          = "m2"
  log_group_name = "/aws/platform-live/app"
}

module "labels" {
  source = "../../../modules/labels"

  project     = "platform"
  environment = "live"
  owner       = var.owner

  # live-stack lets the workflow find anything this stack left behind with one tag lookup after destroy.
  extra_tags = { "live-stack" = local.stack }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = module.labels.tags
  }
}

data "aws_caller_identity" "current" {}

module "kms_logs" {
  source = "../../../modules/kms"

  project     = "platform"
  environment = "live"
  owner       = var.owner
  purpose     = "logs"
  description = "Drill key: encrypts the platform-live application log group"

  # CloudWatch Logs may use the key only for the one log group below. The ARN is built from the group's name
  # because the log group needs the key, and reading it from the resource would make a dependency cycle.
  service_grants = {
    CloudWatchLogs = {
      service = "logs.${var.region}.amazonaws.com"
      encryption_context = {
        "aws:logs:arn" = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_name}"
      }
    }
  }

  deletion_window_in_days = 7
}

resource "aws_cloudwatch_log_group" "app" {
  name              = local.log_group_name
  retention_in_days = 365 # checkov wants a year; the group lives minutes and is empty
  kms_key_id        = module.kms_logs.key_arn
}

# The role has no permissions attached and carries the drill boundary. It exists to show the trust policy:
# only this repository's main branch can assume it. The account's GitHub provider comes from live/bootstrap
# (AWS allows one per URL), hence create_provider = false.
module "github_oidc" {
  source = "../../../modules/github-oidc"

  project           = "platform"
  environment       = "live"
  owner             = var.owner
  github_repository = "rodrigopimenta10/aws-platform-terraform"

  allowed_branches     = ["main"]
  create_provider      = false
  permissions_boundary = var.permissions_boundary_arn
}
