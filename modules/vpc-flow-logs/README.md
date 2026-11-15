# vpc-flow-logs

**VPC flow logs** record the network connections that cross a VPC's network interfaces: source and
destination address and port, protocol, bytes, and whether the traffic was accepted or rejected. They do
not contain packet contents. You use them to answer "who talked to whom?" and "what is my security group
blocking?" after something has happened.

This module sends them to a **CloudWatch Logs** log group (AWS's log storage and search service) and
creates what that needs:

- a customer-managed **KMS key** (AWS's encryption key service) with yearly rotation, whose policy lets
  CloudWatch Logs use it for this one log group only,
- the **log group**, encrypted with that key, with a retention period you choose,
- an **IAM role** that the flow logs service assumes, allowed to write to that log group and nothing else,
- the **flow log** attached to the VPC.

Names and tags come from the [`labels`](../labels/) module.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | n/a (required) | Passed to `labels`. |
| `environment` | `string` | n/a (required) | `dev`, `staging`, `prod` or `live`. |
| `owner` | `string` | n/a (required) | Owner tag value. |
| `vpc_id` | `string` | n/a (required) | VPC to record. |
| `retention_in_days` | `number` | `365` | Days CloudWatch keeps records. Must be a value CloudWatch accepts; 0 (forever) is rejected. |
| `traffic_type` | `string` | `"ALL"` | `ACCEPT`, `REJECT` or `ALL`. |
| `max_aggregation_interval` | `number` | `600` | Seconds a flow is grouped into one record: `60` or `600`. |
| `kms_deletion_window_in_days` | `number` | `30` | 7 to 30 days between scheduling the key for deletion and its removal. |
| `permissions_boundary` | `string` | `null` | IAM permissions boundary ARN for the role. |

## Outputs

| Name | Description |
|------|-------------|
| `flow_log_id` | ID of the flow log. |
| `log_group_name` | Log group receiving the records. |
| `log_group_arn` | ARN of that log group. |
| `kms_key_arn` | ARN of the key that encrypts it. |
| `iam_role_arn` | ARN of the role the flow logs service assumes. |

## Example

```hcl
module "vpc" {
  source = "../../modules/vpc"
  # ...
}

module "vpc_flow_logs" {
  source = "../../modules/vpc-flow-logs"

  project     = "platform"
  environment = "dev"
  owner       = "platform-team"

  vpc_id            = module.vpc.vpc_id
  retention_in_days = 90
}
```

## Why it's built this way

- **Encrypted with its own key.** Flow logs reveal your network layout and who talks to what, so they get
  a customer-managed key: reading them needs both CloudWatch and KMS permission, and key use is logged.
  The key policy allows the CloudWatch Logs service only when the **encryption context** names this log
  group's ARN, so the same service cannot use the key for any other group. The ARN is built from its
  documented format because the key policy and the log group would otherwise depend on each other.
  Rotation is on. [`modules/kms`](../../ROADMAP.md) (M2.1) will later hold shared keys; until then this
  module owns a small one.
- **Retention is explicit and never "forever".** The default is 365 days (also what checkov rule
  `CKV_AWS_338` expects for logs you may need in an investigation). Storage is billed per GB-month, so
  throwaway environments should pass a small number such as `7`. The validation lists the values
  CloudWatch accepts and rejects `0`, so logs cannot silently grow forever.
- **A role scoped to one log group.** The flow logs service writes through a role. Its trust policy
  requires `aws:SourceAccount` and a flow-log `aws:SourceArn`, which stops another account's flow log from
  borrowing the role (the "confused deputy" problem). Its permissions are three `logs:` actions on the one
  log group, never `Resource: "*"`.
- **CloudWatch Logs, not S3.** Logs is easy to search and needs no extra setup; S3 is cheaper for large
  volumes and fits Athena queries. A future change could add S3 as a second destination.
- **`ALL` traffic and 10-minute aggregation by default.** Rejected-only traffic is cheaper but hides what
  was allowed; 60-second aggregation gives finer detail at a higher record count.
- **checkov skips.** `CKV_AWS_109`, `CKV_AWS_111` and `CKV_AWS_356` on the key: in a key policy `"*"` as
  the resource means "this key", and the account-root statement is what lets IAM delegate access. Reasons
  are inline.

## Tests

`tests/unit.tftest.hcl` uses the mock provider (plan only) to check the names, the key policy's log group
condition, the role's trust and permissions, the boundary, the options and every validation rule.
`tests/integration.tftest.hcl` applies `modules/vpc` and then the flow log against Moto and checks the flow
log, log group, key and role are wired together. Moto does not deliver any records, so that traffic
actually appears in the log group is proven only by the live drill.
