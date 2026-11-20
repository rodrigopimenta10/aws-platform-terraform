## Live drill: `m3` applied

- Commit: `65b000c9a0d79a0e39e52d94d3ce14d9c3f93a5e`
- Region: `us-east-1`
- Apply took 16s and created 6 resources.
- Hold: 0 minutes. The destroy job starts its hold when it is approved, so destroy begins
  0 minutes after that approval: 01:17 UTC at the earliest.

### Resources by type

| Type | Count |
|---|---|
| `aws_ecr_lifecycle_policy` | 2 |
| `aws_ecr_repository` | 2 |
| `aws_kms_alias` | 1 |
| `aws_kms_key` | 1 |

### Console (what each screenshot should prove)

- [ecr-repositories](https://us-east-1.console.aws.amazon.com/ecr/private-registry/repositories?region=us-east-1): Private repositories platform-live-api and platform-live-worker, both with Immutable tag mutability and KMS encryption
- [ecr-key](https://us-east-1.console.aws.amazon.com/kms/home?region=us-east-1#/kms/keys/cbf064ff-c2dd-4947-8f67-d40f4c77def2): The customer-managed key alias platform-live-ecr that encrypts both repositories, enabled, with automatic rotation shown as enabled
