output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_arn" {
  description = "ARN of the VPC."
  value       = aws_vpc.this.arn
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "availability_zones" {
  description = "Availability zones used, in the same order as every per-AZ list output."
  value       = local.azs
}

output "internet_gateway_id" {
  description = "ID of the internet gateway attached to the VPC."
  value       = aws_internet_gateway.this.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs, one per AZ. Use for internet-facing load balancers and NAT gateways. Tagged kubernetes.io/role/elb."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs, one per AZ. Use for EKS nodes and internal load balancers. Tagged kubernetes.io/role/internal-elb."
  value       = aws_subnet.private[*].id
}

output "isolated_subnet_ids" {
  description = "Isolated subnet IDs, one per AZ. Use for databases. No route to the internet."
  value       = aws_subnet.isolated[*].id
}

output "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets, in AZ order."
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets, in AZ order."
  value       = aws_subnet.private[*].cidr_block
}

output "isolated_subnet_cidrs" {
  description = "CIDR blocks of the isolated subnets, in AZ order."
  value       = aws_subnet.isolated[*].cidr_block
}

output "public_route_table_id" {
  description = "ID of the single route table shared by all public subnets."
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "Private route table IDs, one per AZ (same order as private_subnet_ids). M1.2 adds NAT routes to these."
  value       = aws_route_table.private[*].id
}

output "isolated_route_table_id" {
  description = "ID of the single route table shared by all isolated subnets."
  value       = aws_route_table.isolated.id
}

output "eks_subnet_ids" {
  description = "Ready-made input for an EKS cluster: private subnets for nodes and the control-plane network interfaces (the API endpoint itself is configured on the cluster)."
  value       = aws_subnet.private[*].id
}
