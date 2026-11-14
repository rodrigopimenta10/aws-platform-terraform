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
  description = "ID of the VPC to add endpoints to (modules/vpc output vpc_id). The VPC needs DNS support and DNS hostnames enabled for private DNS to work; modules/vpc does that."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must look like vpc-0123456789abcdef0."
  }
}

variable "allowed_cidr_blocks" {
  description = "IPv4 CIDR blocks allowed to reach the interface endpoints on port 443. Usually the VPC CIDR (modules/vpc output vpc_cidr_block), or just the private subnet CIDRs for tighter access."
  type        = list(string)

  validation {
    condition     = length(var.allowed_cidr_blocks) > 0 && alltrue([for c in var.allowed_cidr_blocks : can(cidrhost(c, 0))])
    error_message = "allowed_cidr_blocks needs at least one valid IPv4 CIDR block."
  }

  validation {
    condition     = !contains(var.allowed_cidr_blocks, "0.0.0.0/0")
    error_message = "allowed_cidr_blocks must not contain 0.0.0.0/0: endpoints are for traffic from inside the VPC."
  }
}

variable "subnet_ids" {
  description = "Subnets that get an endpoint network interface, one per AZ you want covered (modules/vpc output private_subnet_ids). Interface endpoints bill per subnet, so fewer subnets cost less but lose AZ redundancy."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1 && alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", s))])
    error_message = "subnet_ids needs at least one ID that looks like subnet-0123456789abcdef0."
  }
}

variable "route_table_ids" {
  description = "Route tables that get a route to the S3 gateway endpoint: the private route tables and the isolated one (modules/vpc outputs private_route_table_ids and isolated_route_table_id)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for r in var.route_table_ids : can(regex("^rtb-[0-9a-f]+$", r))])
    error_message = "Each route table ID must look like rtb-0123456789abcdef0."
  }
}

variable "enable_s3_gateway_endpoint" {
  description = "Create the S3 gateway endpoint. It is free, and ECR image layers come from S3, so leave it on unless another endpoint module already provides it."
  type        = bool
  default     = true
}

variable "s3_endpoint_policy" {
  description = "Optional JSON endpoint policy for the S3 gateway endpoint. null keeps AWS's default (allow everything through the endpoint; IAM and bucket policies still apply). Use it to limit which buckets can be reached from the VPC."
  type        = string
  default     = null

  validation {
    condition     = var.s3_endpoint_policy == null || can(jsondecode(var.s3_endpoint_policy))
    error_message = "s3_endpoint_policy must be valid JSON or null."
  }
}

variable "interface_endpoints" {
  description = "Interface endpoints to create. Any of: ecr_api, ecr_dkr, sts, logs. Pulling ECR images needs both ecr_api and ecr_dkr (plus the S3 gateway endpoint)."
  type        = list(string)
  default     = ["ecr_api", "ecr_dkr", "sts", "logs"]

  validation {
    condition     = alltrue([for e in var.interface_endpoints : contains(["ecr_api", "ecr_dkr", "sts", "logs"], e)])
    error_message = "interface_endpoints may only contain ecr_api, ecr_dkr, sts and logs."
  }

  validation {
    condition     = length(distinct(var.interface_endpoints)) == length(var.interface_endpoints)
    error_message = "interface_endpoints must not contain duplicates."
  }
}

variable "private_dns_enabled" {
  description = "Make the normal service hostname (for example api.ecr.us-east-1.amazonaws.com) resolve to the endpoint inside the VPC. Leave true so SDKs and kubelet need no configuration."
  type        = bool
  default     = true
}
