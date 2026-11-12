terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Left empty so no bucket name (which contains the account ID) is ever committed. The values come from
  # -backend-config at `terraform init`. The very first apply cannot use it, because this stack creates
  # the bucket: README.md shows how a gitignored backend_override.tf switches that one run to local state
  # and how `terraform init -migrate-state` then moves the state to bootstrap/terraform.tfstate.
  backend "s3" {}
}
