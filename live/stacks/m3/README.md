# live/stacks/m3

The **milestone 3 live-drill stack**: applies [`modules/ecr`](../../../modules/ecr/) (and a
[`modules/kms`](../../../modules/kms/) key for it) into the real AWS account for the length of a drill, then gets
destroyed. Nobody runs `terraform apply` here by hand. Later M3 items (EKS, node groups, add-ons) add to this stack.

What it creates in `us-east-1`: a KMS key with alias `platform-live-ecr` and two ECR repositories,
`platform-live-api` (keeps the last 30 images) and `platform-live-worker` (keeps 10), each with immutable tags,
scan on push, KMS encryption and a lifecycle policy. Both set `force_delete = true` so destroy works even if an
image was pushed.

**Cost:** empty repositories are free; the key is a fraction of a cent for a drill.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `region` | `string` | `"us-east-1"` | Region to apply into. The drill role denies all others. |
| `owner` | `string` | `"platform-team"` | Owner tag. No email addresses. |

## Outputs

`region`, `tags`, `kms_key_id`, `ecr_api_repository_name`, `ecr_worker_repository_name`. The console links in
`live/screenshots.yml` use them.

The workflow also exports `TF_VAR_permissions_boundary_arn`; this stack creates no IAM roles yet, so it declares
no such variable (Terraform ignores an undeclared `TF_VAR_` value). Add it when a module here creates a role.
