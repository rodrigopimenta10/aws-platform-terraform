# Unit tests: mock provider, plan only. No network, no emulator.
mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/platform-dev-addons-ebs-csi-role"
    }
  }
}

variables {
  project              = "platform"
  environment          = "dev"
  owner                = "platform-team"
  cluster_name         = "platform-dev-eks"
  permissions_boundary = "arn:aws:iam::123456789012:policy/platform-dev-boundary"

  addons = {
    "vpc-cni"    = { version = "v1.19.5-eksbuild.1" }
    "coredns"    = { version = "v1.12.1-eksbuild.2" }
    "kube-proxy" = { version = "v1.35.0-eksbuild.2" }
  }
}

run "pins_each_addon_to_the_cluster" {
  command = plan

  assert {
    condition     = length(aws_eks_addon.this) == 3 && alltrue([for k, a in aws_eks_addon.this : a.cluster_name == "platform-dev-eks"])
    error_message = "One aws_eks_addon per entry, all on the named cluster."
  }

  assert {
    condition     = aws_eks_addon.this["coredns"].addon_version == "v1.12.1-eksbuild.2" && aws_eks_addon.this["vpc-cni"].addon_version == "v1.19.5-eksbuild.1"
    error_message = "The version in the variable is the version requested."
  }

  assert {
    condition     = alltrue([for k, a in aws_eks_addon.this : a.resolve_conflicts_on_create == "OVERWRITE" && a.resolve_conflicts_on_update == "OVERWRITE"])
    error_message = "By default the pinned configuration wins over what is in the cluster, on create and on update."
  }

  assert {
    condition     = aws_eks_addon.this["kube-proxy"].tags["managed-by"] == "terraform" && aws_eks_addon.this["kube-proxy"].tags["Name"] == "platform-dev-eks-kube-proxy"
    error_message = "Add-ons carry the standard tags and a Name."
  }
}

run "no_role_is_created_without_the_ebs_csi_driver" {
  command = plan

  assert {
    condition     = length(module.ebs_csi_role) == 0 && output.ebs_csi_role_arn == null
    error_message = "Only the EBS CSI driver needs an IAM role; the networking add-ons use the node role."
  }
}

run "ebs_csi_driver_gets_a_pod_identity_role_behind_the_boundary" {
  command = plan

  variables {
    addons = {
      "eks-pod-identity-agent" = { version = "v1.3.7-eksbuild.2" }
      "aws-ebs-csi-driver"     = { version = "v1.45.0-eksbuild.2" }
    }
  }

  assert {
    condition     = length(module.ebs_csi_role) == 1 && module.ebs_csi_role[0].permissions_boundary == "arn:aws:iam::123456789012:policy/platform-dev-boundary"
    error_message = "The module creates the driver's role and it carries the boundary."
  }

  assert {
    condition     = one(aws_eks_addon.this["aws-ebs-csi-driver"].pod_identity_association).service_account == "ebs-csi-controller-sa"
    error_message = "The association targets the driver's controller service account."
  }

  assert {
    condition     = length(aws_eks_addon.this["eks-pod-identity-agent"].pod_identity_association) == 0
    error_message = "Only add-ons that need AWS access get an association."
  }
}

run "a_supplied_role_replaces_the_created_one" {
  command = plan

  variables {
    addons = {
      "eks-pod-identity-agent" = { version = "v1.3.7-eksbuild.2" }
      "aws-ebs-csi-driver" = {
        version               = "v1.45.0-eksbuild.2"
        pod_identity_role_arn = "arn:aws:iam::123456789012:role/custom-ebs-csi"
      }
    }
  }

  assert {
    condition     = length(module.ebs_csi_role) == 0 && one(aws_eks_addon.this["aws-ebs-csi-driver"].pod_identity_association).role_arn == "arn:aws:iam::123456789012:role/custom-ebs-csi"
    error_message = "A caller-supplied role is used as is and no second role is created."
  }
}

run "configuration_values_are_passed_through" {
  command = plan

  variables {
    addons = {
      "coredns" = {
        version                     = "v1.12.1-eksbuild.2"
        configuration_values        = "{\"replicaCount\":1}"
        resolve_conflicts_on_update = "PRESERVE"
      }
    }
  }

  assert {
    condition     = jsondecode(aws_eks_addon.this["coredns"].configuration_values).replicaCount == 1 && aws_eks_addon.this["coredns"].resolve_conflicts_on_update == "PRESERVE"
    error_message = "Settings and the conflict policy reach the add-on."
  }
}

run "ebs_csi_driver_requires_the_pod_identity_agent" {
  command = plan

  variables {
    addons = {
      "aws-ebs-csi-driver" = { version = "v1.45.0-eksbuild.2" }
    }
  }

  expect_failures = [aws_eks_addon.this]
}

run "rejects_an_unpinned_version" {
  command = plan

  variables {
    addons = { "coredns" = { version = "latest" } }
  }

  expect_failures = [var.addons]
}

run "rejects_a_partial_version" {
  command = plan

  variables {
    addons = { "coredns" = { version = "v1.12" } }
  }

  expect_failures = [var.addons]
}

run "rejects_an_empty_addon_list" {
  command = plan

  variables {
    addons = {}
  }

  expect_failures = [var.addons]
}

run "rejects_a_bad_conflict_policy" {
  command = plan

  variables {
    addons = { "coredns" = { version = "v1.12.1-eksbuild.2", resolve_conflicts_on_update = "NONE" } }
  }

  expect_failures = [var.addons]
}

run "rejects_configuration_that_is_not_json" {
  command = plan

  variables {
    addons = { "coredns" = { version = "v1.12.1-eksbuild.2", configuration_values = "replicaCount: 1" } }
  }

  expect_failures = [var.addons]
}

run "rejects_a_bad_role_arn" {
  command = plan

  variables {
    addons = { "aws-ebs-csi-driver" = { version = "v1.45.0-eksbuild.2", pod_identity_role_arn = "my-role" } }
  }

  expect_failures = [var.addons]
}

run "rejects_a_bad_cluster_name" {
  command = plan

  variables {
    cluster_name = "bad name!"
  }

  expect_failures = [var.cluster_name]
}
