variable "project" {
  description = "Short project name, passed to the labels module (see modules/labels)."
  type        = string
}

variable "environment" {
  description = "Deployment environment: dev, staging, prod or live. Validated by the labels module."
  type        = string
}

variable "owner" {
  description = "Team or person responsible, used for the owner tag. Validated by the labels module."
  type        = string
}

variable "name" {
  description = "Component name; the EBS CSI role is called <project>-<environment>-<name>-ebs-csi-role. Lowercase letters, digits and hyphens."
  type        = string
  default     = "addons"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,14}$", var.name))
    error_message = "name must be 1-15 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "cluster_name" {
  description = "Name of the cluster the add-ons are installed into (modules/eks output cluster_name)."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-Za-z][0-9A-Za-z_-]{0,99}$", var.cluster_name))
    error_message = "cluster_name must be a valid EKS cluster name (letters, digits, hyphens and underscores)."
  }
}

variable "permissions_boundary" {
  description = "ARN of the boundary policy for the role this module creates for the EBS CSI driver (modules/iam-boundary output policy_arn). Effectively required when aws-ebs-csi-driver is installed without its own role."
  type        = string
  default     = null

  validation {
    condition     = var.permissions_boundary == null || can(regex("^arn:[a-z-]+:iam::[0-9]{12}:policy/.+$", coalesce(var.permissions_boundary, "x")))
    error_message = "permissions_boundary must be an IAM policy ARN."
  }
}

variable "addons" {
  description = <<-EOT
    Add-ons to install, keyed by add-on name (vpc-cni, coredns, kube-proxy, aws-ebs-csi-driver,
    eks-pod-identity-agent, ...). Every version is pinned here on purpose: there is no default, so an
    upgrade is always a reviewed change. Find valid versions with
    `aws eks describe-addon-versions --addon-name <name> --kubernetes-version <minor>`.
      version                      Required. For example v1.12.1-eksbuild.2.
      configuration_values         Optional JSON string with the add-on's own settings (replica counts, resources).
      resolve_conflicts_on_update  OVERWRITE (default; your pinned values win) or PRESERVE (keep manual in-cluster edits).
      pod_identity_role_arn        Optional. Role the add-on's service account assumes through Pod Identity. For
                                   aws-ebs-csi-driver, leave it null and the module creates a suitable role.
  EOT
  type = map(object({
    version                     = string
    configuration_values        = optional(string)
    resolve_conflicts_on_update = optional(string, "OVERWRITE")
    pod_identity_role_arn       = optional(string)
  }))

  validation {
    condition     = length(var.addons) > 0
    error_message = "addons must name at least one add-on."
  }

  validation {
    condition     = alltrue([for k, a in var.addons : can(regex("^[a-z][a-z0-9-]{1,63}$", k))])
    error_message = "Add-on names are lowercase letters, digits and hyphens, for example vpc-cni."
  }

  validation {
    condition     = alltrue([for k, a in var.addons : can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", a.version))])
    error_message = "Each add-on version must be pinned exactly, for example v1.12.1-eksbuild.2. 'latest' and partial versions are not accepted."
  }

  validation {
    condition     = alltrue([for k, a in var.addons : contains(["OVERWRITE", "PRESERVE"], a.resolve_conflicts_on_update)])
    error_message = "resolve_conflicts_on_update must be OVERWRITE or PRESERVE."
  }

  validation {
    condition     = alltrue([for k, a in var.addons : a.configuration_values == null || can(jsondecode(coalesce(a.configuration_values, "{}")))])
    error_message = "configuration_values must be a JSON document."
  }

  validation {
    condition     = alltrue([for k, a in var.addons : a.pod_identity_role_arn == null || can(regex("^arn:[a-z-]+:iam::[0-9]{12}:role/.+$", coalesce(a.pod_identity_role_arn, "x")))])
    error_message = "pod_identity_role_arn must be an IAM role ARN."
  }
}
