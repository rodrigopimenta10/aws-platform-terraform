## Live drill: `m2` applied

- Commit: `8cc01433cab60a40609bbd57d2d7e9a5f40b8527`
- Region: `us-east-1`
- Apply took 18s and created 4 resources.
- Hold: 0 minutes. The destroy job starts its hold when it is approved, so destroy begins
  0 minutes after that approval: 16:55 UTC at the earliest.

### Resources by type

| Type | Count |
|---|---|
| `aws_cloudwatch_log_group` | 1 |
| `aws_iam_role` | 1 |
| `aws_kms_alias` | 1 |
| `aws_kms_key` | 1 |

### Console (what each screenshot should prove)

- [kms-key](https://us-east-1.console.aws.amazon.com/kms/home?region=us-east-1#/kms/keys/6e11bb56-6638-477b-a82f-feb1565a14c3): Customer-managed symmetric key with alias platform-live-logs, enabled, with automatic rotation shown as enabled
- [kms-key-policy](https://us-east-1.console.aws.amazon.com/kms/home?region=us-east-1#/kms/keys/6e11bb56-6638-477b-a82f-feb1565a14c3): The key policy has the account root delegation statement and a CloudWatch Logs statement limited by an encryption context
- [log-group-uses-key](https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups$3FlogGroupNameFilter$3Dplatform-live): The log group /aws/platform-live/app with 1 year retention and the drill KMS key ID shown
- [github-role-trust](https://us-east-1.console.aws.amazon.com/iam/home?region=us-east-1#/roles/details/platform-live-github-deploy?section=trust_relationships): Role platform-live-github-deploy trusts the GitHub OIDC provider with audience sts.amazonaws.com and only this repository's refs/heads/main as subject
