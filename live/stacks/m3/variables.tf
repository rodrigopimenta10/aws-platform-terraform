variable "region" {
  description = "AWS region to apply into. The drill role denies every other region, so leave it at us-east-1 unless live/bootstrap changes too."
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

variable "permissions_boundary_arn" {
  description = "ARN of the IAM permissions boundary every role in this stack must carry. The live-drill workflow sets it through TF_VAR_permissions_boundary_arn; the drill role cannot create a role without it."
  type        = string
  default     = null

  validation {
    condition     = var.permissions_boundary_arn == null || can(regex("^arn:[a-z-]+:iam::[0-9]{12}:policy/.+$", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be null or an IAM policy ARN."
  }
}
