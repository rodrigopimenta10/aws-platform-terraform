# Integration test: applies the module against a local Moto server (see ADR 0001). No real AWS.
# Moto keeps the node group record and the launch template but starts no instances, so this proves the
# API calls are accepted and stored as intended, not that nodes join. The live drill proves that.
# Builds a key and a cluster with modules/kms and modules/eks first, the way a root module would.
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true

  endpoints {
    ec2  = "http://127.0.0.1:5000"
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

run "cluster" {
  command = apply

  module {
    source = "../eks"
  }

  # Moto does not load AWS-managed IAM policies unless started with MOTO_IAM_LOAD_MANAGED_POLICIES.
  override_resource {
    target = module.cluster_role.aws_iam_role_policy_attachment.this
  }

  variables {
    subnet_ids           = ["subnet-0a1b2c3d", "subnet-4e5f6a7b"]
    kms_key_arn          = run.key.key_arn
    logs_kms_key_arn     = run.key.key_arn
    permissions_boundary = "arn:aws:iam::123456789012:policy/platform-dev-boundary"
  }
}

run "node_groups_are_created_with_the_safe_launch_template" {
  command = apply

  # Same Moto limit as above: the three AWS-managed node policies cannot be attached.
  override_resource {
    target = module.node_role.aws_iam_role_policy_attachment.this
  }

  variables {
    cluster_name         = run.cluster.cluster_name
    subnet_ids           = ["subnet-0a1b2c3d", "subnet-4e5f6a7b"]
    permissions_boundary = "arn:aws:iam::123456789012:policy/platform-dev-boundary"
    ebs_kms_key_arn      = run.key.key_arn

    node_groups = {
      system = {
        labels = { workload = "system" }
      }
      batch = {
        capacity_type  = "SPOT"
        instance_types = ["t3.large", "t3a.large"]
        min_size       = 0
        desired_size   = 0
        max_size       = 4
        taints         = [{ key = "spot", value = "true", effect = "NO_SCHEDULE" }]
      }
    }
  }

  assert {
    condition     = aws_eks_node_group.this["system"].node_group_name == "platform-dev-nodes-system" && aws_eks_node_group.this["batch"].node_group_name == "platform-dev-nodes-batch"
    error_message = "Both node groups should be stored under their labels-module names."
  }

  assert {
    condition     = aws_eks_node_group.this["batch"].capacity_type == "SPOT" && aws_eks_node_group.this["system"].capacity_type == "ON_DEMAND"
    error_message = "Moto should report each group's capacity type."
  }

  assert {
    condition     = aws_eks_node_group.this["batch"].scaling_config[0].max_size == 4 && aws_eks_node_group.this["batch"].scaling_config[0].min_size == 0
    error_message = "The stored scaling bounds should match."
  }

  assert {
    condition     = aws_eks_node_group.this["system"].labels["workload"] == "system"
    error_message = "The stored labels should include the user's label."
  }

  assert {
    condition     = length(aws_eks_node_group.this["batch"].taint) == 1
    error_message = "The batch group should keep its taint."
  }

  assert {
    condition     = aws_launch_template.this["system"].metadata_options[0].http_tokens == "required" && aws_launch_template.this["system"].metadata_options[0].http_put_response_hop_limit == 1
    error_message = "The stored launch template should require IMDSv2 with hop limit 1."
  }

  assert {
    condition     = aws_launch_template.this["system"].block_device_mappings[0].ebs[0].encrypted == "true" && aws_launch_template.this["system"].block_device_mappings[0].ebs[0].kms_key_id == run.key.key_arn
    error_message = "The stored launch template should encrypt the root volume with the given key."
  }

  assert {
    condition     = can(regex(":role/platform-dev-nodes-role$", output.node_role_arn))
    error_message = "The node role should be platform-dev-nodes-role."
  }
}
