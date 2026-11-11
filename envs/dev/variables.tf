variable "project" {
  description = "Short project name used as the first segment of every resource name (validated by the labels module)."
  type        = string
  default     = "platform"
}

variable "owner" {
  description = "Team or person responsible for the resources. A name or alias, never an email address."
  type        = string
  default     = "platform-team"
}

variable "region" {
  description = "AWS region for this environment."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must look like an AWS region name, for example us-east-1 or eu-west-2."
  }
}

variable "components" {
  description = "Component names to build full resource names for. Later roadmap items add to this list."
  type        = set(string)
  default     = ["vpc", "tfstate"]
}
