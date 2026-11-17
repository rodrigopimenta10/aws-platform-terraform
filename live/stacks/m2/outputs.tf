# Read by live/evidence.sh and to fill the console URLs in live/screenshots.yml. Key IDs are not account
# identifiers, so they may appear in links (never the account ID).

output "region" {
  description = "Region the stack was applied in."
  value       = var.region
}

output "tags" {
  description = "Tags every resource gets through the provider's default_tags, including live-stack."
  value       = module.labels.tags
}

output "kms_key_id" {
  description = "ID of the drill KMS key."
  value       = module.kms_logs.key_id
}

output "kms_alias_name" {
  description = "Alias of the drill KMS key."
  value       = module.kms_logs.alias_name
}

output "log_group_name" {
  description = "Name of the log group encrypted with the key."
  value       = aws_cloudwatch_log_group.app.name
}

output "github_role_name" {
  description = "Name of the GitHub OIDC deploy role."
  value       = module.github_oidc.role_name
}

output "github_role_arn" {
  description = "ARN of the GitHub OIDC deploy role."
  value       = module.github_oidc.role_arn
}
