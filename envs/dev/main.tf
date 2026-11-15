# Root module for the dev environment. A root module is the folder you run `terraform apply` in;
# it wires reusable modules (under modules/) together with a provider and, later, a state backend.

module "labels" {
  source = "../../modules/labels"

  project     = var.project
  environment = "dev"
  owner       = var.owner
  components  = var.components
}

provider "aws" {
  region = var.region

  # Every taggable resource created through this provider gets the standard tags automatically.
  default_tags {
    tags = module.labels.tags
  }
}

# Remote state is OFF until you have bootstrapped the bucket (see README.md, "Bootstrapping state").
# Once modules/state-backend has been applied, fill in the values from its `backend_config` output,
# uncomment this block and run `terraform init -migrate-state`.
#
# terraform {
#   backend "s3" {
#     bucket       = "platform-dev-tfstate-<account-id>-<region>"
#     key          = "envs/dev/terraform.tfstate"
#     region       = "us-east-1"
#     encrypt      = true
#     kms_key_id   = "<kms key arn from backend_config>"
#     use_lockfile = true # S3 native locking, see docs/adr/0003-s3-native-state-locking.md
#   }
# }

# ---------------------------------------------------------------------------------------------
# Network (milestone 1)
# ---------------------------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  project     = var.project
  environment = "dev"
  owner       = var.owner

  vpc_cidr = var.vpc_cidr
  az_count = var.az_count

  # Dev shares one NAT gateway across the AZs (see ADR 0004): about a third of the cost, at the price of
  # losing egress for every AZ if the NAT gateway's AZ fails. A real prod root module would set false.
  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway

  # Tags the subnets for the EKS cluster that milestone 3 adds.
  eks_cluster_names = ["${var.project}-dev"]
}

module "vpc_endpoints" {
  source = "../../modules/vpc-endpoints"

  project     = var.project
  environment = "dev"
  owner       = var.owner

  vpc_id              = module.vpc.vpc_id
  allowed_cidr_blocks = [module.vpc.vpc_cidr_block]
  subnet_ids          = module.vpc.private_subnet_ids
  route_table_ids     = concat(module.vpc.private_route_table_ids, [module.vpc.isolated_route_table_id])
}

module "vpc_flow_logs" {
  source = "../../modules/vpc-flow-logs"

  project     = var.project
  environment = "dev"
  owner       = var.owner

  vpc_id            = module.vpc.vpc_id
  retention_in_days = var.flow_log_retention_in_days
}
