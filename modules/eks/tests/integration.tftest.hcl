# Integration test: applies the module against a local Moto server (see ADR 0001). No real AWS.
# Moto has no EKS access-entry API, so access entries are covered by unit.tftest.hcl only.
# Builds the KMS key with modules/kms first, then the cluster on top of it, the way a root module would.
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true

  endpoints {
    eks  = "http://127.0.0.1:5000"
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

run "key" {
  command = apply

  module {
    source = "../kms"
  }

  variables {
    purpose     = "eks"
    description = "Encrypts platform Kubernetes secrets and control-plane logs"
  }
}

run "cluster_is_created_with_the_safe_settings" {
  command = apply

  # Moto does not load AWS-managed IAM policies unless started with MOTO_IAM_LOAD_MANAGED_POLICIES, and the
  # shared scripts/check.sh does not set it. So the attachment of AmazonEKSClusterPolicy is the one thing
  # faked here; the role itself, the cluster, the log group and the key are real Moto resources. The
  # attachment is not covered by any test here (a root module cannot see a child module's resources).
  override_resource {
    target = module.cluster_role.aws_iam_role_policy_attachment.this
  }

  variables {
    subnet_ids           = ["subnet-0a1b2c3d", "subnet-4e5f6a7b"]
    kms_key_arn          = run.key.key_arn
    logs_kms_key_arn     = run.key.key_arn
    permissions_boundary = "arn:aws:iam::123456789012:policy/platform-dev-boundary"
  }

  assert {
    condition     = aws_eks_cluster.this.name == "platform-dev-eks" && aws_eks_cluster.this.version == "1.35"
    error_message = "Moto should report the cluster name and pinned version."
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access == true && aws_eks_cluster.this.vpc_config[0].endpoint_public_access == false
    error_message = "The stored endpoint config should be private only."
  }

  assert {
    condition     = aws_eks_cluster.this.encryption_config[0].provider[0].key_arn == run.key.key_arn
    error_message = "The stored encryption config should name the KMS key."
  }

  assert {
    condition     = can(regex(":role/platform-dev-eks-cluster$", output.cluster_role_arn))
    error_message = "The cluster role should be platform-dev-eks-cluster."
  }

  assert {
    condition     = output.log_group_name == "/aws/eks/platform-dev-eks/cluster" && aws_cloudwatch_log_group.cluster.kms_key_id == run.key.key_arn
    error_message = "The log group should have the EKS name and be encrypted."
  }
}
