output "provider_arn" {
  description = "ARN of the GitHub OIDC provider the role trusts, whether this module created it or it already existed."
  value       = local.provider_arn
}

output "role_arn" {
  description = "ARN of the deploy role. A workflow passes it as `role-to-assume` to aws-actions/configure-aws-credentials."
  value       = aws_iam_role.deploy.arn
}

output "role_name" {
  description = "Name of the deploy role, <project>-<environment>-github-deploy."
  value       = aws_iam_role.deploy.name
}

output "allowed_subjects" {
  description = "The exact token subjects the trust policy accepts. Useful to check against what GitHub actually sends."
  value       = local.subjects
}
