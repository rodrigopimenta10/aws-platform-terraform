# eks-controller-policies

IAM policies for two controllers that run **inside** a cluster but act on **AWS**:

- the **AWS Load Balancer Controller** reads Kubernetes `Ingress` and `Service` objects and creates the
  matching Application and Network Load Balancers, target groups, listeners and security groups;
- **Karpenter** watches for pods that cannot be scheduled and launches (and later terminates) EC2 instances
  that fit them, then joins them to the cluster.

A controller is just a pod. To call AWS it needs a role, and the role needs a policy that says exactly what
it may do. Both policies are long and easy to get wrong, so this module owns them once, tested, and hands
consumers a **managed policy** (a standalone IAM policy that many roles can attach) plus the JSON.

The module creates policies only. It creates no role, so a permissions boundary does not apply here: a policy
grants nothing until a role carries it. Give the controller its role with
[`eks-pod-identity`](../eks-pod-identity/) (namespace `kube-system`, service account
`aws-load-balancer-controller` or `karpenter`), where the boundary is enforced.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project`, `environment`, `owner` | `string` | n/a | Passed to [`labels`](../labels/) for names and tags. |
| `cluster_name` | `string` | n/a | EKS cluster the controllers serve. Karpenter's permissions are tied to it. |
| `region` | `string` | n/a | Cluster region. Karpenter's EC2 and EKS permissions are limited to it. |
| `create_lb_controller_policy` | `bool` | `true` | Create the Load Balancer Controller policy. |
| `create_karpenter_policy` | `bool` | `true` | Create the Karpenter policy. Requires `karpenter_node_role_arn`. |
| `karpenter_node_role_arn` | `string` | `null` | The one role Karpenter may pass to the nodes it launches. |
| `karpenter_interruption_queue_arn` | `string` | `null` | SQS queue of Spot interruption events. `null` leaves that statement out. |
| `tags` | `map(string)` | `{}` | Extra tags. |

## Outputs

| Name | Description |
|------|-------------|
| `lb_controller_policy_arn` | ARN of the managed policy, `null` when not created. |
| `lb_controller_policy_json` | The document, for inlining. |
| `karpenter_policy_arn` | ARN of the managed policy, `null` when not created. |
| `karpenter_policy_json` | The document, for inlining. |

## Example

```hcl
module "controller_policies" {
  source = "../../modules/eks-controller-policies"

  project                 = "platform"
  environment             = "dev"
  owner                   = "platform-team"
  cluster_name            = module.eks.cluster_name
  region                  = "eu-west-1"
  karpenter_node_role_arn = module.nodes.node_role_arn
}

module "lb_controller_identity" {
  source = "../../modules/eks-pod-identity"

  project              = "platform"
  environment          = "dev"
  owner                = "platform-team"
  name                 = "lb-controller"
  cluster_name         = module.eks.cluster_name
  namespace            = "kube-system"
  service_account      = "aws-load-balancer-controller"
  permissions_boundary = module.boundary.policy_arn
  managed_policy_arns  = [module.controller_policies.lb_controller_policy_arn]
}
```

Planning caveat: `iam-role` attaches managed policies with a `for_each` over their ARNs. When the policy is
created in the same apply, its ARN is unknown at plan time and Terraform refuses. Either create the policies
first (`terraform apply -target=module.controller_policies`), or pass the document as `policy_json` instead,
as the [`m3` drill stack](../../live/stacks/m3/main.tf) does.

## Why it's built this way

- **Policies, not roles.** The role is a different decision (which cluster, namespace and service account),
  and it is where the permissions boundary belongs. Keeping policies separate lets one policy serve several
  clusters' roles.
- **Scoped by tag.** The Load Balancer Controller tags what it creates (`elbv2.k8s.aws/cluster`) and may only
  change or delete resources carrying that tag. Karpenter does the same with
  `kubernetes.io/cluster/<name> = owned`. If a controller is compromised it can damage what it made, not
  every load balancer or instance in the account.
- **`iam:PassRole` is pinned.** Launching an instance with a role requires `PassRole`. Karpenter may pass
  exactly the node role, and only to EC2. With `Resource = "*"` it could launch an instance wearing an admin
  role and use that instead: a classic privilege escalation.
- **Where `*` remains, and why.** `Describe*` calls (and `pricing:GetProducts`) have no resource-level
  permissions in IAM, so their `Resource` must be `*`. Mutating statements avoid it. No action is a wildcard.
  The four checkov skips on each policy say the same thing inline.
- **Region pinned.** Karpenter's EC2 resources and Describe calls name the cluster's region, so a bug or a
  stolen credential cannot launch instances elsewhere.
- **Written out, not downloaded.** The documents follow the projects' reference policies, as Terraform
  `jsonencode` locals, so they are reviewable in a diff, testable offline and do not change when a URL does.
  Re-check them against the upstream policy when you upgrade a controller's major version.
- **Size.** A managed policy may hold at most 6,144 characters. Both fit; a unit test fails first if an edit
  pushes one over.
- **Cost.** Free.

## Testing

Unit tests (mock provider) check names and tags, the size limit, that every mutating Load Balancer Controller
statement is conditioned on the cluster tag, that no action is a wildcard, that Karpenter's delete and read
statements are tied to the cluster and region, that `PassRole` names one role and only EC2, the optional
queue statement, switching policies off, the precondition when no node role is given, and every validation.
The integration test applies both policies to Moto, which parses the documents and rejects malformed JSON.
Moto does not evaluate policies, so what a policy *allows* is checked by reading the document in the unit
tests; the `m3` live drill proves real IAM accepts both.
