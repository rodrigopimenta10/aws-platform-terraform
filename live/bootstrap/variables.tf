variable "region" {
  description = "The one AWS region live drills may use. The provider deploys the state bucket here, and the role's guardrail policy denies regional API calls anywhere else."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must look like an AWS region name, for example us-east-1."
  }
}

variable "owner" {
  description = "Team or person responsible, used for the owner tag. A name or alias, never an email address."
  type        = string
  default     = "platform-team"
}

variable "github_repository" {
  description = "GitHub repository (\"<owner>/<name>\") whose live-drill workflow may assume the role."
  type        = string
  default     = "rodrigopimenta10/aws-platform-terraform"

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "github_repository must be \"<owner>/<name>\" with no wildcards."
  }
}

variable "github_owner_id" {
  description = "Numeric ID of the repository's owner on GitHub (`gh api users/<owner> --jq .id`). Part of the OIDC subject GitHub sends for this repository."
  type        = string
  default     = "11894505"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "github_owner_id must be digits only."
  }
}

variable "github_repository_id" {
  description = "Numeric ID of the repository on GitHub (`gh api repos/<owner>/<repo> --jq .id`). Part of the OIDC subject GitHub sends for this repository."
  type        = string
  default     = "1451999319"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id must be digits only."
  }
}

variable "github_environment" {
  description = "GitHub environment the workflow job must run in. Its protection rules (required reviewer, main branch only) are what make each drill a human decision."
  type        = string
  default     = "aws-live"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,255}$", var.github_environment))
    error_message = "github_environment must be a plain environment name with no wildcards."
  }
}

variable "max_session_duration" {
  description = "Longest session, in seconds, the role's temporary credentials can last (900-3600). One hour bounds how long leaked credentials stay useful."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 900 && var.max_session_duration <= 3600 && var.max_session_duration == floor(var.max_session_duration)
    error_message = "max_session_duration must be a whole number of seconds between 900 and 3600."
  }
}

variable "allowed_instance_types" {
  description = "EC2 instance types (wildcards allowed) the drill role may launch directly. Small burstable families only."
  type        = list(string)
  default     = ["t3.nano", "t3.micro", "t3.small", "t3.medium", "t3.large", "t4g.nano", "t4g.micro", "t4g.small", "t4g.medium", "t4g.large"]

  validation {
    condition     = length(var.allowed_instance_types) > 0 && alltrue([for t in var.allowed_instance_types : can(regex("^[a-z0-9]+\\.[a-z0-9*]+$", t))])
    error_message = "allowed_instance_types must be instance type names like t3.medium."
  }
}

variable "guard_budget_usd" {
  description = "Monthly account spend (USD) at which AWS Budgets attaches a deny-all policy to the drill role. A backstop: billing data lags by hours."
  type        = number
  default     = 15

  validation {
    condition     = var.guard_budget_usd >= 1 && var.guard_budget_usd <= 200
    error_message = "guard_budget_usd must be between 1 and 200."
  }
}

variable "alert_email" {
  description = "Where the guard budget and its stop action send email. Set it in the gitignored terraform.tfvars; never commit it (the repo is public)."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be an email address."
  }
}
