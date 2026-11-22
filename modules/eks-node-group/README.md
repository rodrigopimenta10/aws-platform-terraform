# eks-node-group

An EKS cluster's **control plane** (see [`eks`](../eks/)) only stores desired state. The **worker nodes** are
the EC2 machines that actually run your containers. A **managed node group** is a set of those machines that
EKS creates, registers with the cluster, drains before replacing, and rolls to a newer image on request. EKS
runs an Auto Scaling group (AWS's "keep N instances running" service) for you behind it.

This module creates one shared node IAM role plus any number of node groups, each with its own launch
template, so on-demand and spot groups can sit side by side.

| Setting | Value | Why |
|---------|-------|-----|
| Instance metadata | IMDSv2 required, hop limit 1 | Every instance can read its own IAM credentials from a link-local address (IMDS). IMDSv1 answers any plain request, so an SSRF bug in an app can leak them. IMDSv2 needs a session token. Hop limit 1 also keeps pods, one network hop away, from reaching it. |
| Root volume | encrypted gp3, your key or `aws/ebs` | Disks are never left in the clear; gp3 is cheaper than gp2 at the same speed. |
| Node role | exactly three AWS-managed policies, behind the boundary | `AmazonEKSWorkerNodePolicy` (join the cluster), `AmazonEKS_CNI_Policy` (pod networking) and `AmazonEC2ContainerRegistryPullOnly` (pull images from ECR, no push). Anything more is opt-in through `additional_node_policy_arns`. |
| Spot groups | at least two instance types | Spot is spare EC2 capacity at a discount that AWS can take back. One type is one capacity pool, so one reclaim can remove every node. |
| `desired_size` | ignored after creation | A cluster autoscaler or Karpenter changes it at run time; Terraform must not undo that. |
| Image | none named | EKS picks the optimized image for `ami_type` and the cluster's Kubernetes version. |

Names and tags come from [`labels`](../labels/): the role is `<project>-<environment>-<name>-role` and each
group `<project>-<environment>-<name>-<key>`. The role goes through [`iam-role`](../iam-role/), so it must carry
a permissions boundary.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | n/a (required) | Passed to `labels`. |
| `environment` | `string` | n/a (required) | `dev`, `staging`, `prod` or `live`. |
| `owner` | `string` | n/a (required) | Owner tag value. |
| `name` | `string` | `"nodes"` | Component name used in the role and group names. |
| `cluster_name` | `string` | n/a (required) | Cluster to join (`eks` output `cluster_name`). |
| `subnet_ids` | `list(string)` | n/a (required) | At least two private subnets in different AZs. |
| `permissions_boundary` | `string` | `null` | Boundary policy ARN for the node role. Effectively required. |
| `ebs_kms_key_arn` | `string` | `null` | Key ARN for root volumes; null uses `aws/ebs`. |
| `metadata_hop_limit` | `number` | `1` | IMDS hop limit, 1 or 2. |
| `additional_node_policy_arns` | `list(string)` | `[]` | Extra managed policies for the node role. |
| `node_groups` | `map(object)` | n/a (required) | Key to `{ capacity_type, instance_types, ami_type, min_size, max_size, desired_size, disk_size_gib, max_unavailable, labels, taints }`. Every field is optional; see `variables.tf` for defaults and rules. |

## Outputs

| Name | Description |
|------|-------------|
| `node_role_arn` | ARN of the role every node uses. |
| `node_role_name` | Name of that role. |
| `node_group_names` | Map of group key to node group name. |
| `node_group_arns` | Map of group key to node group ARN. |
| `node_group_statuses` | Map of group key to status. |
| `launch_template_ids` | Map of group key to launch template ID. |

## Example

```hcl
module "nodes" {
  source = "../../modules/eks-node-group"

  project              = "platform"
  environment          = "dev"
  owner                = "platform-team"
  cluster_name         = module.eks.cluster_name
  subnet_ids           = module.vpc.eks_subnet_ids
  permissions_boundary = module.boundary.policy_arn
  ebs_kms_key_arn      = module.kms_ebs.key_arn

  node_groups = {
    system = {
      instance_types = ["t3.large"]
      min_size       = 2
      desired_size   = 2
      max_size       = 4
      labels         = { workload = "system" }
    }

    batch = {
      capacity_type  = "SPOT"
      instance_types = ["m5.large", "m5a.large", "m6i.large"]
      min_size       = 0
      desired_size   = 0
      max_size       = 10
      labels         = { workload = "batch" }
      taints         = [{ key = "spot", value = "true", effect = "NO_SCHEDULE" }]
    }
  }
}
```

## Why it's built this way

- **Taints on spot, labels on everything.** A *label* lets a pod ask for a node (`nodeSelector`); a *taint*
  keeps pods away unless they say they tolerate it. Spot nodes can vanish with two minutes' notice, so they
  are tainted and only interruption-tolerant work opts in.
- **One launch template per group, no image in it.** A launch template is the recipe for an instance. Naming
  no image keeps EKS in charge of the AMI, which is what makes managed updates work. The cost is that custom
  user data and custom AMIs are out of scope here.
- **Hop limit 1 is the default, not a rule.** Some add-ons that predate Pod Identity read node credentials.
  Raise it per cluster, knowingly, and move those workloads to Pod Identity (M3.5).
- **The role is shared.** All groups need the same three policies. Separate roles would only add boundaries to
  maintain; split them if two groups ever need different permissions.
- **Cost.** Nodes are the real money in a cluster. The default is one `t3.medium`; scale-to-zero spot groups cost nothing idle.

## Testing

- **Unit tests (mock provider, plan):** defaults and naming, IMDSv2 required, hop limit, encrypted gp3 volume
  with the optional key, on-demand and spot groups together with labels and taints, and eight `expect_failures`
  runs (spot with one type, bad capacity type, `min_size` above `desired_size`, bad taint effect, reserved label
  prefix, no groups, one subnet, bad hop limit, non-ARN policy).
- **Moto test (apply):** builds a key and a cluster with [`kms`](../kms/) and [`eks`](../eks/), then two node
  groups, and reads back names, capacity types, scaling, labels, the taint and the launch template's stored
  metadata options and encrypted volume. Moto stores these records but starts no instances, so it cannot show
  nodes joining; the live drill does. Moto also does not load AWS-managed IAM policies, so the three
  node-policy attachments are overridden in that test, and a root module cannot see a child module's
  resources, so nothing asserts on them.
