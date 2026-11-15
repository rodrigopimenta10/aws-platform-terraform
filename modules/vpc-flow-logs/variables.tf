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

variable "vpc_id" {
  description = "ID of the VPC to record traffic for (modules/vpc output vpc_id)."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must look like vpc-0123456789abcdef0."
  }
}

variable "retention_in_days" {
  description = "How long CloudWatch Logs keeps flow log records before deleting them. Must be one of the values CloudWatch accepts. Storage is billed per GB-month, so shorter is cheaper; 0 (never expire) is rejected on purpose."
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.retention_in_days)
    error_message = "retention_in_days must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 or 3653). Never-expire (0) is not allowed."
  }
}

variable "traffic_type" {
  description = "Which traffic to record: ACCEPT (allowed by security groups and network ACLs), REJECT (blocked) or ALL. ALL is the most useful for investigations and the most expensive."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.traffic_type)
    error_message = "traffic_type must be ACCEPT, REJECT or ALL."
  }
}

variable "max_aggregation_interval" {
  description = "Seconds over which packets of one flow are grouped into a single record: 60 (finer detail, more records) or 600 (default AWS behaviour, cheaper)."
  type        = number
  default     = 600

  validation {
    condition     = contains([60, 600], var.max_aggregation_interval)
    error_message = "max_aggregation_interval must be 60 or 600."
  }
}

variable "kms_deletion_window_in_days" {
  description = "Days AWS waits before really deleting the key after it is scheduled for deletion (7 to 30). The shortest window is used by throwaway drill stacks."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30
    error_message = "kms_deletion_window_in_days must be between 7 and 30."
  }
}

variable "permissions_boundary" {
  description = "ARN of an IAM permissions boundary policy to attach to the role this module creates, or null for none. Drill stacks pass the boundary the live-drill role requires."
  type        = string
  default     = null

  validation {
    condition     = var.permissions_boundary == null || can(regex("^arn:[a-z-]+:iam::[0-9]{12}:policy/.+$", var.permissions_boundary))
    error_message = "permissions_boundary must be null or an IAM policy ARN."
  }
}
