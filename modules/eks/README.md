# eks

**EKS** (Elastic Kubernetes Service) is AWS's managed Kubernetes. AWS runs the **control plane**: the API
server you talk to with `kubectl`, and **etcd**, the database that holds every object in the cluster. You run
the **worker nodes** that host your containers (added in M3.3). This module creates the control plane and the
things around it that must be right from day one:

| Setting | Value | Why |
|---------|-------|-----|
| API endpoint | private; public is an opt-in limited to CIDRs you list | The Kubernetes API is the cluster's front door. Unless someone needs it from outside the VPC, it should not exist on the internet. |
| Secrets encryption | your KMS key (envelope encryption) | Kubernetes Secrets are only base64-encoded in etcd. The key adds real encryption and an audit trail. |
| Control-plane logs | all five types to an encrypted log group, 1 year | The `audit` log records who did what to the cluster. Without it you can't investigate anything. |
| Authentication mode | `API` (access entries only) | Access is granted with an AWS API you can put in Terraform, not by hand-editing the old `aws-auth` ConfigMap inside the cluster. |
| Creator admin rights | off | The identity that ran `apply` gets no invisible `cluster-admin`; every administrator is listed in `access_entries`. |
| Kubernetes version | pinned by variable | Upgrades happen when you change the value, one minor version at a time. |

Names and tags come from the [`labels`](../labels/) module: the cluster is `<project>-<environment>-<name>`
and its IAM role goes through [`iam-role`](../iam-role/), so it must carry a permissions boundary.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | n/a (required) | Passed to `labels`. |
| `environment` | `string` | n/a (required) | `dev`, `staging`, `prod` or `live`. |
| `owner` | `string` | n/a (required) | Owner tag value. |
| `name` | `string` | `"eks"` | Component name; cluster is `<project>-<environment>-<name>`. |
| `kubernetes_version` | `string` | `"1.35"` | Control-plane minor version (`1.NN`, no patch). |
| `subnet_ids` | `list(string)` | n/a (required) | At least two subnets in different AZs; use `modules/vpc` output `eks_subnet_ids`. |
| `additional_security_group_ids` | `list(string)` | `[]` | Extra security groups on the control-plane network interfaces. |
| `service_ipv4_cidr` | `string` | `null` | Range for Service (ClusterIP) addresses; must not overlap the VPC. |
| `endpoint_public_access` | `bool` | `false` | Also expose the API server to the internet. |
| `public_access_cidrs` | `list(string)` | `[]` | Allowed sources for the public endpoint. Required when it is on; `0.0.0.0/0` is rejected. |
| `kms_key_arn` | `string` | n/a (required) | Key ARN (not alias) for Secrets encryption. |
| `logs_kms_key_arn` | `string` | n/a (required) | Key ARN for the log group; its policy must allow CloudWatch Logs. May equal `kms_key_arn`. |
| `enabled_log_types` | `list(string)` | all five | Must include `audit`. |
| `log_retention_days` | `number` | `365` | A value CloudWatch accepts. |
| `permissions_boundary` | `string` | `null` | Boundary policy ARN for the cluster role. Effectively required. |
| `access_entries` | `map(object)` | `{}` | Key to `{ principal_arn, policy_arn, namespaces = [] }`. |

## Outputs

| Name | Description |
|------|-------------|
| `cluster_name` | `<project>-<environment>-<name>`. |
| `cluster_arn` | Cluster ARN. |
| `cluster_endpoint` | API server URL. |
| `cluster_certificate_authority_data` | Base64 CA certificate clients need to trust the endpoint. |
| `cluster_version` | Kubernetes version running. |
| `cluster_security_group_id` | The security group EKS created; node groups use it. |
| `oidc_issuer_url` | OIDC issuer, for IAM roles for service accounts (IRSA) later. |
| `cluster_role_arn` | The control-plane IAM role. |
| `log_group_name` | `/aws/eks/<cluster>/cluster`. |

## Example

```hcl
module "kms_eks" {
  source = "../../modules/kms"

  project     = "platform"
  environment = "dev"
  owner       = "platform-team"
  purpose     = "eks"
  description = "Encrypts Kubernetes secrets and control-plane logs"

  service_grants = {
    CloudWatchLogs = { service = "logs.us-east-1.amazonaws.com" }
  }
}

module "eks" {
  source = "../../modules/eks"

  project              = "platform"
  environment          = "dev"
  owner                = "platform-team"
  subnet_ids           = module.vpc.eks_subnet_ids
  kms_key_arn          = module.kms_eks.key_arn
  logs_kms_key_arn     = module.kms_eks.key_arn
  permissions_boundary = module.boundary.policy_arn

  access_entries = {
    admins = {
      principal_arn = "arn:aws:iam::123456789012:role/platform-admins"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    }
  }
}
```

## Why it's built this way

- **Private endpoint, public as an explicit opt-in.** The module always enables private access. Turning on
  the public endpoint requires CIDRs, and `0.0.0.0/0` is rejected by a `validation` block, so the lazy
  option isn't available. Private-only means you need a route into the VPC (VPN, bastion, CI runner in the
  VPC) to reach `kubectl`; that is the trade-off.
- **Access entries, `API` mode, no creator admin.** The old way (`aws-auth` ConfigMap) is edited inside the
  cluster, so a typo can lock everyone out and Terraform can't see it. Access entries live in the AWS API.
  Because the creator gets no hidden admin rights, an empty `access_entries` makes a cluster nobody can use;
  that is deliberate, and it's visible in the plan. Pass at least one admin.
- **Two keys' worth of inputs, one key allowed.** Secrets and logs take separate variables so they can be
  split later, but one key may serve both. The key must let EKS and CloudWatch Logs use it: add a
  `service_grants` entry for `logs.<region>.amazonaws.com` in `modules/kms`.
- **The module makes the log group.** If it doesn't, EKS creates one with no expiry and no key.
  `depends_on` makes sure it exists before the cluster starts writing.
- **Cost.** The control plane bills about $0.10 per hour (roughly $73 a month) whether or not it has nodes.
  Interface endpoints, NAT and nodes cost extra. Drill stacks destroy it within minutes.
- **Not in this module:** node groups (M3.3), add-ons (M3.4), Pod Identity (M3.5), the network (`modules/vpc`).

## Tests

- `tests/unit.tftest.hcl` (mock provider, plan): private-by-default endpoint, KMS Secrets encryption, all log
  types, `API` auth mode, log group name and retention, public opt-in, access entries and their scope, the
  boundary on the role, and every `validation` block rejecting bad input.
- `tests/integration.tftest.hcl` (Moto, apply): a real KMS key from `modules/kms`, then the cluster, role and
  log group, reading back what Moto stored. **Moto limits:** it has no access-entry API, so access entries
  are covered by unit tests only; and it doesn't load AWS-managed IAM policies, so the attachment of
  `AmazonEKSClusterPolicy` is overridden in that test.
