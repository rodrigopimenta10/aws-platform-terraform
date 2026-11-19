# account-baseline

Three account-level security defaults, each a **singleton**: an AWS account (or account and region) has
exactly one of each, so instantiate this module once per account, not once per environment.

| Setting | Resource | What it does |
|---|---|---|
| EBS encryption by default | `aws_ebs_encryption_by_default` (+ optional `aws_ebs_default_kms_key`) | EBS (Elastic Block Store) is the disk service behind EC2 and EKS nodes. With this on, every new volume is encrypted even if the creator forgot to ask. Per **region**. |
| S3 account public access block | `aws_s3_account_public_access_block` | Overrides every bucket in the account, present and future, so no ACL or bucket policy can make one public. |
| IAM password policy | `aws_iam_account_password_policy` | Rules for IAM users' console passwords. The platform prefers roles and OIDC, but a break-glass user would otherwise get AWS's weak default. |

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `enable_ebs_encryption_by_default` | `bool` | `true` | Turn default EBS encryption on or off for the region. |
| `ebs_default_kms_key_arn` | `string` | `null` | KMS key ARN for new volumes. Null keeps the AWS-managed `aws/ebs` key. Aliases are rejected. |
| `password_minimum_length` | `number` | `14` | 14 to 128. |
| `password_max_age_days` | `number` | `90` | 0 (never expires) to 1095. |
| `password_reuse_prevention` | `number` | `24` | Previous passwords that cannot be reused, 1 to 24. |

The S3 block and the password character classes (upper, lower, number, symbol) have **no variable**: they
are not something to loosen per environment.

## Outputs

| Name | Description |
|------|-------------|
| `ebs_encryption_by_default_enabled` | Whether default EBS encryption is on. |
| `ebs_default_kms_key_arn` | The default key, or null for `aws/ebs`. |
| `s3_public_access_blocked` | True when all four S3 settings are on. |
| `password_minimum_length` | Enforced minimum length. |

## Example

```hcl
module "account_baseline" {
  source = "../../modules/account-baseline"

  ebs_default_kms_key_arn = module.kms_ebs.key_arn # optional, see modules/kms
}
```

## Why it's built this way

- **Defaults on, little to configure.** These are guardrails. A flag that turns one off would be used first.
- **Singletons, so one instance.** Two stacks managing the same account setting would fight over it, each
  apply undoing the other. Apply this from one place only.
- **Destroy resets, it does not restore.** Destroying removes the S3 block and password policy and turns EBS
  default encryption off. It does not bring back whatever the account had before.
- **EBS default is per region.** Instantiate it with a provider for each region you use.
- **Existing volumes are not touched.** Only volumes created after the setting is on are encrypted.
- **Key alias rejected.** The API wants a key ID or ARN. The validation catches it at plan time.

## Testing and Moto limits

Unit tests (mock provider) cover the defaults, the optional key, every validation and the rule that the
key is ignored while encryption is off. The Moto test applies the EBS and password policy resources. It
**does not apply the S3 account block**: the provider reaches the S3 Control API at
`<account-id>.<endpoint>`, a hostname that cannot point at a local Moto server, so that resource is covered
by unit tests and by the live drill (`live/stacks/m2`).
