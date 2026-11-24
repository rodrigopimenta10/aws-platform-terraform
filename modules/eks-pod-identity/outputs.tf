output "role_arn" {
  description = "ARN of the workload's IAM role."
  value       = module.role.role_arn
}

output "role_name" {
  description = "Name of the role, <project>-<environment>-<name>. Attach further policies to it by name."
  value       = module.role.role_name
}

output "association_arn" {
  description = "ARN of the Pod Identity association."
  value       = aws_eks_pod_identity_association.this.association_arn
}

output "association_id" {
  description = "ID of the Pod Identity association."
  value       = aws_eks_pod_identity_association.this.association_id
}

output "trust_policy" {
  description = "The role's trust policy (JSON): only pods.eks.amazonaws.com, for this account and cluster."
  value       = local.trust_policy
}
