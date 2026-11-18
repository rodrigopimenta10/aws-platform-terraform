output "policy_arn" {
  description = "ARN of the boundary policy. Pass it as `permissions_boundary` to every role (see modules/iam-role)."
  value       = aws_iam_policy.boundary.arn
}

output "policy_name" {
  description = "Name of the boundary policy, <project>-<environment>-boundary."
  value       = aws_iam_policy.boundary.name
}
