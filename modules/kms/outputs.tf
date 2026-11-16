output "key_id" {
  description = "ID of the key."
  value       = aws_kms_key.this.key_id
}

output "key_arn" {
  description = "ARN of the key. Pass this to a resource's kms_key_id argument."
  value       = aws_kms_key.this.arn
}

output "alias_name" {
  description = "Alias of the key, alias/<project>-<environment>-<purpose>."
  value       = aws_kms_alias.this.name
}

output "alias_arn" {
  description = "ARN of the alias."
  value       = aws_kms_alias.this.arn
}
