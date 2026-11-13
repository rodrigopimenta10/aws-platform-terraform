# vpc

A VPC (Virtual Private Cloud, your own isolated network inside AWS) with three subnet tiers spread over
two or three availability zones (AZs, separate data centers in one region). Names and tags come from the
[`labels`](../labels/) module. Subnet sizes are set by variables and computed with `cidrsubnet`.

| Tier | Route to internet | Use it for |
|------|-------------------|------------|
| **public** | Direct, through an internet gateway | Internet-facing load balancers, NAT gateways |
| **private** | Outbound only, through a NAT gateway (optional) | EKS nodes, application workloads |
| **isolated** | Never | Databases and anything that must not reach out |

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | n/a (required) | Passed to `labels`. |
| `environment` | `string` | n/a (required) | `dev`, `staging`, `prod` or `live`. |
| `owner` | `string` | n/a (required) | Owner tag value. |
| `vpc_cidr` | `string` | `"10.0.0.0/16"` | VPC range, written in network form, `/16` to `/22`. |
| `az_count` | `number` | `3` | `2` or `3` AZs. |
| `private_subnet_newbits` | `number` | `2` | Bits added to the tier block to size private subnets (`/16` VPC gives `/20`). |
| `public_subnet_newbits` | `number` | `4` | Same for public subnets (`/22`). |
| `isolated_subnet_newbits` | `number` | `4` | Same for isolated subnets (`/22`). |
| `enable_nat_gateway` | `bool` | `true` | Create NAT gateways for private-subnet egress. `false` leaves the private tier with no internet route. |
| `single_nat_gateway` | `bool` | `false` | `true`: one shared NAT gateway. `false`: one per AZ. Ignored when NAT is off. See [ADR 0004](../../docs/adr/0004-nat-gateway-strategy.md). |
| `eks_cluster_names` | `set(string)` | `[]` | Clusters that get the `kubernetes.io/cluster/<name>=shared` tag on every subnet. |

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id`, `vpc_arn`, `vpc_cidr_block` | The VPC. |
| `availability_zones` | AZs used. Every per-AZ list below follows this order. |
| `internet_gateway_id` | The internet gateway. |
| `public_subnet_ids`, `private_subnet_ids`, `isolated_subnet_ids` | Subnet IDs, one per AZ. |
| `public_subnet_cidrs`, `private_subnet_cidrs`, `isolated_subnet_cidrs` | Subnet CIDR blocks. |
| `public_route_table_id`, `isolated_route_table_id` | The shared route tables. |
| `private_route_table_ids` | One route table per AZ. |
| `nat_gateway_ids` | NAT gateway IDs (one per AZ, one in single mode, none when disabled). |
| `nat_public_ips` | Elastic IPs of the NAT gateways, for partners that allow-list your egress. |
| `eks_subnet_ids` | The private subnets, ready to hand to an EKS cluster (M3.2). |

## Example

```hcl
module "vpc" {
  source = "../../modules/vpc"

  project           = "platform"
  environment       = "dev"
  owner             = "platform-team"
  vpc_cidr          = "10.20.0.0/16"
  eks_cluster_names = ["platform-dev"]
}
```

With the defaults and a `/16` the address plan is:

| Tier | Tier block | Subnets (AZ a, b, c) |
|------|-----------|----------------------|
| private | `10.0.0.0/18` | `10.0.0.0/20`, `10.0.16.0/20`, `10.0.32.0/20` |
| public | `10.0.64.0/18` | `10.0.64.0/22`, `10.0.68.0/22`, `10.0.72.0/22` |
| isolated | `10.0.128.0/18` | `10.0.128.0/22`, `10.0.132.0/22`, `10.0.136.0/22` |
| spare | `10.0.192.0/18` | unused, kept for a future tier |

### Choosing a NAT strategy

| Setting | NAT gateways | Rough cost (us-east-1, 3 AZs) | If one AZ fails |
|---------|--------------|-------------------------------|-----------------|
| default (`single_nat_gateway = false`) | 3 | about $110/month plus data | Other AZs keep their egress |
| `single_nat_gateway = true` | 1 | about $37/month plus data | Egress stops everywhere if the NAT's AZ is the one that fails |
| `enable_nat_gateway = false` | 0 | $0 | Private subnets have no egress at all |

Use `single_nat_gateway = true` for dev. Prices are approximate, check the AWS pricing page.

## Why it's built this way

- **Tier blocks first, subnets second.** `cidrsubnet(vpc_cidr, 2, n)` cuts the VPC into four blocks and each
  tier's subnets are carved only from its own block. Different `*_newbits` values can therefore never make
  subnets of different tiers overlap, and growth room stays inside each tier.
- **Private subnets are the largest.** On EKS every pod gets a VPC IP address, so nodes and pods eat
  addresses fast. Public subnets only hold load balancers and NAT gateways.
- **Three tiers, not two.** Isolated subnets have no internet route at all, not even through NAT, so a
  compromised database host cannot call out. That is a stronger statement than a security group alone.
- **One private route table per AZ.** The NAT strategy (one shared gateway or one per AZ) is just a different
  route target in each table, so switching modes changes routes, not the route tables.
- **NAT per AZ by default.** Production-style: an AZ outage should not cut off other AZs. Cheap
  single-NAT mode is one variable away. Reasoning and numbers are in ADR 0004.
- **Default security group emptied.** `aws_default_security_group` with no rules removes the permissive
  default, so nothing is accidentally "allowed" by being left in it.
- **No auto-assigned public IPs**, even in public subnets. Things that need one ask for it.
- **EKS tags up front.** `kubernetes.io/role/elb` on public and `kubernetes.io/role/internal-elb` on private
  subnets let the AWS Load Balancer Controller pick subnets automatically. The cluster tag is optional.
- **DNS support and hostnames on**, needed by EKS and by interface VPC endpoints (M1.3).
- **Cost:** a VPC, subnets, route tables and an internet gateway are free. NAT gateways are not: each bills
  every hour it exists plus per GB processed, so the live-drill stack turns them off.

### checkov skips
- `CKV2_AWS_11` (flow logs): added by roadmap item M1.4 in its own module.
- `CKV_AWS_394` (AZ data source pinning): deliberately takes the first `az_count` zones, see the comment in `main.tf`.

## Testing notes
`tests/unit.tftest.hcl` (mock provider, `plan`) checks the address plan, routing, tags, and every
validation rule. `tests/integration.tftest.hcl` applies against Moto and checks subnets, route tables, tags
and the emptied default security group. The default security group's rule sets are only known after apply,
so that check lives in the integration test. Moto's AZ list is not the real one, which is fine because the
module never hard-codes zone names.
