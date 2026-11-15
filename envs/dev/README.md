# envs/dev

The **root module** for the `dev` environment. A root module is the folder you run `terraform init/plan/apply`
in. Reusable modules live in `modules/`; a root module wires them to a provider (which region and account to talk
to) and to a state backend (where Terraform remembers what it created). It calls
[`labels`](../../modules/labels/), configures the AWS provider and builds the milestone 1 network:
[`vpc`](../../modules/vpc/), [`vpc-endpoints`](../../modules/vpc-endpoints/) and
[`vpc-flow-logs`](../../modules/vpc-flow-logs/). **Applying it in a real account costs money**: the shared NAT
gateway bills about $0.045 an hour (plus data), and the four interface endpoints in three AZs about
$0.12 an hour. See [ADR 0004](../../docs/adr/0004-nat-gateway-strategy.md). Later roadmap items add EKS and more.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | `"platform"` | Project name, first segment of every resource name. Validated by `labels`. |
| `owner` | `string` | `"platform-team"` | Team or person responsible. No email addresses. |
| `region` | `string` | `"us-east-1"` | AWS region. Must look like `us-east-1`. |
| `components` | `set(string)` | `["vpc", "tfstate"]` | Components to build full names for. |
| `vpc_cidr` | `string` | `"10.0.0.0/16"` | VPC address range. Validated by `modules/vpc`. |
| `az_count` | `number` | `3` | Availability zones to use, 2 or 3. |
| `single_nat_gateway` | `bool` | `true` | One shared NAT gateway (cheap) or one per AZ (highly available). |
| `flow_log_retention_in_days` | `number` | `365` | Days CloudWatch keeps flow log records. |

## Outputs

| Name | Description |
|------|-------------|
| `environment` | Always `dev`. |
| `region` | Region the provider uses. |
| `prefix` | `<project>-dev`, for example `platform-dev`. |
| `names` | Map of component to full resource name. |
| `tags` | Standard tags, also applied through the provider's `default_tags`. |
| `vpc_id`, `vpc_cidr_block` | The dev VPC. |
| `public_subnet_ids`, `private_subnet_ids`, `isolated_subnet_ids` | Subnet IDs, one per AZ per tier. |
| `private_route_table_ids` | One private route table per AZ. |
| `nat_gateway_ids` | NAT gateway IDs (one by default). |
| `flow_log_group_name` | CloudWatch log group receiving the flow logs. |

## Example

```bash
cd envs/dev
terraform init
terraform plan -var owner=my-team
```

(Planning needs AWS credentials, because the VPC module looks up availability zones. This repo's checks
never use real ones: they use a mock provider and Moto, see `scripts/check.sh`.)

## Bootstrapping state

Terraform's **state** records which real resources belong to your configuration. By default it is a local file;
for a team it should live in S3 (see [ADR 0003](../../docs/adr/0003-s3-native-state-locking.md)). That creates a
chicken-and-egg problem: the bucket that stores state must itself be created by Terraform. The usual way out:

1. **Apply the state backend with local state.** In a scratch root module (or here, temporarily) call
   `modules/state-backend` with the same `project` and `environment`, then `terraform apply`. State for this
   one small stack stays in a local `terraform.tfstate`.
2. **Read the output.** `terraform output backend_config` prints the bucket name, region, KMS key and
   `use_lockfile = true`.
3. **Enable the backend in `envs/dev`.** Uncomment the `backend "s3"` block in `main.tf`, fill in the values,
   and choose a `key` such as `envs/dev/terraform.tfstate`.
4. **Migrate.** Run `terraform init -migrate-state`. Terraform offers to copy the local state into the bucket.
5. **Protect it.** Keep the bootstrap stack's local state somewhere safe (or migrate it into the same bucket
   under a different `key`). The bucket has versioning on, so a bad write can be rolled back.

This repo never runs these steps for you: it has no AWS account, only mock and Moto tests.

## Why it's built this way

- **One root module per environment** (`envs/dev`, later `envs/prod`) keeps each environment's state and blast
  radius separate, instead of one folder switched by workspaces or flags.
- **`environment` is hard-coded to `dev`** rather than a variable, so this folder can never accidentally be
  applied as `prod`.
- **`default_tags` on the provider** tag every taggable resource with project, environment, owner and
  managed-by without repeating `tags = ...` in each module call.
- **Backend block commented out.** A backend block cannot use variables, and enabling it before the bucket
  exists makes `terraform init` fail. It is committed as documentation, enabled on purpose.
- **Providers in the root, never in child modules**, so modules stay reusable with any provider configuration.

## Testing

`tests/unit.tftest.hcl` uses `mock_provider "aws"` with `command = plan` to check the default names and tags,
that variables flow into `labels` and the provider region, that dev gets 3 subnets per tier and one shared NAT
gateway, that `single_nat_gateway = false` gives three, and that `az_count = 2` is respected.
`tests/integration.tftest.hcl` overrides the provider to point at Moto and applies the whole root module. It
asserts 3 + 3 + 3 subnets, one private route table per AZ, one NAT gateway (three with
`single_nat_gateway = false`) and the flow log group name. A root module can only see its child modules'
outputs, so the tests assert on root outputs rather than on resources inside modules.
