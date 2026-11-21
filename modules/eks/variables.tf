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
  description = "Component name; the cluster is called <project>-<environment>-<name>. Lowercase letters, digits and hyphens."
  type        = string
  default     = "eks"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,19}$", var.name))
    error_message = "name must be 1-20 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes minor version of the control plane, for example 1.33. Pinned on purpose: AWS upgrades the control plane only when this value changes, and never skips a minor version."
  type        = string
  default     = "1.33"

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must be a minor version such as 1.33 (no patch number)."
  }
}

variable "subnet_ids" {
  description = "Subnets for the control plane's network interfaces, in at least two availability zones. Use the private subnets (modules/vpc output eks_subnet_ids)."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2 && alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", s))])
    error_message = "subnet_ids must hold at least two subnet IDs (subnet-...), in different availability zones."
  }
}

variable "additional_security_group_ids" {
  description = "Extra security groups attached to the control plane's network interfaces. EKS always creates and attaches its own cluster security group as well."
  type        = list(string)
  default     = []
}

variable "service_ipv4_cidr" {
  description = "CIDR block Kubernetes assigns Service (ClusterIP) addresses from. It must not overlap the VPC. Null lets EKS pick 10.100.0.0/16 or 172.20.0.0/16."
  type        = string
  default     = null

  validation {
    condition     = var.service_ipv4_cidr == null || can(cidrhost(coalesce(var.service_ipv4_cidr, "10.0.0.0/8"), 0))
    error_message = "service_ipv4_cidr must be a valid IPv4 CIDR block."
  }
}

variable "endpoint_public_access" {
  description = "Whether the API server is also reachable from the internet. Off by default: the endpoint is then reachable only from inside the VPC (and networks connected to it)."
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public endpoint. Only used when endpoint_public_access is true, and then required: 0.0.0.0/0 is rejected, because an open Kubernetes API is the usual first thing an attacker probes."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.public_access_cidrs : can(cidrhost(c, 0))])
    error_message = "public_access_cidrs must be valid IPv4 CIDR blocks."
  }

  validation {
    condition     = !contains(var.public_access_cidrs, "0.0.0.0/0")
    error_message = "public_access_cidrs must not contain 0.0.0.0/0. List the specific networks that need the API."
  }
}

variable "kms_key_arn" {
  description = "ARN of the customer-managed KMS key for envelope encryption of Kubernetes Secrets in etcd (see modules/kms). The key and the cluster must be in the same region."
  type        = string

  validation {
    condition     = can(regex("^arn:[a-z-]+:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias."
  }
}

variable "logs_kms_key_arn" {
  description = "ARN of the KMS key that encrypts the control-plane log group. Its key policy must let the CloudWatch Logs service use it (modules/kms service_grants). It may be the same key as kms_key_arn."
  type        = string

  validation {
    condition     = can(regex("^arn:[a-z-]+:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.logs_kms_key_arn))
    error_message = "logs_kms_key_arn must be a KMS key ARN, not an alias."
  }
}

variable "enabled_log_types" {
  description = "Control-plane log types sent to CloudWatch Logs. All five by default: api, audit, authenticator, controllerManager, scheduler. The audit log is what answers who did what to the cluster."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  validation {
    condition     = alltrue([for t in var.enabled_log_types : contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)])
    error_message = "enabled_log_types may only contain api, audit, authenticator, controllerManager and scheduler."
  }

  validation {
    condition     = contains(var.enabled_log_types, "audit")
    error_message = "enabled_log_types must include audit: without it nobody can tell who changed the cluster."
  }
}

variable "log_retention_days" {
  description = "Days control-plane logs are kept in CloudWatch Logs (default one year, which security baselines such as checkov CKV_AWS_338 expect). Must be a retention value CloudWatch accepts."
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts (for example 30, 90, 365)."
  }
}

variable "permissions_boundary" {
  description = "ARN of the IAM permissions boundary for the cluster role (modules/iam-boundary output policy_arn). Required in practice: the role module fails its precondition when this is null."
  type        = string
  default     = null
}

variable "access_entries" {
  description = "Who may use the Kubernetes API, keyed by a short name. Each entry maps an IAM role or user (principal_arn) to one EKS access policy (policy_arn, for example arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy). With no namespaces the policy applies cluster-wide; with namespaces it is limited to them."
  type = map(object({
    principal_arn = string
    policy_arn    = string
    namespaces    = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.access_entries) : can(regex("^[A-Za-z0-9-]{1,40}$", k))])
    error_message = "access_entries keys may contain only letters, digits and hyphens (max 40)."
  }

  validation {
    condition     = alltrue([for e in values(var.access_entries) : can(regex("^arn:[a-z-]+:eks::(aws|[0-9]{12}):cluster-access-policy/.+$", e.policy_arn))])
    error_message = "policy_arn must be an EKS access policy ARN such as arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy."
  }

  validation {
    condition     = alltrue([for e in values(var.access_entries) : can(regex("^arn:[a-z-]+:iam::[0-9]{12}:(role|user)/.+$", e.principal_arn))])
    error_message = "principal_arn must be an IAM role or user ARN."
  }
}
