# A three-tier VPC (Virtual Private Cloud: your own isolated network inside AWS).
#
# Address plan. The VPC CIDR is first cut into four equal "tier blocks" with cidrsubnet(cidr, 2, n):
#   block 0 = private, block 1 = public, block 2 = isolated, block 3 = spare for a future tier.
# Each tier block is then cut into one subnet per availability zone (AZ). Because every tier lives in its
# own block, subnets of different tiers can never overlap, whatever the *_newbits variables are.

module "labels" {
  source = "../labels"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  components  = ["vpc"]
}

# Only AZs that are open for use (not "impaired" or opt-in local zones).
data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394:We deliberately take the first az_count zones by name. Names sort alphabetically and AWS appends new zones, so existing subnets keep their AZ; callers needing fixed zones should not rely on this default.
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  name = module.labels.names["vpc"]
  azs  = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  tier_blocks = {
    private  = cidrsubnet(var.vpc_cidr, 2, 0)
    public   = cidrsubnet(var.vpc_cidr, 2, 1)
    isolated = cidrsubnet(var.vpc_cidr, 2, 2)
  }

  tier_newbits = {
    private  = var.private_subnet_newbits
    public   = var.public_subnet_newbits
    isolated = var.isolated_subnet_newbits
  }

  # One CIDR per AZ for each tier, in AZ order: { private = ["10.0.0.0/20", ...], ... }
  subnet_cidrs = {
    for tier, block in local.tier_blocks :
    tier => [for i in range(var.az_count) : cidrsubnet(block, local.tier_newbits[tier], i)]
  }

  # Tags that let EKS and the AWS Load Balancer Controller find the right subnets.
  cluster_tags = { for n in var.eks_cluster_names : "kubernetes.io/cluster/${n}" => "shared" }

  # NAT strategy (ADR 0004). One NAT gateway in total, or one per AZ. nat_count is 0 when NAT is off.
  nat_count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : var.az_count) : 0

  tier_tags = {
    public   = merge(local.cluster_tags, { "kubernetes.io/role/elb" = "1" })
    private  = merge(local.cluster_tags, { "kubernetes.io/role/internal-elb" = "1" })
    isolated = {}
  }
}

resource "aws_vpc" "this" {
  #checkov:skip=CKV2_AWS_11:Flow logs are a separate roadmap item (M1.4) that attaches to this VPC from its own module.
  cidr_block = var.vpc_cidr

  # Both are required for EKS nodes to resolve the API endpoint and for interface VPC endpoints (M1.3).
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = local.name }

  lifecycle {
    # A subnet needs at least 16 addresses (a /28). Catch an oversized newbits value at plan time
    # instead of with a cryptic API error during apply.
    precondition {
      condition = alltrue([
        for tier, bits in local.tier_newbits :
        tonumber(split("/", var.vpc_cidr)[1]) + 2 + bits <= 28
      ])
      error_message = "A subnet_newbits value makes subnets smaller than a /28 (the AWS minimum). Lower the *_subnet_newbits values or use a larger vpc_cidr."
    }
  }
}

# The default security group allows all traffic between its members. Adopting it with no rules empties it,
# so nothing can use it by accident. Real workloads get their own security groups.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name}-default-unused" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = local.name }
}

resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = local.subnet_cidrs.public[count.index]

  # Resources placed here must ask for a public IP explicitly. Load balancers and NAT gateways do.
  map_public_ip_on_launch = false

  tags = merge(local.tier_tags.public, {
    Name = "${local.name}-public-${local.azs[count.index]}"
    tier = "public"
  })
}

resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = local.subnet_cidrs.private[count.index]

  map_public_ip_on_launch = false

  tags = merge(local.tier_tags.private, {
    Name = "${local.name}-private-${local.azs[count.index]}"
    tier = "private"
  })
}

resource "aws_subnet" "isolated" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = local.subnet_cidrs.isolated[count.index]

  map_public_ip_on_launch = false

  tags = merge(local.tier_tags.isolated, {
    Name = "${local.name}-isolated-${local.azs[count.index]}"
    tier = "isolated"
  })
}

# Public: one shared route table whose default route goes to the internet gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name}-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = var.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private: one route table PER AZ. The default route to NAT is added below. Per-AZ tables let the NAT strategy
# (roadmap M1.2) point each AZ at its own NAT gateway, or all of them at one, without restructuring.
resource "aws_route_table" "private" {
  count = var.az_count

  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name}-private-${local.azs[count.index]}" }
}

# NAT (Network Address Translation) gateway: lets private subnets start connections to the internet
# (package downloads, AWS APIs) without being reachable from it. It must sit in a PUBLIC subnet and needs
# an Elastic IP (a fixed public address). It costs money for every hour it exists, see ADR 0004.
resource "aws_eip" "nat" {
  count = local.nat_count

  domain = "vpc"

  tags = { Name = "${local.name}-nat-${local.azs[count.index]}" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.nat_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = { Name = "${local.name}-${local.azs[count.index]}" }

  # The NAT gateway needs the internet gateway in place to reach the internet.
  depends_on = [aws_internet_gateway.this]
}

# Each private route table sends internet-bound traffic to a NAT gateway. With one NAT everything shares
# index 0. With one per AZ, AZ i uses NAT i, so an AZ outage cannot cut off the other AZs' egress.
resource "aws_route" "private_nat" {
  count = var.enable_nat_gateway ? var.az_count : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
}

resource "aws_route_table_association" "private" {
  count = var.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Isolated: one route table with only the implicit local route (traffic inside the VPC). No way out.
resource "aws_route_table" "isolated" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name}-isolated" }
}

resource "aws_route_table_association" "isolated" {
  count = var.az_count

  subnet_id      = aws_subnet.isolated[count.index].id
  route_table_id = aws_route_table.isolated.id
}
