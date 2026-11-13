output "role_arn" {
  description = "ARN of the platform-live-drill role. Store it as the AWS_LIVE_ROLE_ARN secret of the aws-live GitHub environment (a secret, so GitHub masks it in public logs)."
  value       = aws_iam_role.drill.arn
}

output "state_bucket_name" {
  description = "Name of the bucket that holds the drill stacks' state (and, after migration, this stack's own). Store it as the AWS_LIVE_STATE_BUCKET secret of the aws-live environment."
  value       = module.state_backend.bucket_name
}

output "region" {
  description = "The drill region. Store it as the AWS_LIVE_REGION repository variable."
  value       = var.region
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider. M2.2 (modules/github-oidc) imports this resource rather than creating a second provider."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "state_kms_key_arn" {
  description = "ARN of the KMS key that encrypts the state bucket by default. The drill backends do not need it: they omit `encrypt`, so the bucket's default SSE-KMS applies."
  value       = module.state_backend.kms_key_arn
}

output "permissions_boundary_arn" {
  description = "Boundary every role created by a drill must carry. The workflow passes it to stacks as TF_VAR_permissions_boundary_arn."
  value       = aws_iam_policy.boundary.arn
}

output "stop_policy_arn" {
  description = "Deny-all policy the guard budget's action attaches to the drill role. Detach it (as an admin) to re-enable drills."
  value       = aws_iam_policy.stop.arn
}
