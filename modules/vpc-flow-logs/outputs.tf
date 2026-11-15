output "flow_log_id" {
  description = "ID of the VPC flow log."
  value       = aws_flow_log.this.id
}

output "log_group_name" {
  description = "Name of the CloudWatch log group that receives the flow log records."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group."
  value       = aws_cloudwatch_log_group.this.arn
}

output "kms_key_arn" {
  description = "ARN of the customer-managed KMS key that encrypts the log group."
  value       = aws_kms_key.this.arn
}

output "iam_role_arn" {
  description = "ARN of the IAM role the flow logs service assumes to write to the log group."
  value       = aws_iam_role.this.arn
}
