output "node_role_arn" {
  description = "ARN of the IAM role every node uses."
  value       = module.node_role.role_arn
}

output "node_role_name" {
  description = "Name of the node role, <project>-<environment>-<name>-role."
  value       = module.node_role.role_name
}

output "node_group_names" {
  description = "Map of group key to EKS node group name, <project>-<environment>-<name>-<key>."
  value       = { for k, g in aws_eks_node_group.this : k => g.node_group_name }
}

output "node_group_arns" {
  description = "Map of group key to node group ARN."
  value       = { for k, g in aws_eks_node_group.this : k => g.arn }
}

output "node_group_statuses" {
  description = "Map of group key to status (ACTIVE once the nodes have joined)."
  value       = { for k, g in aws_eks_node_group.this : k => g.status }
}

output "launch_template_ids" {
  description = "Map of group key to launch template ID."
  value       = { for k, t in aws_launch_template.this : k => t.id }
}
