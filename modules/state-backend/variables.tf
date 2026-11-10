variable "project" {
  description = "Short project name, passed to the labels module. Lowercase letters, digits and hyphens, 2-20 characters."
  type        = string
}

variable "environment" {
  description = "Deployment environment. One of dev, staging, prod."
  type        = string
}

variable "owner" {
  description = "Team or person responsible for the bucket (never an email address)."
  type        = string
}

variable "noncurrent_version_expiration_days" {
  description = "Days to keep old (noncurrent) versions of a state file before S3 deletes them. Versions are your undo history for state, so keep this generous."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days >= 7 && var.noncurrent_version_expiration_days == floor(var.noncurrent_version_expiration_days)
    error_message = "noncurrent_version_expiration_days must be a whole number of at least 7, so a bad apply can be rolled back."
  }
}

variable "kms_deletion_window_in_days" {
  description = "Waiting period (7-30 days) before AWS actually deletes the KMS key after it is scheduled for deletion."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30 && var.kms_deletion_window_in_days == floor(var.kms_deletion_window_in_days)
    error_message = "kms_deletion_window_in_days must be a whole number between 7 and 30."
  }
}

variable "force_destroy" {
  description = "Allow `terraform destroy` to delete the bucket even when it still contains state files. Leave false for anything real; the tests set it to true so they can clean up."
  type        = bool
  default     = false
}

variable "extra_tags" {
  description = "Additional tags merged into the standard set from the labels module."
  type        = map(string)
  default     = {}
}
