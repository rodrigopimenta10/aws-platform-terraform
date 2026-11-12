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

output "availability_zones" {
  description = "The two AZs used."
  value       = module.vpc.availability_zones
}

output "internet_gateway_id" {
  description = "ID of the internet gateway."
  value       = module.vpc.internet_gateway_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs, one per AZ."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs, one per AZ."
  value       = module.vpc.private_subnet_ids
}

output "isolated_subnet_ids" {
  description = "Isolated subnet IDs, one per AZ."
  value       = module.vpc.isolated_subnet_ids
}

output "public_route_table_id" {
  description = "ID of the public route table."
  value       = module.vpc.public_route_table_id
}

output "private_route_table_ids" {
  description = "Private route table IDs, one per AZ."
  value       = module.vpc.private_route_table_ids
}

output "isolated_route_table_id" {
  description = "ID of the isolated route table."
  value       = module.vpc.isolated_route_table_id
}
