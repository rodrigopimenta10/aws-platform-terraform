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

variable "github_repository" {
  description = "The one repository whose workflows may assume the role, as <owner>/<repo>. A token from any other repository carries a different subject and is refused."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "github_repository must look like owner/repo, with no wildcards."
  }
}

variable "github_owner_id" {
  description = "Numeric ID of the repository owner. Set it together with github_repository_id when the repository's tokens carry IDs in their subject (repo:<owner>@<id>/<repo>@<id>:...), which pins the role to this exact repository so a deleted and re-created one with the same name cannot match. Find both with `gh api repos/<owner>/<repo> --jq '.owner.id, .id'`."
  type        = string
  default     = null

  validation {
    condition     = var.github_owner_id == null || can(regex("^[0-9]+$", coalesce(var.github_owner_id, "x")))
    error_message = "github_owner_id must be digits only."
  }
}

variable "github_repository_id" {
  description = "Numeric ID of the repository. Must be set together with github_owner_id, or both left null."
  type        = string
  default     = null

  validation {
    condition     = var.github_repository_id == null || can(regex("^[0-9]+$", coalesce(var.github_repository_id, "x")))
    error_message = "github_repository_id must be digits only."
  }

  validation {
    condition     = (var.github_repository_id == null) == (var.github_owner_id == null)
    error_message = "Set github_owner_id and github_repository_id together, or leave both null."
  }
}

variable "allowed_branches" {
  description = "Branches whose workflow runs may assume the role. Exact names only: a wildcard would let anyone who can push a branch deploy."
  type        = list(string)
  default     = ["main"]

  validation {
    condition     = alltrue([for b in var.allowed_branches : can(regex("^[A-Za-z0-9._/-]+$", b))])
    error_message = "Branch names may contain letters, digits and . _ / - only. Wildcards are not allowed."
  }
}

variable "allowed_environments" {
  description = "GitHub Actions environments (the `environment:` key of a job) whose runs may assume the role. Environments can require a human approval before a job starts, which makes them the safest trust for production."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.allowed_environments : can(regex("^[A-Za-z0-9._-]+$", e))])
    error_message = "Environment names may contain letters, digits and . _ - only. Wildcards are not allowed."
  }
}

variable "allow_pull_requests" {
  description = "Whether workflow runs triggered by pull requests may assume the role. Off by default, because a pull request can come from a fork and run changed workflow code. Turn it on only for a read-only role."
  type        = bool
  default     = false
}

variable "create_provider" {
  description = "Create the GitHub OIDC identity provider. AWS allows one provider per URL per account, so set this to false when the account already has one (for example from live/bootstrap), and the role will trust the existing provider."
  type        = bool
  default     = true
}

variable "managed_policy_arns" {
  description = "ARNs of IAM managed policies to attach to the role. These are the role's permissions: the trust policy only says who may use the role, not what it can do. Start from the narrowest policy that works."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.managed_policy_arns : can(regex("^arn:[a-z-]+:iam::(aws|[0-9]{12}):policy/.+$", a))])
    error_message = "managed_policy_arns must be IAM managed policy ARNs."
  }
}

variable "permissions_boundary" {
  description = "ARN of a permissions boundary policy to cap the role. Default null for none. Drill stacks pass the boundary the drill role requires."
  type        = string
  default     = null

  validation {
    condition     = var.permissions_boundary == null || can(regex("^arn:[a-z-]+:iam::[0-9]{12}:policy/.+$", coalesce(var.permissions_boundary, "x")))
    error_message = "permissions_boundary must be an IAM policy ARN."
  }
}

variable "max_session_duration" {
  description = "Seconds the role's credentials last, 3600 to 43200. An hour is plenty for a deploy job, and a leaked token is useless sooner."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200."
  }
}
