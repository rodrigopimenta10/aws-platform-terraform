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

variable "vpc_cidr" {
  description = "IPv4 CIDR block of the dev VPC. Validated by modules/vpc (between /16 and /22)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones for the VPC (2 or 3). Validated by modules/vpc."
  type        = number
  default     = 3
}

variable "single_nat_gateway" {
  description = "true: one NAT gateway for all AZs (cheaper, dev default). false: one per AZ (highly available). See ADR 0004."
  type        = bool
  default     = true
}

variable "flow_log_retention_in_days" {
  description = "Days CloudWatch keeps VPC flow log records. Validated by modules/vpc-flow-logs. Lower it (for example 30) to save storage cost in a scratch account."
  type        = number
  default     = 365
}
