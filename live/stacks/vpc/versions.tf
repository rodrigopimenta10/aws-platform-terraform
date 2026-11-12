terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Deliberately empty: the live-drill workflow fills it at `terraform init` with
  #   -backend-config="bucket=<AWS_LIVE_STATE_BUCKET secret>" -backend-config="key=live/vpc/terraform.tfstate"
  #   -backend-config="region=us-east-1" -backend-config="use_lockfile=true"
  # so no real bucket name (it contains the account ID) is committed. scripts/check.sh uses -backend=false.
  backend "s3" {}
}
