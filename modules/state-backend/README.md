# state-backend

An encrypted, versioned S3 bucket (plus a KMS key) for storing Terraform state remotely.
Locking uses S3 native lock files, so **no DynamoDB table** is created
([ADR 0003](../../docs/adr/0003-s3-native-state-locking.md)).

## What it creates

| Resource | Purpose |
|----------|---------|
| `aws_s3_bucket` | Holds state files. Name: `<project>-<env>-tfstate-<account-id>-<region>`. |
| `aws_s3_bucket_versioning` | Keeps every previous state file so a bad apply can be rolled back. |
| `aws_s3_bucket_server_side_encryption_configuration` | SSE-KMS with the key below, bucket keys on. |
| `aws_s3_bucket_public_access_block` | All four public-access settings on. |
| `aws_s3_bucket_ownership_controls` | `BucketOwnerEnforced`: ACLs disabled. |
| `aws_s3_bucket_policy` | Denies every request that is not over TLS. |
| `aws_s3_bucket_lifecycle_configuration` | Expires noncurrent versions after N days, aborts stale multipart uploads. |
| `aws_kms_key` + `aws_kms_alias` | Customer-managed key with automatic yearly rotation. |

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | n/a (required) | Passed to [labels](../labels/). |
| `environment` | `string` | n/a (required) | `dev`, `staging`, `prod` or `live`. |
| `owner` | `string` | n/a (required) | Team or alias, never an email. |
| `noncurrent_version_expiration_days` | `number` | `90` | Days before an old state version is deleted. Minimum 7. |
| `kms_deletion_window_in_days` | `number` | `30` | KMS key deletion waiting period, 7-30. |
| `force_destroy` | `bool` | `false` | Let `destroy` delete a non-empty bucket. Tests only. |
| `extra_tags` | `map(string)` | `{}` | Extra tags. |

## Outputs

| Name | Description |
|------|-------------|
| `bucket_name` | State bucket name, for the backend `bucket` setting. |
| `bucket_arn` | Bucket ARN, for IAM policies. |
| `kms_key_arn` | Key ARN. Roles using the state need `kms:Decrypt` and `kms:GenerateDataKey` on it. |
| `kms_alias_name` | `alias/<prefix>-tfstate`. |
| `backend_config` | Object with `bucket`, `region`, `encrypt`, `kms_key_id`, `use_lockfile`. |
| `tags` | Standard tags from labels. |

## Example

```hcl
module "state_backend" {
  source = "../../modules/state-backend"

  project     = "platform"
  environment = "dev"
  owner       = "platform-team"
}
```

After the first `apply` (which uses local state), other roots point at it:

```hcl
terraform {
  backend "s3" {
    bucket       = "platform-dev-tfstate-123456789012-us-east-1" # output bucket_name
    key          = "envs/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:us-east-1:123456789012:key/..." # output kms_key_arn
    use_lockfile = true
  }
}
```

## Why it's built this way

- **Versioning + lifecycle.** State is the one file you cannot regenerate. Versioning gives an undo
  history; the lifecycle rule stops that history from growing forever.
- **SSE-KMS with a customer-managed key** (not the default S3 key). State can contain secrets, and with
  your own key access needs both S3 *and* KMS permission, and every use is logged in CloudTrail.
- **Key rotation on.** AWS rotates the key material yearly; old data stays readable.
- **Public access fully blocked and ACLs off.** Access is only through IAM and the bucket policy.
- **TLS-only policy.** A `Deny` on `aws:SecureTransport = false` blocks plain-HTTP requests.
- **`use_lockfile` instead of DynamoDB.** One less resource to pay for, secure and bootstrap.
- **Bucket name includes account ID and region.** S3 names are global; this avoids collisions.
- **`force_destroy` is false by default** so a stray `destroy` cannot wipe state.
- **Chicken-and-egg:** this module's own state is local the first time. Bootstrapping is covered in
  `envs/dev` (roadmap M0.3).
- **Cost:** pennies per month for a few small files, plus about $1/month for the KMS key.

### checkov skips
`CKV_AWS_18` (access logging) and `CKV_AWS_144` (cross-region replication) are skipped inline with
reasons; `CKV2_AWS_62` (event notifications) too. The KMS root statement in the key policy is skipped for
`CKV_AWS_109/111/356` because `Resource = "*"` in a key policy only means "this key".

## Testing notes
`tests/unit.tftest.hcl` uses a mock provider (`plan`). `tests/integration.tftest.hcl` applies against Moto.
Moto does not return the lifecycle setting `NewerNoncurrentVersions` when reading a rule back, which made
the AWS provider wait forever, so the module only uses `noncurrent_days`. Moto does not enforce the TLS
deny policy, so that is verified in the unit test by inspecting the policy JSON.
