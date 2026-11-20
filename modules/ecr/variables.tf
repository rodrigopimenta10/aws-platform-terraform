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

variable "repositories" {
  description = "Repositories to create, keyed by a short name (lowercase letters, digits, hyphens). The key becomes the repository name <project>-<environment>-<key>. keep_last_images is how many images the lifecycle policy keeps (1 to 1000). force_delete lets Terraform destroy a repository that still holds images; leave it false outside throwaway drill stacks."
  type = map(object({
    keep_last_images = optional(number, 30)
    force_delete     = optional(bool, false)
  }))

  validation {
    condition     = length(var.repositories) > 0
    error_message = "repositories must contain at least one repository."
  }

  validation {
    condition     = alltrue([for k in keys(var.repositories) : can(regex("^[a-z][a-z0-9-]{0,29}$", k))])
    error_message = "Repository keys must be 1-30 characters: lowercase letters, digits and hyphens, starting with a letter."
  }

  validation {
    condition     = alltrue([for r in values(var.repositories) : r.keep_last_images >= 1 && r.keep_last_images <= 1000 && floor(r.keep_last_images) == r.keep_last_images])
    error_message = "keep_last_images must be a whole number from 1 to 1000."
  }
}

variable "kms_key_arn" {
  description = "ARN of the customer-managed KMS key that encrypts the images (see modules/kms). Required: the module offers no unencrypted or AWS-owned-key option."
  type        = string

  validation {
    condition     = can(regex("^arn:[a-z-]+:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias."
  }
}

variable "untagged_expiry_days" {
  description = "Days after which untagged images are expired (1 to 365)."
  type        = number
  default     = 7

  validation {
    condition     = var.untagged_expiry_days >= 1 && var.untagged_expiry_days <= 365 && floor(var.untagged_expiry_days) == var.untagged_expiry_days
    error_message = "untagged_expiry_days must be a whole number from 1 to 365."
  }
}
