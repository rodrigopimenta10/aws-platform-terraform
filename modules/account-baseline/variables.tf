variable "enable_ebs_encryption_by_default" {
  description = "Turn on EBS encryption by default for this region: every new volume and snapshot copy is encrypted."
  type        = bool
  default     = true
}

variable "ebs_default_kms_key_arn" {
  description = "KMS key (ARN) that encrypts new EBS volumes by default. Null keeps the AWS-managed aws/ebs key. Ignored when enable_ebs_encryption_by_default is false."
  type        = string
  default     = null

  validation {
    condition     = var.ebs_default_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]+$", coalesce(var.ebs_default_kms_key_arn, "x")))
    error_message = "ebs_default_kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias."
  }
}

variable "password_minimum_length" {
  description = "Minimum length of IAM user passwords (AWS allows 6 to 128; CIS recommends 14 or more)."
  type        = number
  default     = 14

  validation {
    condition     = var.password_minimum_length >= 14 && var.password_minimum_length <= 128
    error_message = "password_minimum_length must be between 14 and 128."
  }
}

variable "password_max_age_days" {
  description = "Days before a password must be changed. 0 means passwords never expire."
  type        = number
  default     = 90

  validation {
    condition     = var.password_max_age_days >= 0 && var.password_max_age_days <= 1095
    error_message = "password_max_age_days must be between 0 and 1095."
  }
}

variable "password_reuse_prevention" {
  description = "How many previous passwords a user may not reuse (1 to 24)."
  type        = number
  default     = 24

  validation {
    condition     = var.password_reuse_prevention >= 1 && var.password_reuse_prevention <= 24
    error_message = "password_reuse_prevention must be between 1 and 24."
  }
}
