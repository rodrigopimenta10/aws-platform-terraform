# eks-addons

An **EKS add-on** is a piece of operational software that AWS packages, tests against each Kubernetes version
and can install and upgrade through the EKS API. A new cluster already runs default copies of three of them,
but nobody wrote down which versions. This module declares them as `aws_eks_addon` resources, so EKS takes
them over and the **version of each one is pinned in code**: an upgrade becomes a reviewed change.

| Add-on | What it does | Needs |
|--------|--------------|-------|
| `vpc-cni` | Gives every pod a real VPC IP address (the pod network). Runs as the `aws-node` DaemonSet, one pod per node. | The node role's `AmazonEKS_CNI_Policy` (see [`eks-node-group`](../eks-node-group/)). |
| `coredns` | Cluster DNS: turns `my-service.my-namespace.svc` into an IP. | Nodes to run on. Without nodes it stays *Degraded* and Terraform waits. |
| `kube-proxy` | Programs each node's network rules so a Service address reaches a pod. | Nothing extra. |
| `eks-pod-identity-agent` | Hands pods temporary credentials for their own IAM role (**Pod Identity**). | Nodes. |
| `aws-ebs-csi-driver` | Lets pods use EBS disks as PersistentVolumes. **CSI** (Container Storage Interface) is Kubernetes' plug-in standard for storage. | A role with `AmazonEBSCSIDriverPolicy`, which the module creates, and the agent above. |

Any other add-on name works too; the five above are the ones the module knows extra things about.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | n/a (required) | Passed to `labels`. |
| `environment` | `string` | n/a (required) | `dev`, `staging`, `prod` or `live`. |
| `owner` | `string` | n/a (required) | Owner tag value. |
| `name` | `string` | `"addons"` | Component name; the EBS CSI role is `<project>-<environment>-<name>-ebs-csi-role`. |
| `cluster_name` | `string` | n/a (required) | Cluster to install into (`eks` output `cluster_name`). |
| `permissions_boundary` | `string` | `null` | Boundary policy ARN for the role created for the EBS CSI driver. |
| `addons` | `map(object)` | n/a (required) | Add-on name to `{ version, configuration_values, resolve_conflicts_on_update, pod_identity_role_arn }`. Only `version` is required, and it has no default on purpose. |

## Outputs

| Name | Description |
|------|-------------|
| `addon_arns` | Map of add-on name to ARN. |
| `addon_versions` | Map of add-on name to the pinned, installed version. |
| `ebs_csi_role_arn` | ARN of the role created for the EBS CSI driver, or `null`. |

## Example

```hcl
module "addons" {
  source = "../../modules/eks-addons"

  project              = "platform"
  environment          = "dev"
  owner                = "platform-team"
  cluster_name         = module.eks.cluster_name
  permissions_boundary = module.boundary.policy_arn

  addons = {
    "vpc-cni"                = { version = "v1.19.5-eksbuild.1" }
    "kube-proxy"             = { version = "v1.33.0-eksbuild.2" }
    "eks-pod-identity-agent" = { version = "v1.3.7-eksbuild.2" }
    "coredns"                = { version = "v1.12.1-eksbuild.2", configuration_values = jsonencode({ replicaCount = 2 }) }
    "aws-ebs-csi-driver"     = { version = "v1.45.0-eksbuild.2" }
  }

  # CoreDNS and the others cannot become healthy until there are nodes to run on.
  depends_on = [module.nodes]
}
```

The versions above are examples. List the real ones for your cluster with
`aws eks describe-addon-versions --addon-name coredns --kubernetes-version 1.33`.

## Why it's built this way

- **Versions are required, with no default and no `latest`.** Add-on versions are tied to the Kubernetes
  minor version, and a default would silently move on the next `apply`. A validation rejects anything that is
  not an exact `vX.Y.Z-eksbuild.N`. The cost is that you update the numbers by hand when you upgrade the
  cluster, which is the point.
- **`OVERWRITE` on create and (by default) on update.** The cluster's own copies of `vpc-cni`, `coredns` and
  `kube-proxy` already exist. With `OVERWRITE`, EKS replaces any settings on them with the ones in code,
  so the code is the truth. `PRESERVE` is there for the day someone must keep a hand edit, but it hides drift.
- **Pod Identity for the EBS driver, not IRSA.** The older way (IRSA, IAM Roles for Service Accounts) needs an
  OIDC identity provider per cluster and a trust policy naming the exact service account. Pod Identity trusts
  one service principal, `pods.eks.amazonaws.com`, and the link between role and service account is an
  association stored in EKS. M3.5 covers it in more depth. The module requires the agent add-on when the
  driver is installed, because the driver would otherwise start without credentials.
- **The trust policy pins `aws:SourceAccount`.** The same confused-deputy guard as on other service roles:
  only the EKS service acting for this account can use the role.
- **The role goes through [`iam-role`](../iam-role/).** A boundary is mandatory, like every role the platform
  creates. A caller can bring its own role with `pod_identity_role_arn` instead.
- **No customer-managed key for volumes here.** `AmazonEBSCSIDriverPolicy` covers the default `aws/ebs` key
  only. Encrypting volumes with your own key needs an extra KMS policy on the role; that is a follow-up.
- **Cost.** Add-ons themselves are free. Their pods use node CPU and memory, so on small nodes lower the
  replica counts through `configuration_values`.

## Testing

- **Unit tests (mock provider, plan):** one resource per entry with the pinned version and cluster name,
  `OVERWRITE` defaults, standard tags, no role without the EBS driver, a boundary-protected role plus a Pod
  Identity association for the driver, a caller-supplied role replacing the created one, configuration values
  passed through, the driver refusing to plan without the agent, and `expect_failures` runs for an unpinned
  version, a partial version, an empty map, a bad conflict policy, non-JSON configuration, a bad role ARN and
  a bad cluster name.
- **No Moto test.** Moto does not implement the EKS add-on API (`CreateAddon`), so there is nothing to apply
  against. The live drill (`live/stacks/m3`) installs all five add-ons into a real cluster, which covers it.
