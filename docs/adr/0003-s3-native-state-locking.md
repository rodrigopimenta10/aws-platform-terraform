# ADR 0003: S3 native state locking instead of a DynamoDB table

- **Status:** accepted
- **Date:** 2026-11-10

## Context
Terraform keeps a **state file**, its record of which real resources it manages. A **remote backend**
stores that file somewhere shared, here S3 (Amazon's object storage, where a "bucket" is a named
container for files). If two people run `apply` at once without a **lock**, both read the same state,
and the later write can silently overwrite the earlier one, corrupting it.

Until recently S3 could not lock, so the standard pattern was a DynamoDB table (AWS's key-value
database) whose item acted as the lock. Terraform 1.10 added `use_lockfile = true`: the S3 backend
writes a small `.tflock` object next to the state using S3 conditional writes, so only one writer wins.

## Decision
Use S3 native locking. `modules/state-backend` creates only a bucket and a KMS key, no DynamoDB table.
The module's `backend_config` output includes `use_lockfile = true`. The repo already requires
Terraform `>= 1.10`.

## Consequences
- One resource fewer to create, pay for, encrypt, back up and bootstrap.
- The identity running Terraform needs `s3:PutObject` and `s3:DeleteObject` on the `.tflock` object as
  well as on the state key.
- Versioning stays on, so lock files create extra object versions; the lifecycle rule cleans them up.
- The DynamoDB locking arguments of the S3 backend are deprecated, so this avoids a future migration.
- Teams stuck on Terraform older than 1.10 cannot use this module's backend config.
