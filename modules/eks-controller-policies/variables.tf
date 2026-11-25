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

variable "cluster_name" {
  description = "Name of the EKS cluster the controllers run in (modules/eks output cluster_name). Scopes the Karpenter policy to this cluster's resources."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-Za-z][0-9A-Za-z_-]{0,99}$", var.cluster_name))
    error_message = "cluster_name must be a valid EKS cluster name (letters, digits, hyphens and underscores)."
  }
}

variable "region" {
  description = "AWS region of the cluster. Karpenter's EC2 and EKS permissions are limited to it."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must look like eu-west-1."
  }
}

variable "create_lb_controller_policy" {
  description = "Create the managed policy for the AWS Load Balancer Controller."
  type        = bool
  default     = true
}

variable "create_karpenter_policy" {
  description = "Create the managed policy for the Karpenter controller. Needs karpenter_node_role_arn."
  type        = bool
  default     = true
}

variable "karpenter_node_role_arn" {
  description = "ARN of the IAM role Karpenter-launched nodes run with (modules/eks-node-group role). Karpenter may pass exactly this role to EC2 and no other."
  type        = string
  default     = null

  validation {
    condition     = var.karpenter_node_role_arn == null || can(regex("^arn:[a-z-]+:iam::[0-9]{12}:role/.+$", coalesce(var.karpenter_node_role_arn, "x")))
    error_message = "karpenter_node_role_arn must be an IAM role ARN."
  }
}

variable "karpenter_interruption_queue_arn" {
  description = "ARN of the SQS queue that receives Spot interruption and health events. null leaves interruption handling off."
  type        = string
  default     = null

  validation {
    condition     = var.karpenter_interruption_queue_arn == null || can(regex("^arn:[a-z-]+:sqs:[a-z0-9-]+:[0-9]{12}:.+$", coalesce(var.karpenter_interruption_queue_arn, "x")))
    error_message = "karpenter_interruption_queue_arn must be an SQS queue ARN."
  }
}

variable "tags" {
  description = "Extra tags merged over the standard tag map."
  type        = map(string)
  default     = {}
}
