variable "project" {
  description = "Short project name, passed to the labels module (see modules/labels)."
  type        = string
}

variable "environment" {
  description = "Deployment environment: dev, staging or prod. Validated by the labels module."
  type        = string
}

variable "owner" {
  description = "Team or person responsible for the VPC, used for the owner tag. Validated by the labels module."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block of the VPC, between /16 and /22. Use a private range (RFC 1918) that does not overlap other VPCs you may peer with. 10.0.0.0/16 is the default."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 22
    error_message = "vpc_cidr must be a valid IPv4 CIDR block with a prefix length between /16 and /22."
  }

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && cidrhost(var.vpc_cidr, 0) == split("/", var.vpc_cidr)[0]
    error_message = "vpc_cidr must be written in network form (for example 10.0.0.0/16, not 10.0.1.5/16)."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread the subnets across (2 or 3). Production-style default is 3."
  type        = number
  default     = 3

  validation {
    condition     = contains([2, 3], var.az_count)
    error_message = "az_count must be 2 or 3."
  }
}

variable "private_subnet_newbits" {
  description = "Bits added to a tier block's prefix to size each private subnet. The VPC is first split into four equal tier blocks (2 bits), so a /16 VPC with 2 gives /20 private subnets (4,091 usable IPs each). Private subnets are the biggest because EKS pods take VPC IPs."
  type        = number
  default     = 2

  validation {
    condition     = var.private_subnet_newbits >= 2 && var.private_subnet_newbits <= 8
    error_message = "private_subnet_newbits must be between 2 and 8 (2 is the minimum so 3 subnets fit in a tier block)."
  }
}

variable "public_subnet_newbits" {
  description = "Bits added to a tier block's prefix to size each public subnet. A /16 VPC with 4 gives /22 public subnets. Public subnets only hold load balancers and NAT gateways, so they can be small."
  type        = number
  default     = 4

  validation {
    condition     = var.public_subnet_newbits >= 2 && var.public_subnet_newbits <= 8
    error_message = "public_subnet_newbits must be between 2 and 8."
  }
}

variable "isolated_subnet_newbits" {
  description = "Bits added to a tier block's prefix to size each isolated subnet (databases, no route to the internet). A /16 VPC with 4 gives /22 isolated subnets."
  type        = number
  default     = 4

  validation {
    condition     = var.isolated_subnet_newbits >= 2 && var.isolated_subnet_newbits <= 8
    error_message = "isolated_subnet_newbits must be between 2 and 8."
  }
}

variable "eks_cluster_names" {
  description = "Names of EKS clusters that will use this VPC. Each one adds the kubernetes.io/cluster/<name>=shared tag to every subnet so EKS and the load balancer controller can discover them."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for n in var.eks_cluster_names : can(regex("^[0-9A-Za-z][0-9A-Za-z_-]{0,99}$", n))])
    error_message = "Each EKS cluster name must be 1-100 characters: letters, digits, hyphens and underscores, starting with a letter or digit."
  }
}
