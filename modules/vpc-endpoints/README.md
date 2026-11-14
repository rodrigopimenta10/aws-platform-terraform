# vpc-endpoints

VPC endpoints let resources in a VPC talk to AWS services over AWS's private network, with no internet
route and no NAT gateway. This module creates:

- an **S3 gateway endpoint** (a route-table entry that sends S3 traffic straight to S3; free), and
- **interface endpoints** for ECR (`ecr.api` and `ecr.dkr`), STS and CloudWatch Logs. An interface endpoint
  is a network interface with a private IP in your subnets, plus a private DNS override so the normal
  hostname (for example `api.ecr.us-east-1.amazonaws.com`) resolves to that IP inside the VPC.

Each interface endpoint gets **its own security group** that allows HTTPS (TCP 443) only from the CIDR blocks
you list. Names and tags come from the [`labels`](../labels/) module.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | n/a (required) | Passed to `labels`. |
| `environment` | `string` | n/a (required) | `dev`, `staging`, `prod` or `live`. |
| `owner` | `string` | n/a (required) | Owner tag value. |
| `vpc_id` | `string` | n/a (required) | VPC to add the endpoints to. |
| `allowed_cidr_blocks` | `list(string)` | n/a (required) | Sources allowed on port 443. Never `0.0.0.0/0`. |
| `subnet_ids` | `list(string)` | n/a (required) | Subnets for the endpoint network interfaces, one per AZ. |
| `route_table_ids` | `list(string)` | `[]` | Route tables that get the S3 gateway route. |
| `enable_s3_gateway_endpoint` | `bool` | `true` | Create the S3 gateway endpoint. |
| `s3_endpoint_policy` | `string` | `null` | Optional JSON policy for the S3 endpoint. |
| `interface_endpoints` | `list(string)` | all four | Any of `ecr_api`, `ecr_dkr`, `sts`, `logs`. |
| `private_dns_enabled` | `bool` | `true` | Resolve the public service hostname to the endpoint inside the VPC. |

## Outputs

| Name | Description |
|------|-------------|
| `s3_gateway_endpoint_id` | S3 gateway endpoint ID, or `null` when disabled. |
| `interface_endpoint_ids` | Map of key (`ecr_api`, ...) to endpoint ID. |
| `interface_endpoint_dns_names` | Map of key to the endpoint's own DNS names. |
| `security_group_ids` | Map of key to security group ID. Add more ingress rules here (for example for EKS nodes). |

## Example

```hcl
module "vpc" {
  source = "../../modules/vpc"
  # ...
}

module "vpc_endpoints" {
  source = "../../modules/vpc-endpoints"

  project     = "platform"
  environment = "dev"
  owner       = "platform-team"

  vpc_id              = module.vpc.vpc_id
  allowed_cidr_blocks = [module.vpc.vpc_cidr_block]
  subnet_ids          = module.vpc.private_subnet_ids
  route_table_ids     = concat(module.vpc.private_route_table_ids, [module.vpc.isolated_route_table_id])
}
```

## Why it's built this way

- **Three things to pull an image, not one.** ECR needs `ecr.api` (login, metadata) and `ecr.dkr` (the
  registry protocol), and the image layers themselves come from S3, so the S3 gateway endpoint is part of the
  set. Leave any out and pulls from a private subnet without NAT time out.
- **Gateway for S3, interface for the rest.** The gateway endpoint costs nothing and has no network
  interface; only S3 and DynamoDB offer one. Everything else needs an interface endpoint.
- **A security group per endpoint.** Scoping reachability per service makes each one auditable and lets you
  later open, say, only `logs` to another network. The groups have no egress rules: an endpoint interface
  never opens connections, and security groups are stateful, so replies need no rule.
- **Never `0.0.0.0/0`.** Endpoints are for traffic from inside the VPC, so a validation blocks the open range.
- **Private DNS on.** SDKs, kubelet and `docker pull` keep using the normal hostnames. This needs DNS support
  and hostnames enabled on the VPC, which [`modules/vpc`](../vpc/) does.
- **Isolated subnets get S3 too.** Pass the isolated route table to `route_table_ids` so databases can reach
  S3 (backups, exports) without any internet route.
- **Why endpoints at all.** Traffic stays on AWS's network (a security gain), and it avoids NAT gateway
  per-GB charges for AWS traffic (see [ADR 0004](../../docs/adr/0004-nat-gateway-strategy.md)).
- **Cost.** About $0.01 per endpoint per AZ-hour in us-east-1 (roughly $7/month each) plus $0.01/GB. Four
  endpoints in 3 AZs is about $87/month before data, so they only pay off when NAT data charges are larger,
  or when you need private-only networking. The S3 gateway endpoint is free. Check the AWS pricing page.

### checkov skips
- `CKV2_AWS_5` (security group not attached): false positive, each group is attached through
  `security_group_ids` on its endpoint, indexed by `each.key`.

## Testing notes
`tests/unit.tftest.hcl` (mock provider, `plan`) checks service names, one security group and rule per endpoint,
subsets, disabling S3, the policy option, and every validation. `tests/integration.tftest.hcl` builds a VPC
with `modules/vpc` on Moto and then applies the endpoints on top: gateway attached to three route tables,
four interface endpoints across two subnets, distinct security groups, and TCP 443 rules from the VPC CIDR.
A security group's own `ingress` and `egress` attributes stay empty when rules are separate resources, so
the tests inspect the rule resources. Moto does not resolve private DNS or route real traffic, so that
part is only proven by the live drill.
