# Read by live/evidence.sh and to fill the console URLs in live/screenshots.yml. IDs of VPC resources are
# not account identifiers, so they may appear in links (never the account ID).

output "region" {
  description = "Region the stack was applied in."
  value       = var.region
}

output "tags" {
  description = "Tags every resource gets through the provider's default_tags, including live-stack."
  value       = module.labels.tags
}

output "vpc_id" {
  description = "ID of the drill VPC."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs, one per AZ (where the interface endpoints live)."
  value       = module.vpc.private_subnet_ids
}

output "s3_gateway_endpoint_id" {
  description = "ID of the S3 gateway endpoint."
  value       = module.vpc_endpoints.s3_gateway_endpoint_id
}

output "sts_endpoint_id" {
  description = "ID of the STS interface endpoint."
  value       = module.vpc_endpoints.interface_endpoint_ids["sts"]
}

output "sts_security_group_id" {
  description = "ID of the STS endpoint's own security group."
  value       = module.vpc_endpoints.security_group_ids["sts"]
}
