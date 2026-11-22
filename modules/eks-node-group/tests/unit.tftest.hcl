# Unit tests: mock provider, plan only. No network, no emulator.
mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/platform-dev-nodes-role"
    }
  }
}

variables {
  project              = "platform"
  environment          = "dev"
  owner                = "platform-team"
  cluster_name         = "platform-dev-eks"
  subnet_ids           = ["subnet-0a1b2c3d", "subnet-4e5f6a7b"]
  permissions_boundary = "arn:aws:iam::123456789012:policy/platform-dev-boundary"

  node_groups = {
    general = {}
  }
}

run "defaults_give_one_on_demand_group_named_by_the_labels_module" {
  command = plan

  assert {
    condition     = aws_eks_node_group.this["general"].node_group_name == "platform-dev-nodes-general" && aws_eks_node_group.this["general"].cluster_name == "platform-dev-eks"
    error_message = "Node group name comes from the labels module and it joins the named cluster."
  }

  assert {
    condition     = aws_eks_node_group.this["general"].capacity_type == "ON_DEMAND" && aws_eks_node_group.this["general"].instance_types == tolist(["t3.medium"]) && aws_eks_node_group.this["general"].ami_type == "AL2023_x86_64_STANDARD"
    error_message = "Defaults are on-demand t3.medium on Amazon Linux 2023."
  }

  assert {
    condition     = aws_eks_node_group.this["general"].scaling_config[0].min_size == 1 && aws_eks_node_group.this["general"].scaling_config[0].max_size == 3 && aws_eks_node_group.this["general"].scaling_config[0].desired_size == 1
    error_message = "Default scaling is 1 to 3 nodes, starting at 1."
  }

  assert {
    condition     = aws_eks_node_group.this["general"].labels["node-group"] == "general" && aws_eks_node_group.this["general"].tags["managed-by"] == "terraform"
    error_message = "Every group is labelled with its key and carries the standard tags."
  }

  assert {
    condition     = aws_eks_node_group.this["general"].update_config[0].max_unavailable == 1
    error_message = "Updates replace one node at a time by default."
  }
}

run "launch_template_requires_imdsv2_and_encrypts_the_root_volume" {
  command = plan

  assert {
    condition     = aws_launch_template.this["general"].metadata_options[0].http_tokens == "required" && aws_launch_template.this["general"].metadata_options[0].http_endpoint == "enabled"
    error_message = "IMDSv2 must be required."
  }

  assert {
    condition     = aws_launch_template.this["general"].metadata_options[0].http_put_response_hop_limit == 1
    error_message = "Hop limit 1 keeps pods away from the node's credentials."
  }

  assert {
    condition     = aws_launch_template.this["general"].block_device_mappings[0].ebs[0].encrypted == "true" && aws_launch_template.this["general"].block_device_mappings[0].ebs[0].volume_type == "gp3"
    error_message = "The root volume must be an encrypted gp3 volume."
  }

  assert {
    condition     = aws_launch_template.this["general"].image_id == null
    error_message = "No image is named: EKS picks the optimized one for the ami_type."
  }
}

run "customer_managed_key_and_hop_limit_are_passed_through" {
  command = plan

  variables {
    ebs_kms_key_arn    = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    metadata_hop_limit = 2
  }

  assert {
    condition     = aws_launch_template.this["general"].block_device_mappings[0].ebs[0].kms_key_id == var.ebs_kms_key_arn
    error_message = "The root volume should use the given key."
  }

  assert {
    condition     = aws_launch_template.this["general"].metadata_options[0].http_put_response_hop_limit == 2
    error_message = "The hop limit should follow the variable."
  }
}

run "on_demand_and_spot_groups_with_labels_and_taints" {
  command = plan

  variables {
    node_groups = {
      system = {
        labels = { workload = "system" }
      }
      batch = {
        capacity_type  = "SPOT"
        instance_types = ["t3.large", "t3a.large"]
        min_size       = 0
        desired_size   = 0
        max_size       = 5
        labels         = { workload = "batch" }
        taints         = [{ key = "spot", value = "true", effect = "NO_SCHEDULE" }]
      }
    }
  }

  assert {
    condition     = aws_eks_node_group.this["system"].capacity_type == "ON_DEMAND" && aws_eks_node_group.this["batch"].capacity_type == "SPOT"
    error_message = "Each group keeps its own capacity type."
  }

  assert {
    condition     = length(aws_launch_template.this) == 2
    error_message = "Each group gets its own launch template."
  }

  assert {
    condition     = aws_eks_node_group.this["batch"].labels["workload"] == "batch" && aws_eks_node_group.this["batch"].labels["node-group"] == "batch"
    error_message = "User labels are kept next to the node-group label."
  }

  assert {
    condition     = length(aws_eks_node_group.this["batch"].taint) == 1 && length(aws_eks_node_group.this["system"].taint) == 0
    error_message = "Only the batch group is tainted."
  }

  assert {
    condition     = aws_eks_node_group.this["batch"].scaling_config[0].min_size == 0
    error_message = "A group may scale to zero."
  }
}

run "rejects_a_spot_group_with_one_instance_type" {
  command = plan

  variables {
    node_groups = {
      batch = { capacity_type = "SPOT" }
    }
  }

  expect_failures = [var.node_groups]
}

run "rejects_unknown_capacity_type" {
  command = plan

  variables {
    node_groups = { general = { capacity_type = "RESERVED" } }
  }

  expect_failures = [var.node_groups]
}

run "rejects_min_above_desired" {
  command = plan

  variables {
    node_groups = { general = { min_size = 2, desired_size = 1 } }
  }

  expect_failures = [var.node_groups]
}

run "rejects_bad_taint_effect" {
  command = plan

  variables {
    node_groups = { general = { taints = [{ key = "k", effect = "EVICT" }] } }
  }

  expect_failures = [var.node_groups]
}

run "rejects_reserved_label_prefix" {
  command = plan

  variables {
    node_groups = { general = { labels = { "eks.amazonaws.com/nodegroup" = "x" } } }
  }

  expect_failures = [var.node_groups]
}

run "rejects_empty_node_groups" {
  command = plan

  variables {
    node_groups = {}
  }

  expect_failures = [var.node_groups]
}

run "rejects_one_subnet" {
  command = plan

  variables {
    subnet_ids = ["subnet-0a1b2c3d"]
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_hop_limit_above_two" {
  command = plan

  variables {
    metadata_hop_limit = 3
  }

  expect_failures = [var.metadata_hop_limit]
}

run "rejects_a_non_arn_extra_policy" {
  command = plan

  variables {
    additional_node_policy_arns = ["AdministratorAccess"]
  }

  expect_failures = [var.additional_node_policy_arns]
}
