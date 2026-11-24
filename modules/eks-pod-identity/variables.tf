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
  description = "Workload name; the role is called <project>-<environment>-<name>-role. Lowercase letters, digits and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,24}$", var.name))
    error_message = "name must be 1-25 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster the workload runs in (modules/eks output cluster_name)."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-Za-z][0-9A-Za-z_-]{0,99}$", var.cluster_name))
    error_message = "cluster_name must be a valid EKS cluster name (letters, digits, hyphens and underscores)."
  }
}

variable "namespace" {
  description = "Kubernetes namespace of the service account. Only pods in this namespace get the role."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid Kubernetes namespace name (lowercase letters, digits and hyphens)."
  }
}

variable "service_account" {
  description = "Kubernetes service account whose pods get the role. Name it exactly: there are no wildcards."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?$", var.service_account))
    error_message = "service_account must be a valid Kubernetes service account name."
  }
}

variable "permissions_boundary" {
  description = "ARN of the boundary policy that caps the role (modules/iam-boundary output policy_arn). Required in practice: planning fails without it."
  type        = string
  default     = null

  validation {
    condition     = var.permissions_boundary == null || can(regex("^arn:[a-z-]+:iam::[0-9]{12}:policy/.+$", coalesce(var.permissions_boundary, "x")))
    error_message = "permissions_boundary must be an IAM policy ARN."
  }
}

variable "managed_policy_arns" {
  description = "ARNs of managed policies attached to the role."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.managed_policy_arns : can(regex("^arn:[a-z-]+:iam::(aws|[0-9]{12}):policy/.+$", a))])
    error_message = "managed_policy_arns must be IAM managed policy ARNs."
  }
}

variable "policy_json" {
  description = "Optional inline policy for the workload as a JSON string. Prefer naming exact actions and resources."
  type        = string
  default     = null

  validation {
    condition     = var.policy_json == null || can(jsondecode(coalesce(var.policy_json, "{}")).Statement)
    error_message = "policy_json must be a JSON policy document with a Statement."
  }
}
