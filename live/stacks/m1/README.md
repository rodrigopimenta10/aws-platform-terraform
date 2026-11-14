# live/stacks/m1

The **milestone 1 live-drill stack**: applies [`modules/vpc`](../../../modules/vpc/) and
[`modules/vpc-endpoints`](../../../modules/vpc-endpoints/) into the real AWS account for the length of a drill,
then gets destroyed. Run it with `/live-drill m1`. Nobody runs `terraform apply` here by hand. Later M1 items
add to this stack. The smaller [`vpc`](../vpc/) stack stays as the cheapest check of the VPC alone.

What it creates in `us-east-1`: the 20 VPC resources from the `vpc` stack, plus an S3 gateway endpoint
attached to three route tables, and four interface endpoints (ECR api, ECR dkr, STS, CloudWatch Logs), each in
both private subnets and each with its own security group that allows only TCP 443 from the VPC CIDR.

**Cost:** the VPC and the S3 gateway endpoint are free. Interface endpoints bill about $0.01 per endpoint per
AZ-hour: 4 endpoints x 2 AZs = about $0.08 an hour, so a drill that lasts a few minutes costs a few cents.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `region` | `string` | `"us-east-1"` | Region to apply into. The drill role denies all others. |
| `owner` | `string` | `"platform-team"` | Owner tag. No email addresses. |

## Outputs

`region`, `tags`, `vpc_id`, `private_subnet_ids`, `s3_gateway_endpoint_id`, `sts_endpoint_id`,
`sts_security_group_id`. The console links in `live/screenshots.yml` use them.

## Why it's built this way

- **Endpoints in both private subnets.** `live/plan-gate.sh` refuses an interface endpoint in more than 2 AZs.
- **No NAT gateway.** The point of the endpoints is that private subnets reach ECR, STS, Logs and S3 without one.
- **`live-stack = "m1"` tag** on everything, so the workflow can check after destroy that nothing is left.

## Testing

`tests/unit.tftest.hcl` uses `mock_provider "aws"` with `command = plan`: four endpoints in two private
subnets, the `platform`/`live` tags plus `live-stack = m1`, and that a malformed region is rejected. The real
apply is the drill.
