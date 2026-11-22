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

variable "name" {
  description = "Component name. The shared node role is <project>-<environment>-<name>-role and each node group is <project>-<environment>-<name>-<group key>. Lowercase letters, digits and hyphens."
  type        = string
  default     = "nodes"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,19}$", var.name))
    error_message = "name must be 1-20 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster the nodes join (modules/eks output cluster_name)."
  type        = string

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}

variable "subnet_ids" {
  description = "Subnets the nodes launch in, in at least two availability zones. Use the private subnets (modules/vpc output eks_subnet_ids)."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2 && alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", s))])
    error_message = "subnet_ids must hold at least two subnet IDs (subnet-...), in different availability zones."
  }
}

variable "permissions_boundary" {
  description = "ARN of the permissions boundary the node role carries (modules/iam-boundary output policy_arn). Required in practice: modules/iam-role refuses a role without one."
  type        = string
  default     = null
}

variable "ebs_kms_key_arn" {
  description = "KMS key that encrypts each node's root volume. Null uses the AWS-managed aws/ebs key. Volumes are always encrypted."
  type        = string
  default     = null

  validation {
    condition     = var.ebs_kms_key_arn == null || can(regex("^arn:[a-z-]+:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", coalesce(var.ebs_kms_key_arn, "x")))
    error_message = "ebs_kms_key_arn must be a KMS key ARN (not an alias)."
  }
}

variable "metadata_hop_limit" {
  description = "IMDS (instance metadata service) hop limit. 1 means only the node itself can reach its credentials; pods, which sit one network hop further away, cannot. Raise to 2 only for workloads that must read instance metadata, and prefer Pod Identity or IRSA for them."
  type        = number
  default     = 1

  validation {
    condition     = var.metadata_hop_limit >= 1 && var.metadata_hop_limit <= 2
    error_message = "metadata_hop_limit must be 1 or 2."
  }
}

variable "additional_node_policy_arns" {
  description = "Managed policies added to the node role on top of the three EKS needs (worker node, CNI, ECR pull). Keep this empty where you can: every pod on the node can reach the node's permissions unless the hop limit blocks it."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.additional_node_policy_arns : can(regex("^arn:[a-z-]+:iam::(aws|[0-9]{12}):policy/.+$", a))])
    error_message = "additional_node_policy_arns must be IAM managed policy ARNs."
  }
}

variable "node_groups" {
  description = <<-EOT
    Managed node groups, keyed by a short name (lowercase letters, digits, hyphens).
      capacity_type   ON_DEMAND (default) or SPOT. A SPOT group needs at least two instance types so it can draw from more than one spare-capacity pool.
      instance_types  EC2 instance types. Default ["t3.medium"].
      ami_type        EKS-optimized image. Default AL2023_x86_64_STANDARD; use AL2023_ARM_64_STANDARD with t4g/m7g types.
      min_size, max_size, desired_size   scaling bounds; desired_size is only the starting value, because a cluster autoscaler owns it afterwards.
      disk_size_gib   root volume size. Default 30.
      max_unavailable nodes replaced at once during an update. Default 1.
      labels          Kubernetes node labels, for nodeSelector and affinity.
      taints          Kubernetes taints (key, optional value, effect NO_SCHEDULE | PREFER_NO_SCHEDULE | NO_EXECUTE) that keep pods off unless they tolerate it.
  EOT
  type = map(object({
    capacity_type   = optional(string, "ON_DEMAND")
    instance_types  = optional(list(string), ["t3.medium"])
    ami_type        = optional(string, "AL2023_x86_64_STANDARD")
    min_size        = optional(number, 1)
    max_size        = optional(number, 3)
    desired_size    = optional(number, 1)
    disk_size_gib   = optional(number, 30)
    max_unavailable = optional(number, 1)
    labels          = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string, "")
      effect = string
    })), [])
  }))

  validation {
    condition     = length(var.node_groups) > 0
    error_message = "node_groups must define at least one group."
  }

  validation {
    condition     = alltrue([for k, g in var.node_groups : can(regex("^[a-z][a-z0-9-]{0,19}$", k))])
    error_message = "Node group keys must be 1-20 characters: lowercase letters, digits and hyphens, starting with a letter."
  }

  validation {
    condition     = alltrue([for k, g in var.node_groups : contains(["ON_DEMAND", "SPOT"], g.capacity_type)])
    error_message = "capacity_type must be ON_DEMAND or SPOT."
  }

  validation {
    condition     = alltrue([for k, g in var.node_groups : g.capacity_type != "SPOT" || length(g.instance_types) >= 2])
    error_message = "A SPOT node group needs at least two instance types: one type means one capacity pool, and one interruption can remove every node."
  }

  validation {
    condition     = alltrue([for k, g in var.node_groups : length(g.instance_types) >= 1])
    error_message = "Each node group needs at least one instance type."
  }

  validation {
    condition = alltrue([for k, g in var.node_groups :
      g.min_size >= 0 && g.min_size <= g.desired_size && g.desired_size <= g.max_size && g.max_size >= 1
    ])
    error_message = "Scaling must satisfy 0 <= min_size <= desired_size <= max_size and max_size >= 1."
  }

  validation {
    condition     = alltrue([for k, g in var.node_groups : g.disk_size_gib >= 20 && g.disk_size_gib <= 16384])
    error_message = "disk_size_gib must be between 20 and 16384."
  }

  validation {
    condition     = alltrue([for k, g in var.node_groups : g.max_unavailable >= 1])
    error_message = "max_unavailable must be at least 1."
  }

  validation {
    condition = alltrue([for k, g in var.node_groups : alltrue([
      for t in g.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)
    ])])
    error_message = "Taint effect must be NO_SCHEDULE, PREFER_NO_SCHEDULE or NO_EXECUTE."
  }

  validation {
    condition = alltrue([for k, g in var.node_groups : alltrue([
      for l, v in g.labels : !startswith(l, "eks.amazonaws.com/") && !startswith(l, "kubernetes.io/")
    ])])
    error_message = "Label keys under eks.amazonaws.com/ and kubernetes.io/ are reserved for AWS and Kubernetes."
  }
}
