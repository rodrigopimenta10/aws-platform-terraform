output "role_arn" {
  description = "ARN of the role."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the role, <project>-<environment>-<name>."
  value       = aws_iam_role.this.name
}

output "permissions_boundary" {
  description = "ARN of the boundary the role carries."
  value       = aws_iam_role.this.permissions_boundary
}
