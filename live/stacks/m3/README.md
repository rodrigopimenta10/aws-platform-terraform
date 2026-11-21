# live/stacks/m3

The **milestone 3 live-drill stack**: applies [`modules/ecr`](../../../modules/ecr/) (and a
[`modules/kms`](../../../modules/kms/) key for it) into the real AWS account for the length of a drill, then gets
destroyed. Nobody runs `terraform apply` here by hand. Later M3 items (node groups, add-ons) add to this stack.

What it creates in `us-east-1`: a KMS key with alias `platform-live-ecr` and two ECR repositories,
`platform-live-api` (keeps the last 30 images) and `platform-live-worker` (keeps 10), each with immutable tags,
scan on push, KMS encryption and a lifecycle policy. Both set `force_delete = true` so destroy works even if an
image was pushed.

M3.2 adds [`modules/eks`](../../../modules/eks/): a small VPC ([`modules/vpc`](../../../modules/vpc/), 2 AZs, no NAT
gateway), a second KMS key (`platform-live-eks`, for Secrets and control-plane logs) and the cluster
`platform-live-eks` with a private endpoint, all five log types and no nodes or access entries.

**Cost:** empty repositories are free; the keys are a fraction of a cent for a drill. The EKS control plane is
$0.10 an hour, so a 20 to 40 minute drill costs a few cents. Creating a cluster takes about 10 minutes and
deleting it a few more.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `region` | `string` | `"us-east-1"` | Region to apply into. The drill role denies all others. |
| `owner` | `string` | `"platform-team"` | Owner tag. No email addresses. |
| `permissions_boundary_arn` | `string` | `null` | Boundary for every role here; set by the workflow. |

## Outputs

`region`, `tags`, `kms_key_id`, `ecr_api_repository_name`, `ecr_worker_repository_name`, `eks_cluster_name`,
`eks_kms_key_id`, `vpc_id`. The console links in
`live/screenshots.yml` use them.

The workflow exports `TF_VAR_permissions_boundary_arn`; the cluster's IAM role must carry that boundary, so it is
passed to `modules/eks`.