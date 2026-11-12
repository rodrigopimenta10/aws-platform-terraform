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
