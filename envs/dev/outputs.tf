output "environment" {
  description = "Environment name of this root module."
  value       = "dev"
}

output "region" {
  description = "AWS region the provider is configured for."
  value       = var.region
}

output "prefix" {
  description = "Name prefix \"<project>-dev\"."
  value       = module.labels.prefix
}

output "names" {
  description = "Map of component to full resource name, from the labels module."
  value       = module.labels.names
}

output "tags" {
  description = "Standard tags applied to every resource through the provider's default_tags."
  value       = module.labels.tags
}
