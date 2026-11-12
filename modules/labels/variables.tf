variable "project" {
  description = "Short project name, used as the first segment of every resource name. Lowercase letters, digits and hyphens, 2-20 characters, starting with a letter."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}$", var.project)) && !endswith(var.project, "-")
    error_message = "project must be 2-20 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "environment" {
  description = "Deployment environment. One of dev, staging, prod, or live (short-lived stacks created and destroyed by the live drill, see live/README.md)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod", "live"], var.environment)
    error_message = "environment must be one of: dev, staging, prod, live."
  }
}

variable "owner" {
  description = "Team or person responsible for the resources (a name or team alias, never a personal email address, because tags are visible in many places)."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9 ._-]{0,62}$", var.owner))
    error_message = "owner must be 1-63 characters of letters, digits, spaces, '.', '_' or '-', starting with a letter or digit. Email addresses are not allowed."
  }
}

variable "components" {
  description = "Optional component names (for example [\"vpc\", \"logs\"]). For each one the module outputs a full resource name in `names`."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.components : can(regex("^[a-z][a-z0-9-]{0,29}$", c))])
    error_message = "Each component must be 1-30 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "extra_tags" {
  description = "Additional tags merged into the standard set. They can never override project, environment, owner or managed-by."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.extra_tags) : !startswith(lower(k), "aws:")])
    error_message = "Tag keys starting with 'aws:' are reserved by AWS."
  }
}
