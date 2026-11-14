output "s3_gateway_endpoint_id" {
  description = "ID of the S3 gateway endpoint, or null when it is disabled."
  value       = one(aws_vpc_endpoint.s3[*].id)
}

output "interface_endpoint_ids" {
  description = "Map of endpoint key (ecr_api, ecr_dkr, sts, logs) to VPC endpoint ID."
  value       = { for k, e in aws_vpc_endpoint.interface : k => e.id }
}

output "interface_endpoint_dns_names" {
  description = "Map of endpoint key to the endpoint's own DNS names (they work even when private DNS is off)."
  value       = { for k, e in aws_vpc_endpoint.interface : k => [for d in e.dns_entry : d.dns_name] }
}

output "security_group_ids" {
  description = "Map of endpoint key to its security group ID. Add ingress rules for other sources (for example the EKS node security group) to these."
  value       = { for k, sg in aws_security_group.interface : k => sg.id }
}
