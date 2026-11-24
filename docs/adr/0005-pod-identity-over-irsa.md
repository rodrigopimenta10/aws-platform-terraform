# ADR 0005: Pod Identity for workload IAM, not IRSA

- **Status:** accepted
- **Date:** 2026-11-23

## Context
A pod that calls AWS needs credentials, and they should be temporary, specific to that workload and not
shared with its neighbours. EKS has two ways to do this.

**IRSA** (IAM Roles for Service Accounts) uses **OIDC** (OpenID Connect, a standard for signed identity
tokens). The cluster publishes an OIDC issuer URL, you register it in IAM as an identity provider, and the
role's trust policy says "accept tokens from that issuer whose subject is
`system:serviceaccount:<namespace>:<name>`". The service account carries an annotation naming the role, and
the AWS SDK in the pod exchanges the token for credentials with `sts:AssumeRoleWithWebIdentity`.

**Pod Identity** (2023) moves the link into EKS. An **association** says "this service account in this
namespace of this cluster gets this role". The `eks-pod-identity-agent` add-on, a DaemonSet (one pod per
node), serves credentials to pods on the node. The role trusts the service `pods.eks.amazonaws.com`.

## Options
| | IRSA | Pod Identity |
|---|---|---|
| Per-cluster setup | OIDC provider in IAM | `eks-pod-identity-agent` add-on |
| Trust policy | Names the provider URL, namespace and service account, so it differs per cluster | One fixed statement for all clusters |
| Reuse a role across clusters | Edit the trust policy for each cluster | Add an association |
| Link lives in | The role's trust policy plus a service-account annotation | The EKS API |
| Role session tags (cluster, namespace, pod) | No | Yes, usable in policy conditions |
| Works on Fargate and outside EKS (EKS Anywhere) | Yes | No for Fargate; needs a node agent |
| IAM role trust policy size limit | Hit when one role serves many clusters | Not a factor |
| SDK support | Old and universal | Needs a reasonably recent SDK |

## Decision
New workloads use **Pod Identity**: [`modules/eks-pod-identity`](../../modules/eks-pod-identity/) creates the
role and association, and [`modules/eks-addons`](../../modules/eks-addons/) installs the agent. Fargate pods
and anything on an SDK too old to know the credential endpoint are the cases for IRSA, and no module for it
exists until a workload needs it.

## Consequences
- No OIDC provider to create, rotate or leak into trust policies, and the trust policy is the same everywhere.
- Moving or cloning a workload is an association change, with no IAM edit.
- The agent add-on becomes a dependency of every workload using this: without it nothing is delivered and the
  failure looks like "no credentials" inside the pod.
- Credentials come from a node-local endpoint, so a pod on the host network or a node role with broad rights
  weakens the isolation. Keep the node group's metadata hop limit at 1 so pods cannot reach the node's own credentials (`modules/eks-node-group` exposes `metadata_hop_limit`).
- Roles cannot be shared with IRSA-style trust without also trusting the OIDC provider. Mixing both for one
  role is possible but not done here.
