# Live-drill stack "m1": the milestone 1 network, applied for real for the length of a drill, then destroyed.
# Started only by .github/workflows/live-drill.yml. It grows with each M1 roadmap item (M1.3 adds the VPC
# endpoints; flow logs and the envs/dev wiring come next).
#
# Cheapest settings: 2 AZs, no NAT gateway (it bills every hour), and the interface endpoints in both
# private subnets (the drill limit is 2 AZs). The VPC, subnets, route tables and the S3 gateway endpoint are
# free. Four interface endpoints x 2 AZs bill about $0.08 an hour while they exist, a few cents per drill.

locals {
  stack = "m1"
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

  # A NAT gateway costs money per hour. The endpoints below are what let private subnets reach ECR, STS,
  # CloudWatch Logs and S3 without one.
  enable_nat_gateway = false
}

module "vpc_endpoints" {
  source = "../../../modules/vpc-endpoints"

  project     = "platform"
  environment = "live"
  owner       = var.owner

  vpc_id              = module.vpc.vpc_id
  allowed_cidr_blocks = [module.vpc.vpc_cidr_block]
  subnet_ids          = module.vpc.private_subnet_ids # 2 subnets = 2 AZs, the plan gate's limit
  route_table_ids     = concat(module.vpc.private_route_table_ids, [module.vpc.isolated_route_table_id])
}
