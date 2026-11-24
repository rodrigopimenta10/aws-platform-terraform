# eks-pod-identity

Gives **one workload** on EKS its own AWS permissions through **EKS Pod Identity**. A pod that calls an AWS
API (read an S3 object, write to a queue) needs credentials. The wrong answers are to put long-lived keys in
a Secret or to give the worker node's role to every pod on the node. Pod Identity gives the pod a role of its
own: you name a cluster, a Kubernetes **namespace** and a **service account** (the identity a pod runs as
inside Kubernetes), and only pods running as that service account receive the role's temporary credentials.

The module creates:

1. an IAM role, through [`iam-role`](../iam-role/) so the permissions boundary is mandatory, that only the EKS
   pods service (`pods.eks.amazonaws.com`) can assume,
2. an optional inline policy on that role,
3. the `aws_eks_pod_identity_association` that links the role to the service account.

The cluster must run the `eks-pod-identity-agent` add-on (see [`eks-addons`](../eks-addons/)). The agent runs
on every node and answers the AWS SDK's credential request for the pod. Without it the association exists
and nothing is delivered. [ADR 0005](../../docs/adr/0005-pod-identity-over-irsa.md) explains why this is
used instead of IRSA.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project`, `environment`, `owner` | `string` | n/a | Passed to [`labels`](../labels/) for names and tags. |
| `name` | `string` | n/a | Workload name. The role is `<project>-<environment>-<name>`. |
| `cluster_name` | `string` | n/a | EKS cluster the workload runs in. |
| `namespace` | `string` | n/a | Kubernetes namespace of the service account. |
| `service_account` | `string` | n/a | Service account whose pods get the role. Exact name, no wildcards. |
| `permissions_boundary` | `string` | `null` | Boundary policy ARN. Planning fails without it. |
| `managed_policy_arns` | `list(string)` | `[]` | Managed policies to attach. |
| `policy_json` | `string` | `null` | Optional inline policy (JSON). |

## Outputs

| Name | Description |
|------|-------------|
| `role_arn` | ARN of the workload's role. |
| `role_name` | Name of the role, for attaching more policies. |
| `association_arn` / `association_id` | The Pod Identity association. |
| `trust_policy` | The trust policy JSON. |

## Example

```hcl
module "orders_identity" {
  source = "../../modules/eks-pod-identity"

  project              = "platform"
  environment          = "dev"
  owner                = "platform-team"
  name                 = "orders"
  cluster_name         = module.eks.cluster_name
  namespace            = "orders"
  service_account      = "orders-api"
  permissions_boundary = module.boundary.policy_arn

  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = ["arn:aws:s3:::example-orders-bucket/*"]
    }]
  })
}
```

In Kubernetes, nothing needs annotating. Create a service account called `orders-api` in namespace `orders`,
run the pods with `serviceAccountName: orders-api`, and the AWS SDK finds credentials by itself.

## Why it's built this way

- **Trust the service, not an OIDC provider.** The trust policy is one fixed statement for every cluster.
  IRSA needs an OIDC provider per cluster and a trust policy that quotes that provider's URL.
- **Confused-deputy guards.** `aws:SourceAccount` and `aws:SourceArn` (this cluster in this account) mean the
  EKS service cannot be talked into handing the role to another account's cluster. The ARN uses `*` for the
  region only, because a role is global and the cluster's region is not known here; the cluster name and
  account are pinned.
- **The binding lives in EKS, not in the role.** The role does not name the namespace or service account, so
  one role can serve several associations and moving a workload changes the association, not IAM.
- **Boundary mandatory, wildcards impossible.** The role goes through `iam-role`. The service account is an
  exact name: a wildcard would give every pod in the namespace the role.
- **Inline policy.** It belongs to this one workload and has no life of its own. Shared permissions go in
  `managed_policy_arns`.
- **Cost.** Free.

## Testing

Unit tests only (mock provider, `terraform test`): the association fields and tags, the trust policy
(service, account, cluster, `sts:TagSession`), the boundary, the optional inline policy, and validation
failures for bad names, a wildcard service account, non-JSON policy and a bad boundary ARN. "No boundary is
rejected" is tested in [`iam-role`](../iam-role/), because a test cannot expect a failure inside a child
module. Moto has no Pod Identity API, so there is no apply test here; the `m3` live drill creates a real
association.
