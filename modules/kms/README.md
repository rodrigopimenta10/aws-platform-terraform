# kms

**KMS** (Key Management Service) is AWS's service for encryption keys. A **customer-managed key** is one you
create and write the access policy for, as opposed to a key AWS owns and hides from you. Services such as
CloudWatch Logs, ECR and S3 can encrypt their data with your key, so reading that data needs permission on
the data *and* on the key, and every use of the key is logged in CloudTrail.

This module creates **one key and one alias** (a friendly name, `alias/<project>-<environment>-<purpose>`)
with automatic rotation always on. Call it once per workload so each gets its own key.

The **key policy** is the document that says who may use the key. Unlike most AWS resources, a key is
unusable without one. This module writes a policy with separate jobs:

| Statement | Who | Can do |
|-----------|-----|--------|
| `EnableIAMPolicies` | the account root | delegate: lets ordinary IAM policies grant access to the key |
| `KeyAdministratorsManageButCannotUse` | `key_administrator_arns` | manage (tag, rotate, disable, schedule deletion), **not** encrypt or decrypt |
| `KeyUsersEncryptAndDecrypt` | `key_user_arns` | encrypt, decrypt, generate data keys, **not** manage |
| `Service<Name>` | each entry of `service_grants` | what the service needs, optionally only when the request carries a given **encryption context** |

Names and tags come from the [`labels`](../labels/) module.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | n/a (required) | Passed to `labels`. |
| `environment` | `string` | n/a (required) | `dev`, `staging`, `prod` or `live`. |
| `owner` | `string` | n/a (required) | Owner tag value. |
| `purpose` | `string` | n/a (required) | What the key protects (`logs`, `ecr`...). Becomes part of the alias. |
| `description` | `string` | n/a (required) | Console description, at least 10 characters. |
| `key_administrator_arns` | `list(string)` | `[]` | IAM role or user ARNs that manage the key but cannot use it. |
| `key_user_arns` | `list(string)` | `[]` | IAM role or user ARNs that use the key but cannot manage it. |
| `service_grants` | `map(object)` | `{}` | AWS services allowed to use the key: `service` principal plus optional `encryption_context` map. |
| `rotation_period_in_days` | `number` | `365` | 90 to 2560. Rotation can't be turned off. |
| `deletion_window_in_days` | `number` | `30` | 7 to 30 days between scheduling deletion and removal. |

## Outputs

| Name | Description |
|------|-------------|
| `key_id` | ID of the key. |
| `key_arn` | ARN of the key, for a resource's `kms_key_id`. |
| `alias_name` | `alias/<project>-<environment>-<purpose>`. |
| `alias_arn` | ARN of the alias. |

## Example

```hcl
module "kms_logs" {
  source = "../../modules/kms"

  project     = "platform"
  environment = "dev"
  owner       = "platform-team"
  purpose     = "logs"
  description = "Encrypts platform CloudWatch log groups"

  key_administrator_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
  key_user_arns          = ["arn:aws:iam::123456789012:role/app"]

  service_grants = {
    CloudWatchLogs = {
      service            = "logs.us-east-1.amazonaws.com"
      encryption_context = { "aws:logs:arn" = "arn:aws:logs:us-east-1:123456789012:log-group:/platform/app" }
    }
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name       = "/platform/app"
  kms_key_id = module.kms_logs.key_arn
}
```

## Why it's built this way

- **Administrators and users are different people.** The usual mistake is one statement with `kms:*` for
  the "owner". Here whoever can schedule the key's deletion or edit its policy cannot decrypt the data,
  and the tests assert that neither list contains the other's actions.
- **The root statement stays.** `Principal: root` with `kms:*` looks like a wildcard but only means "IAM
  policies in this account may grant access". Without it, deleting the one admin role would leave a key
  nobody can fix. The checkov rules about `*` in a policy (`CKV_AWS_109`, `111`, `356`) are skipped with
  that reason. In a key policy `Resource: "*"` can only ever mean this key.
- **Services get a context, not a blank cheque.** A service grant can require an **encryption context**,
  extra labelled data KMS checks on every call. CloudWatch Logs includes the log group ARN, so a key
  granted for one log group cannot be used for another. Exact-match `StringEquals` is used, so wildcards
  are impossible by design.
- **Rotation is not optional.** There's no variable to turn it off. The period is configurable (90 to 2560
  days); old key material is kept, so data encrypted before a rotation stays readable.
- **One key per purpose.** A shared key is cheaper (about $1 a month each) but couples blast radius and
  makes the policy a pile of exceptions. Cost is low enough to prefer separation.
- **No multi-region keys, no grants.** Not needed yet; adding them later does not change this interface.
- **Deletion is slow on purpose.** KMS keys can't be deleted immediately; they wait 7 to 30 days disabled,
  because deleting a key makes everything encrypted with it unreadable forever. Default is 30.

## Testing

Unit tests (mock provider, `plan`) check the default policy, that administrators get no data-use action
and users no management action, the encryption context condition, and every input validation. The Moto test
applies the module with all three kinds of principal and checks the key, rotation, alias and outputs.
Moto stores the policy but does not enforce it, so what a principal can really do is shown only by the
live drill, and `kms:ViaService`-style behaviour is not emulated.
