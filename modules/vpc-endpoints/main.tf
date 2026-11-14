# VPC endpoints: private doorways from the VPC to AWS services, so traffic never leaves the AWS network
# and never needs a NAT gateway or an internet route.
#
# Two kinds:
#   gateway   (S3, DynamoDB only) a route-table entry pointing at the service. Free, no network interface.
#   interface (most services)     an elastic network interface (ENI) with a private IP in your subnets,
#                                 plus a private DNS name override so the normal service hostname resolves to it.
#                                 Billed per endpoint per AZ-hour plus per GB.

data "aws_region" "current" {}

locals {
  region = data.aws_region.current.region

  # Short key -> AWS service name suffix. Pulling an image from ECR needs three endpoints, not one:
  # ecr.api (login, image metadata), ecr.dkr (the Docker registry protocol) and the S3 gateway endpoint
  # (the image layers themselves are stored in S3).
  interface_services = {
    ecr_api = "ecr.api"
    ecr_dkr = "ecr.dkr"
    sts     = "sts"
    logs    = "logs"
  }

  interface_endpoints = toset(var.interface_endpoints)
}

module "labels" {
  source = "../labels"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  # Hyphens, not underscores: labels components are lowercase letters, digits and hyphens.
  components = concat(["s3-vpce"], [for k in local.interface_endpoints : "${replace(k, "_", "-")}-vpce"])
}

# ---- S3 gateway endpoint ------------------------------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_gateway_endpoint ? 1 : 0

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  # null means the default policy (full access through the endpoint). IAM and bucket policies still apply.
  policy = var.s3_endpoint_policy

  tags = { Name = module.labels.names["s3-vpce"] }
}

# ---- Interface endpoints, each with its own security group ---------------------------------------------

# One security group per endpoint, so each service's reachability can be narrowed or audited on its own.
resource "aws_security_group" "interface" {
  #checkov:skip=CKV2_AWS_5:False positive. Each group is attached to its interface endpoint through security_group_ids = [aws_security_group.interface[each.key].id]; checkov cannot follow the for_each index.
  for_each = local.interface_endpoints

  name        = module.labels.names["${replace(each.key, "_", "-")}-vpce"]
  description = "HTTPS to the ${local.interface_services[each.key]} interface endpoint"
  vpc_id      = var.vpc_id

  tags = { Name = module.labels.names["${replace(each.key, "_", "-")}-vpce"] }

  lifecycle {
    # A new security group must exist before the endpoint stops using the old one.
    create_before_destroy = true
  }
}

# Clients talk to the endpoint over HTTPS only. A security group is stateful, so replies are allowed back
# without an egress rule, and an endpoint network interface never starts connections. The group has no
# egress rules at all (Terraform removes AWS's default allow-all egress when it creates the group).
resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each = { for pair in setproduct(local.interface_endpoints, var.allowed_cidr_blocks) : "${pair[0]}|${pair[1]}" => pair }

  security_group_id = aws_security_group.interface[each.value[0]].id
  description       = "HTTPS from ${each.value[1]}"
  cidr_ipv4         = each.value[1]
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${local.region}.${local.interface_services[each.key]}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.interface[each.key].id]
  private_dns_enabled = var.private_dns_enabled

  tags = { Name = module.labels.names["${replace(each.key, "_", "-")}-vpce"] }
}
