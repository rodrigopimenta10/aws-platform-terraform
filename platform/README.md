# platform/

Cluster add-ons installed with Helm *after* the EKS cluster from `modules/eks` exists. Terraform builds
the cluster and the IAM roles; this folder holds the Kubernetes side: the configuration (Helm **values**)
for three add-ons every cluster needs.

**Helm** is a package manager for Kubernetes. A **chart** is a package (templates for Deployments,
Services and so on); a **values file** is the set of settings you give the templates.

| Add-on | What it does | AWS permissions |
| --- | --- | --- |
| [aws-load-balancer-controller](aws-load-balancer-controller/values.yaml) | Turns `Ingress` and `Service` objects into Application and Network Load Balancers | Yes: policy from [`modules/eks-controller-policies`](../modules/eks-controller-policies/) |
| [metrics-server](metrics-server/values.yaml) | CPU and memory numbers for `kubectl top` and autoscaling | No |
| [external-dns](external-dns/values.yaml) | Writes DNS records in Route 53 for your Ingress hostnames | Yes: Route 53 change permissions on the zones it manages |

## Layout
```
platform/
  charts.env        pinned chart versions and repositories (the one place to bump)
  <addon>/values.yaml   production-style settings
  kind/<addon>.yaml     overrides for a local kind cluster (no AWS)
  kind/cluster.yaml     the kind cluster itself
  smoke-test.sh     create kind cluster, install all three charts, check, delete
  tests/lint.sh     offline checks, no Docker needed
```

## Run it
```bash
platform/tests/lint.sh      # offline: YAML parses, versions pinned, names match Pod Identity
platform/smoke-test.sh      # needs docker, kind, helm, kubectl; takes a few minutes
KEEP_CLUSTER=1 platform/smoke-test.sh   # keep the cluster afterwards to explore
```
The smoke test exits 2 (not a failure) if a tool is missing. `scripts/check.sh` does not run it: the
agent sandbox has no Docker daemon, and CI should not depend on pulling charts from the internet.

## On a real cluster
```bash
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version "$(. platform/charts.env; echo $LBC_CHART_VERSION)" -n kube-system \
  -f platform/aws-load-balancer-controller/values.yaml \
  --set clusterName=<cluster> --set region=<region> --set vpcId=<vpc-id>
```
Create the Pod Identity associations first (`modules/eks-pod-identity`) with namespace and service
account matching `serviceAccount.name` in each values file; `tests/lint.sh` checks the names.

## Why it's built this way
- **Pinned versions in one file.** An unpinned chart changes the cluster without a commit. `charts.env`
  is read by both scripts so they cannot drift apart.
- **Base values + kind overlay.** The base file is what you would run on EKS. The overlay changes only
  what kind forces: one replica, fake AWS inputs, `--kubelet-insecure-tls` for metrics-server, and the
  in-memory provider for external-dns. Helm merges `-f a -f b` with the later file winning.
- **Per-cluster inputs are not committed.** `clusterName`, `vpcId` and `txtOwnerId` default to empty so a
  forgotten `--set` fails at install time rather than managing the wrong cluster.
- **No role annotations.** With EKS Pod Identity the association, not the ServiceAccount, grants the role
  (ADR 0005). IRSA would need an `eks.amazonaws.com/role-arn` annotation.
- **`upsert-only` for external-dns.** It never deletes DNS records, so a mistaken manifest cannot take a
  hostname offline.

## What the smoke test does not prove
kind has no AWS: the load balancer controller starts but cannot create a load balancer, and external-dns
runs against an in-memory provider. The test shows the charts render, the pods start and the values
files are accepted by the pinned chart versions. IAM and Route 53 behaviour are only proved in a real
account.
