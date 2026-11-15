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

output "vpc_id" {
  description = "ID of the dev VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR block of the dev VPC."
  value       = module.vpc.vpc_cidr_block
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

output "private_route_table_ids" {
  description = "Private route table IDs, one per AZ."
  value       = module.vpc.private_route_table_ids
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs (one when single_nat_gateway is true)."
  value       = module.vpc.nat_gateway_ids
}

output "flow_log_group_name" {
  description = "CloudWatch log group receiving the VPC flow logs."
  value       = module.vpc_flow_logs.log_group_name
}
