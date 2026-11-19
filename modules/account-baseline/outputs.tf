output "ebs_encryption_by_default_enabled" {
  description = "Whether new EBS volumes in this region are encrypted by default."
  value       = aws_ebs_encryption_by_default.this.enabled
}

output "ebs_default_kms_key_arn" {
  description = "KMS key that encrypts new EBS volumes by default, or null when the AWS-managed aws/ebs key is used."
  value       = one(aws_ebs_default_kms_key.this[*].key_arn)
}

output "s3_public_access_blocked" {
  description = "True when all four account-level S3 Block Public Access settings are on."
  value = alltrue([
    aws_s3_account_public_access_block.this.block_public_acls,
    aws_s3_account_public_access_block.this.block_public_policy,
    aws_s3_account_public_access_block.this.ignore_public_acls,
    aws_s3_account_public_access_block.this.restrict_public_buckets,
  ])
}

output "password_minimum_length" {
  description = "Minimum IAM password length enforced in the account."
  value       = aws_iam_account_password_policy.this.minimum_password_length
}
