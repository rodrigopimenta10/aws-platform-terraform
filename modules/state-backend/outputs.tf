output "bucket_name" {
  description = "Name of the S3 bucket that holds Terraform state. Use it as `bucket` in a backend block."
  value       = aws_s3_bucket.state.id
}

output "bucket_arn" {
  description = "ARN of the state bucket, for IAM policies that grant a role access to state."
  value       = aws_s3_bucket.state.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key that encrypts state. Roles that read or write state need kms:Decrypt, kms:GenerateDataKey on it."
  value       = aws_kms_key.state.arn
}

output "kms_alias_name" {
  description = "Alias of the KMS key (alias/<prefix>-tfstate)."
  value       = aws_kms_alias.state.name
}

output "backend_config" {
  description = "Ready-to-paste backend settings (bucket, region, encrypt, kms_key_id, use_lockfile). The `key` (state file path) is chosen by each root module."
  value = {
    bucket       = aws_s3_bucket.state.id
    region       = data.aws_region.current.region
    encrypt      = true
    kms_key_id   = aws_kms_key.state.arn
    use_lockfile = true
  }
}

output "tags" {
  description = "Standard tag map from the labels module, for callers that want to reuse it."
  value       = module.labels.tags
}
