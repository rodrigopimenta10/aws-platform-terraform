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
