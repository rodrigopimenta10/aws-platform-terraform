output "repository_urls" {
  description = "Map of repository key to its URL (<account>.dkr.ecr.<region>.amazonaws.com/<name>), what docker push and a Kubernetes image field use."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_arns" {
  description = "Map of repository key to its ARN, for IAM policies that grant pull or push."
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}

output "repository_names" {
  description = "Map of repository key to the full repository name <project>-<environment>-<key>."
  value       = { for k, r in aws_ecr_repository.this : k => r.name }
}
