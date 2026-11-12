# live/stacks/vpc

The first **live-drill stack**: a root module that applies [`modules/vpc`](../../../modules/vpc/) into the real
AWS account for the length of a drill, then gets destroyed. Run it with `/live-drill vpc` (see the repo
README, "Live drills"). Nobody runs `terraform apply` here by hand.

What it creates in `us-east-1`: one VPC `platform-live-vpc` (`10.0.0.0/16`), six subnets (public, private
and isolated in each of 2 AZs), an internet gateway, four route tables (one public with a `0.0.0.0/0` route
to the gateway, one private per AZ, one isolated) with six subnet associations, and the VPC's default
security group emptied of rules. 20 resources in Terraform state.

**Cost: $0.** There is no NAT gateway (modules/vpc has none until M1.2) and no KMS key. VPCs, subnets, route
tables, internet gateways and security groups have no hourly charge.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `region` | `string` | `"us-east-1"` | Region to apply into. The drill role denies all others. |
| `owner` | `string` | `"platform-team"` | Owner tag. No email addresses. |

## Outputs

`region`, `tags`, `vpc_id`, `availability_zones`, `internet_gateway_id`, `public_subnet_ids`,
`private_subnet_ids`, `isolated_subnet_ids`, `public_route_table_id`, `private_route_table_ids`,
`isolated_route_table_id`. `live/evidence.sh` and the console links in `live/screenshots.yml` use them.

## Why it's built this way

- **Empty `backend "s3" {}`.** The workflow passes bucket, key (`live/vpc/terraform.tfstate`), region and
  `use_lockfile = true` with `-backend-config`, so the bucket name (which contains the account ID) is never
  committed. `encrypt` is left unset on purpose so the bucket's default SSE-KMS applies (see
  `live/bootstrap/README.md`).
- **`live-stack = "vpc"` tag** on everything, through `default_tags`. After `terraform destroy` the workflow
  looks the tag up with the Resource Groups Tagging API and fails if anything still carries it.
- **2 AZs, not 3.** A drill proves the module works; the third AZ adds resources to wait for and nothing to
  learn.

## Testing

`tests/unit.tftest.hcl` uses `mock_provider "aws"` with `command = plan`: two AZs with three tiers each, the
`platform`/`live` tags plus `live-stack`, the default region, and that a malformed region is rejected.
modules/vpc has its own unit and Moto tests. The real apply is the drill.
