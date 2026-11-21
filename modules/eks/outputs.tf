output "cluster_name" {
  description = "Name of the cluster, <project>-<environment>-<name>."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the cluster."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "URL of the Kubernetes API server. Resolves to private addresses unless endpoint_public_access is true."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority that signed the API server's certificate. Clients (kubectl, Helm) need it to trust the endpoint."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_version" {
  description = "Kubernetes version the control plane runs."
  value       = aws_eks_cluster.this.version
}

output "cluster_security_group_id" {
  description = "ID of the security group EKS created for the cluster. Node groups and add-ons use it to talk to the control plane."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_issuer_url" {
  description = "The cluster's OIDC issuer URL. Used later to trust Kubernetes service accounts from IAM (IRSA)."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "cluster_role_arn" {
  description = "ARN of the IAM role the EKS service assumes for the control plane."
  value       = module.cluster_role.role_arn
}

output "log_group_name" {
  description = "CloudWatch log group that receives the control-plane logs."
  value       = aws_cloudwatch_log_group.cluster.name
}
