# Live-drill stack "vpc": applies modules/vpc for real, for the length of a drill, then gets destroyed.
# Started only by .github/workflows/live-drill.yml after Rodrigo approves the aws-live environment.
#
# Cheapest settings: 2 AZs instead of 3, and no NAT gateway (enable_nat_gateway = false, because a NAT
# gateway bills every hour). A VPC,
# its subnets, route tables, internet gateway and an emptied default security group have no hourly charge,
# so a drill of this stack costs nothing.

locals {
  stack = "vpc"
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

module "vpc" {
  source = "../../../modules/vpc"

  project     = "platform"
  environment = "live"
  owner       = var.owner
  az_count    = 2

  # A NAT gateway costs money per hour; this drill is meant to be free.
  enable_nat_gateway = false
}
