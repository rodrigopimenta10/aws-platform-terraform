# Unit tests: mock provider, plan only. No network, no emulator.
mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/platform-dev-eks-cluster"
    }
  }
}

variables {
  project              = "platform"
  environment          = "dev"
  owner                = "platform-team"
  subnet_ids           = ["subnet-0a1b2c3d", "subnet-4e5f6a7b"]
  kms_key_arn          = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  logs_kms_key_arn     = "arn:aws:kms:us-east-1:123456789012:key/66666666-7777-8888-9999-000000000000"
  permissions_boundary = "arn:aws:iam::123456789012:policy/platform-dev-boundary"
}

run "cluster_is_private_encrypted_and_logged_by_default" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.name == "platform-dev-eks" && aws_eks_cluster.this.version == "1.33"
    error_message = "Cluster should be named by the labels module and pin the Kubernetes version."
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access == true && aws_eks_cluster.this.vpc_config[0].endpoint_public_access == false
    error_message = "The API endpoint should be private only unless asked otherwise."
  }

  assert {
    condition     = aws_eks_cluster.this.encryption_config[0].resources == toset(["secrets"]) && aws_eks_cluster.this.encryption_config[0].provider[0].key_arn == var.kms_key_arn
    error_message = "Secrets must be envelope-encrypted with the given KMS key."
  }

  assert {
    condition     = length(aws_eks_cluster.this.enabled_cluster_log_types) == 5
    error_message = "All five control-plane log types should be on by default."
  }

  assert {
    condition     = aws_eks_cluster.this.access_config[0].authentication_mode == "API" && aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions == false
    error_message = "Access entries only, and no hidden admin rights for the creator."
  }

  assert {
    condition     = aws_eks_cluster.this.tags["managed-by"] == "terraform" && aws_eks_cluster.this.tags["Name"] == "platform-dev-eks"
    error_message = "Name and standard tags come from the labels module."
  }
}

run "log_group_is_named_for_eks_encrypted_and_expires" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.cluster.name == "/aws/eks/platform-dev-eks/cluster" && aws_cloudwatch_log_group.cluster.retention_in_days == 365
    error_message = "EKS only writes to /aws/eks/<cluster>/cluster; retention defaults to 365 days."
  }

  assert {
    condition     = aws_cloudwatch_log_group.cluster.kms_key_id == var.logs_kms_key_arn
    error_message = "The log group must use the given KMS key."
  }
}

run "cluster_role_goes_through_the_boundary_module" {
  command = plan

  assert {
    condition     = module.cluster_role.permissions_boundary == var.permissions_boundary
    error_message = "The cluster role must carry the permissions boundary."
  }
}

run "custom_log_types_retention_and_service_cidr" {
  command = plan

  variables {
    enabled_log_types  = ["audit", "authenticator"]
    log_retention_days = 180
    service_ipv4_cidr  = "172.20.0.0/16"
  }

  assert {
    condition     = length(aws_eks_cluster.this.enabled_cluster_log_types) == 2 && aws_cloudwatch_log_group.cluster.retention_in_days == 180
    error_message = "Log types and retention should be configurable."
  }

  assert {
    condition     = aws_eks_cluster.this.kubernetes_network_config[0].service_ipv4_cidr == "172.20.0.0/16"
    error_message = "service_ipv4_cidr should reach the cluster."
  }
}

run "public_endpoint_is_opt_in_and_cidr_restricted" {
  command = plan

  variables {
    endpoint_public_access = true
    public_access_cidrs    = ["203.0.113.0/24"]
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_public_access == true && aws_eks_cluster.this.vpc_config[0].public_access_cidrs == toset(["203.0.113.0/24"])
    error_message = "The public endpoint should be limited to the given CIDRs."
  }
}

run "access_entries_become_entries_and_scoped_policies" {
  command = plan

  variables {
    access_entries = {
      admins = {
        principal_arn = "arn:aws:iam::123456789012:role/platform-admins"
        policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
      }
      devs = {
        principal_arn = "arn:aws:iam::123456789012:role/platform-devs"
        policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
        namespaces    = ["apps", "staging"]
      }
    }
  }

  assert {
    condition     = length(aws_eks_access_entry.this) == 2 && length(aws_eks_access_policy_association.this) == 2
    error_message = "One access entry and one policy association per map key."
  }

  assert {
    condition     = aws_eks_access_policy_association.this["admins"].access_scope[0].type == "cluster" && aws_eks_access_policy_association.this["devs"].access_scope[0].type == "namespace"
    error_message = "No namespaces means cluster scope; namespaces mean namespace scope."
  }

  assert {
    condition     = aws_eks_access_policy_association.this["devs"].access_scope[0].namespaces == toset(["apps", "staging"])
    error_message = "Namespaces should reach the association."
  }
}

run "rejects_public_endpoint_without_cidrs" {
  command = plan

  variables {
    endpoint_public_access = true
  }

  expect_failures = [aws_eks_cluster.this]
}

run "rejects_open_public_cidr" {
  command = plan

  variables {
    endpoint_public_access = true
    public_access_cidrs    = ["0.0.0.0/0"]
  }

  expect_failures = [var.public_access_cidrs]
}

run "rejects_single_subnet" {
  command = plan

  variables {
    subnet_ids = ["subnet-0a1b2c3d"]
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_alias_instead_of_key_arn" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:alias/platform-dev-eks"
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_logs_without_audit" {
  command = plan

  variables {
    enabled_log_types = ["api"]
  }

  expect_failures = [var.enabled_log_types]
}

run "rejects_patch_version" {
  command = plan

  variables {
    kubernetes_version = "1.33.2"
  }

  expect_failures = [var.kubernetes_version]
}

run "rejects_bad_retention" {
  command = plan

  variables {
    log_retention_days = 45
  }

  expect_failures = [var.log_retention_days]
}

run "rejects_non_eks_policy_in_access_entry" {
  command = plan

  variables {
    access_entries = {
      bad = {
        principal_arn = "arn:aws:iam::123456789012:role/x"
        policy_arn    = "arn:aws:iam::aws:policy/AdministratorAccess"
      }
    }
  }

  expect_failures = [var.access_entries]
}
