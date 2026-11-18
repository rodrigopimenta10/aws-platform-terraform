variable "project" {
  description = "Passed to the labels module. Lowercase letters, digits and hyphens, 2-20 characters."
  type        = string
}

variable "environment" {
  description = "Passed to the labels module: dev, staging, prod or live."
  type        = string
}

variable "owner" {
  description = "Passed to the labels module: the owner tag value."
  type        = string
}

variable "name" {
  description = "Component name; the role is called <project>-<environment>-<name>. Lowercase letters, digits and hyphens."
  type        = string
}

variable "description" {
  description = "What the role is for. Shown in the IAM console."
  type        = string
}

variable "assume_role_policy" {
  description = "Trust policy as a JSON string: who may assume the role (a service, an account or an OIDC provider)."
  type        = string

  validation {
    condition     = can(jsondecode(var.assume_role_policy).Statement)
    error_message = "assume_role_policy must be a JSON policy document with a Statement."
  }
}

variable "permissions_boundary" {
  description = "ARN of the boundary policy that caps the role (modules/iam-boundary output policy_arn). Required in practice: the role fails its precondition when this is null."
  type        = string
  default     = null

  validation {
    condition     = var.permissions_boundary == null || can(regex("^arn:[a-z-]+:iam::[0-9]{12}:policy/.+$", coalesce(var.permissions_boundary, "x")))
    error_message = "permissions_boundary must be an IAM policy ARN."
  }
}

variable "managed_policy_arns" {
  description = "ARNs of managed policies attached to the role: its permissions, inside the boundary."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.managed_policy_arns : can(regex("^arn:[a-z-]+:iam::(aws|[0-9]{12}):policy/.+$", a))])
    error_message = "managed_policy_arns must be IAM managed policy ARNs."
  }
}

variable "max_session_duration" {
  description = "Seconds the role's credentials last, 3600 to 43200."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds."
  }
}
