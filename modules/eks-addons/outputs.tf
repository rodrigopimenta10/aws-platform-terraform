output "addon_arns" {
  description = "Map of add-on name to the add-on's ARN."
  value       = { for k, a in aws_eks_addon.this : k => a.arn }
}

output "addon_versions" {
  description = "Map of add-on name to the version that is pinned and installed."
  value       = { for k, a in aws_eks_addon.this : k => a.addon_version }
}

output "ebs_csi_role_arn" {
  description = "ARN of the role the module created for the EBS CSI driver, or null when the driver is not installed or brings its own role."
  value       = local.create_ebs_csi_role ? module.ebs_csi_role[0].role_arn : null
}
