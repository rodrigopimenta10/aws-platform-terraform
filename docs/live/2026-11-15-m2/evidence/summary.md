## Live drill: `m2` applied

- Commit: `f9c3a6875fc4b117fdb64b5bb4b20b2493a22019`
- Region: `us-east-1`
- Apply took 16s and created 3 resources.
- Hold: 0 minutes. The destroy job starts its hold when it is approved, so destroy begins
  0 minutes after that approval: 00:49 UTC at the earliest.

### Resources by type

| Type | Count |
|---|---|
| `aws_cloudwatch_log_group` | 1 |
| `aws_kms_alias` | 1 |
| `aws_kms_key` | 1 |

### Console (what each screenshot should prove)

- [kms-key](https://us-east-1.console.aws.amazon.com/kms/home?region=us-east-1#/kms/keys/22360b4a-2d61-41b6-abb9-57f4bcd4e2fb): Customer-managed symmetric key with alias platform-live-logs, enabled, with automatic rotation shown as enabled
- [kms-key-policy](https://us-east-1.console.aws.amazon.com/kms/home?region=us-east-1#/kms/keys/22360b4a-2d61-41b6-abb9-57f4bcd4e2fb): The key policy has the account root delegation statement and a CloudWatch Logs statement limited by an encryption context
- [log-group-uses-key](https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups$3FlogGroupNameFilter$3Dplatform-live): The log group /aws/platform-live/app with 1 year retention and the drill KMS key ID shown
