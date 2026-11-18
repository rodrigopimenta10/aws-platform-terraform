variable "project" {
  description = "Passed to the labels module. Lowercase letters, digits and hyphens, 2-20 characters."
  type        = string
}

variable "environment" {
  description = "Passed to the labels module: dev, staging, prod or live."
  type        = string
}

variable "owner" {
  description = "Passed to the labels module: the owner tag value."
  type        = string
}

variable "allowed_services" {
  description = "IAM service prefixes roles under this boundary may use, such as \"s3\" or \"logs\". Each becomes \"<prefix>:*\" in the boundary's Allow. Anything not listed is out of reach for every role, whatever its own policies say."
  type        = list(string)

  validation {
    condition     = length(var.allowed_services) > 0 && alltrue([for s in var.allowed_services : can(regex("^[a-z0-9-]+$", s))])
    error_message = "allowed_services needs at least one service prefix of lowercase letters, digits and hyphens (for example \"s3\"). Use no wildcards."
  }
}

variable "allowed_regions" {
  description = "Regions roles under this boundary may call. Global services (IAM, STS, Route 53 and similar) are exempt. Default is us-east-1 only."
  type        = list(string)
  default     = ["us-east-1"]

  validation {
    condition     = length(var.allowed_regions) > 0 && alltrue([for r in var.allowed_regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", r))])
    error_message = "allowed_regions needs at least one region name such as us-east-1."
  }
}
