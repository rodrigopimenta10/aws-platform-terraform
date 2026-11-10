output "prefix" {
  description = "Name prefix \"<project>-<environment>\". Append a component to build a resource name."
  value       = local.prefix
}

output "names" {
  description = "Map of component name to full resource name (\"<project>-<environment>-<component>\"), one entry per item in `components`."
  value       = local.names
}

output "tags" {
  description = "Standard tag map (project, environment, owner, managed-by) plus extra_tags. Pass to a resource's `tags`, or to the provider's `default_tags`."
  value       = local.tags
}
