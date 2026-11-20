# Read by live/evidence.sh and to fill the console URLs in live/screenshots.yml.

output "region" {
  description = "Region the stack was applied in."
  value       = var.region
}

output "tags" {
  description = "Tags every resource gets through the provider's default_tags, including live-stack."
  value       = module.labels.tags
}

output "kms_key_id" {
  description = "ID of the drill KMS key that encrypts the repositories."
  value       = module.kms_ecr.key_id
}

output "ecr_api_repository_name" {
  description = "Name of the api repository."
  value       = module.ecr.repository_names["api"]
}

output "ecr_worker_repository_name" {
  description = "Name of the worker repository."
  value       = module.ecr.repository_names["worker"]
}
