# Live-drill stack "m3": the milestone 3 container modules, applied for real for the length of a drill, then
# destroyed. Started only by .github/workflows/live-drill.yml. It grows with each M3 roadmap item;
# M3.1 adds two ECR repositories encrypted with a drill KMS key.
#
# Cost: repositories and the lifecycle policies are free while empty. The KMS key bills about $1 a month
# prorated by the hour (a fraction of a cent for a drill) and is scheduled for deletion after 7 days.

locals {
  stack = "m3"
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

module "kms_ecr" {
  source = "../../../modules/kms"

  project     = "platform"
  environment = "live"
  owner       = var.owner
  purpose     = "ecr"
  description = "Drill key: encrypts the platform-live container image repositories"

  deletion_window_in_days = 7
}

module "ecr" {
  source = "../../../modules/ecr"

  project     = "platform"
  environment = "live"
  owner       = var.owner
  kms_key_arn = module.kms_ecr.key_arn

  repositories = {
    api    = { force_delete = true }
    worker = { keep_last_images = 10, force_delete = true }
  }
}
