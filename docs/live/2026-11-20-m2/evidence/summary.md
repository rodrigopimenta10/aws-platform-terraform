## Live drill: `m2` applied

- Commit: `0793331850bdf81391b82ecdab1e97bb04014d0e`
- Region: `us-east-1`
- Apply took 18s and created 9 resources.
- Hold: 0 minutes. The destroy job starts its hold when it is approved, so destroy begins
  0 minutes after that approval: 00:58 UTC at the earliest.

### Resources by type

| Type | Count |
|---|---|
| `aws_cloudwatch_log_group` | 1 |
| `aws_ebs_encryption_by_default` | 1 |
| `aws_iam_account_password_policy` | 1 |
| `aws_iam_policy` | 1 |
| `aws_iam_role` | 2 |
| `aws_kms_alias` | 1 |
| `aws_kms_key` | 1 |
| `aws_s3_account_public_access_block` | 1 |

### Console (what each screenshot should prove)

- [kms-key](https://us-east-1.console.aws.amazon.com/kms/home?region=us-east-1#/kms/keys/36ce1bfd-0ed3-40ec-a7e9-f0e94e286e69): Customer-managed symmetric key with alias platform-live-logs, enabled, with automatic rotation shown as enabled
- [kms-key-policy](https://us-east-1.console.aws.amazon.com/kms/home?region=us-east-1#/kms/keys/36ce1bfd-0ed3-40ec-a7e9-f0e94e286e69): The key policy has the account root delegation statement and a CloudWatch Logs statement limited by an encryption context
- [log-group-uses-key](https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups$3FlogGroupNameFilter$3Dplatform-live): The log group /aws/platform-live/app with 1 year retention and the drill KMS key ID shown
- [github-role-trust](https://us-east-1.console.aws.amazon.com/iam/home?region=us-east-1#/roles/details/platform-live-github-deploy?section=trust_relationships): Role platform-live-github-deploy trusts the GitHub OIDC provider with audience sts.amazonaws.com and only this repository's refs/heads/main as subject
- [worker-role-boundary](https://us-east-1.console.aws.amazon.com/iam/home?region=us-east-1#/roles/details/platform-live-worker?section=permissions): Role platform-live-worker has no permission policies and shows the permissions boundary platform-live-drill-boundary
- [ebs-default-encryption](https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#Settings:tab=dataProtectionAndSecurity): EC2 settings, Data protection and security: Always encrypt new EBS volumes is Enabled
- [s3-account-public-access](https://s3.console.aws.amazon.com/s3/settings?region=us-east-1): S3 Block public access (account settings): all four settings On
- [iam-password-policy](https://us-east-1.console.aws.amazon.com/iam/home?region=us-east-1#/account_settings): IAM account settings show the password policy: 14 characters minimum, 90 day expiry, reuse prevention of 24
