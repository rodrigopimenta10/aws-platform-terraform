# EKS managed node groups: the worker machines that run your pods. "Managed" means EKS creates and drains
# the EC2 instances (through an Auto Scaling group it owns) and rolls them to a new image on request.
# Settings chosen here:
#   - one launch template per group that REQUIRES IMDSv2 and encrypts the root volume,
#   - one shared node role with exactly the three AWS-managed policies a node needs, behind the boundary,
#   - on-demand and spot groups side by side, each with its own labels and taints.

module "labels" {
  source = "../labels"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  components  = [var.name]
}

locals {
  base_name = module.labels.names[var.name]
}

data "aws_partition" "current" {}

# The identity every node (the EC2 instance, not the pods) uses to join the cluster and pull images.
module "node_role" {
  source = "../iam-role"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  name        = "${var.name}-role"
  description = "Assumed by the EC2 worker nodes of ${var.cluster_name} to join the cluster and pull images"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  permissions_boundary = var.permissions_boundary
  managed_policy_arns = concat([
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
  ], var.additional_node_policy_arns)
}

# Instances are built from this. No image is named, so EKS picks the right EKS-optimized one for ami_type
# and the Kubernetes version, and can replace it during an update.
resource "aws_launch_template" "this" {
  for_each = var.node_groups

  name_prefix = "${local.base_name}-${each.key}-"
  description = "Nodes of group ${each.key} in ${var.cluster_name}"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only: a session token is needed to read credentials
    http_put_response_hop_limit = var.metadata_hop_limit
    instance_metadata_tags      = "disabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = each.value.disk_size_gib
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.ebs_kms_key_arn
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(module.labels.tags, { Name = "${local.base_name}-${each.key}" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(module.labels.tags, { Name = "${local.base_name}-${each.key}" })
  }

  tags = module.labels.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = var.cluster_name
  node_group_name = "${local.base_name}-${each.key}"
  node_role_arn   = module.node_role.role_arn
  subnet_ids      = var.subnet_ids

  capacity_type  = each.value.capacity_type
  instance_types = each.value.instance_types
  ami_type       = each.value.ami_type

  scaling_config {
    min_size     = each.value.min_size
    max_size     = each.value.max_size
    desired_size = each.value.desired_size
  }

  update_config {
    max_unavailable = each.value.max_unavailable
  }

  launch_template {
    id      = aws_launch_template.this[each.key].id
    version = aws_launch_template.this[each.key].latest_version
  }

  labels = merge(each.value.labels, { "node-group" = each.key })

  dynamic "taint" {
    for_each = each.value.taints

    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = merge(module.labels.tags, { Name = "${local.base_name}-${each.key}" })

  # A cluster autoscaler or Karpenter changes desired_size at run time; Terraform must not undo that.
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}
