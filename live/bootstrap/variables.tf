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
