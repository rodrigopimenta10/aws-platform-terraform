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

variable "purpose" {
  description = "What the key protects, as one lowercase word or hyphenated phrase (for example logs or ecr). It becomes the key's alias: alias/<project>-<environment>-<purpose>."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}[a-z0-9]$", var.purpose))
    error_message = "purpose must be 2 to 32 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "description" {
  description = "Sentence shown next to the key in the console. Say what it encrypts, so nobody has to guess before scheduling it for deletion."
  type        = string

  validation {
    condition     = length(var.description) >= 10 && length(var.description) <= 8192
    error_message = "description must be between 10 and 8192 characters."
  }
}

variable "key_administrator_arns" {
  description = "IAM role or user ARNs that may manage the key (rotate, tag, schedule deletion) but not use it to encrypt or decrypt. Keeping the two apart means whoever administers a key cannot read the data it protects."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.key_administrator_arns : can(regex("^arn:[a-z-]+:iam::[0-9]{12}:(role|user)/.+$", a))])
    error_message = "key_administrator_arns must be IAM role or user ARNs."
  }
}

variable "key_user_arns" {
  description = "IAM role or user ARNs that may use the key to encrypt, decrypt and create data keys, but not manage it."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.key_user_arns : can(regex("^arn:[a-z-]+:iam::[0-9]{12}:(role|user)/.+$", a))])
    error_message = "key_user_arns must be IAM role or user ARNs."
  }
}

variable "service_grants" {
  description = "AWS services allowed to use the key, keyed by a short statement name (letters and digits only). Each has the service principal (for example logs.us-east-1.amazonaws.com) and optional encryption_context: key/value pairs the request must carry, which is how a key is limited to one log group, bucket or table."
  type = map(object({
    service            = string
    encryption_context = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.service_grants) : can(regex("^[A-Za-z0-9]+$", k))])
    error_message = "service_grants keys become statement IDs, so they may contain only letters and digits."
  }

  validation {
    condition     = alltrue([for g in values(var.service_grants) : can(regex("^[a-z0-9.-]+\\.amazonaws\\.com$", g.service))])
    error_message = "Each service must be a service principal such as logs.us-east-1.amazonaws.com."
  }
}

variable "rotation_period_in_days" {
  description = "How often AWS rotates the key material, 90 to 2560 days. Rotation is always on; old material is kept so existing data stays readable."
  type        = number
  default     = 365

  validation {
    condition     = var.rotation_period_in_days >= 90 && var.rotation_period_in_days <= 2560
    error_message = "rotation_period_in_days must be between 90 and 2560."
  }
}

variable "deletion_window_in_days" {
  description = "Days AWS waits before really deleting the key after it is scheduled for deletion (7 to 30). Throwaway drill stacks use 7."
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}
