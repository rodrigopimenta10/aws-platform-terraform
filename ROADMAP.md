# Roadmap

The daily run works through this list from top to bottom, one item per run. If an item is small (S) and
time is left, it may also take the next S item. Sizes: **S** is about one commit, **M** two or three,
**L** four to six.

Every item is done only when:
- it has a `terraform test` file: unit tests that use `mock_provider`, plus integration tests applied
  against Moto where Moto supports the resources,
- `scripts/check.sh` passes (fmt, validate, tests, tflint, checkov),
- the module has a README with inputs, outputs, an example and a "Why it's built this way" section,
- that day's learning note is in `docs/daily/`.

If Moto can't emulate a resource, cover it with mock-provider unit tests only and say so in the module README.

## M0: Foundations
- [x] **M0.1** (S) Shared conventions: `modules/labels` module that builds names and the standard tag map (`project`, `environment`, `owner`, `managed-by = terraform`). ADR 0002 on naming and tagging.
- [x] **M0.2** (M) Remote state: `modules/state-backend`, an S3 bucket with versioning, SSE-KMS, public access fully blocked, TLS-only bucket policy, and lifecycle on noncurrent versions. Uses S3 native locking (`use_lockfile`), with no DynamoDB table. ADR 0003 explaining why.
- [x] **M0.3** (S) `envs/dev` root module wired to `labels` and the provider, with a commented-out S3 backend block and a README on how to bootstrap state.

## M1: Network
- [x] **M1.1** (L) `modules/vpc`: VPC across 3 AZs with public, private and isolated subnet tiers, sized by variables using `cidrsubnet`. Outputs ready for EKS.
- [x] **M1.2** (M) NAT strategy: `single_nat_gateway` vs one per AZ, controlled by a variable. ADR 0004 on cost vs availability, with rough monthly numbers.
- [x] **M1.3** (M) VPC endpoints: an S3 gateway endpoint, plus interface endpoints for ECR (api, dkr), STS and CloudWatch Logs, each with its own security group.
- [ ] **M1.4** (S) VPC flow logs to CloudWatch Logs with a retention variable and a KMS key.
- [ ] **M1.5** (S) Wire the VPC into `envs/dev` and add an integration test that asserts subnet counts and route tables.

## M2: Identity and security
- [ ] **M2.1** (M) `modules/kms`: customer-managed keys with rotation and a least-privilege key policy, reused by the other modules.
- [ ] **M2.2** (L) `modules/github-oidc`: GitHub Actions OIDC provider plus a deploy role whose trust policy is scoped to this repo and branch. Explain in the README why OIDC beats long-lived keys.
  - Note: `live/bootstrap` already creates the GitHub OIDC provider (`token.actions.githubusercontent.com`) in the real account, and AWS allows only one provider per URL. When `modules/github-oidc` is wired into a root module that targets that account, take the existing provider over with `import` (and `moved` blocks if it moves out of `live/bootstrap`) rather than creating a second one. Don't edit `live/bootstrap` itself: the daily run may not touch it, so leave a note for Rodrigo.
- [ ] **M2.3** (M) IAM permission boundary for roles the platform creates, plus a test that a role without the boundary is rejected (a `precondition` or check block).
- [ ] **M2.4** (S) Account baseline: `aws_ebs_encryption_by_default`, S3 account-level public access block, IAM password policy.

## M3: Containers
- [ ] **M3.1** (M) `modules/ecr`: repositories with scan-on-push, immutable tags, KMS encryption and a lifecycle policy that keeps the last N images.
- [ ] **M3.2** (L) `modules/eks`: cluster with a private API endpoint (public optional, CIDR-restricted), control-plane logging, secrets encryption with KMS, and the access-entries authentication mode.
- [ ] **M3.3** (M) Managed node groups: on-demand and spot groups, launch template with IMDSv2 required, labels and taints.
- [ ] **M3.4** (M) EKS add-ons: vpc-cni, coredns, kube-proxy, ebs-csi-driver, with versions pinned by variable.
- [ ] **M3.5** (M) EKS Pod Identity: an association and role for one example workload. ADR 0005 comparing it with IRSA.
- [ ] **M3.6** (S) IAM policies for the AWS Load Balancer Controller and Karpenter, as a module consumers can attach.

## M4: Kubernetes platform layer
- [ ] **M4.1** (M) `platform/` folder with Helm values for aws-load-balancer-controller, metrics-server and external-dns, plus a `kind` smoke test script that installs the charts into a local cluster with Docker.
- [ ] **M4.2** (M) Argo CD bootstrap: an app-of-apps manifest that points Argo CD at `platform/`, tested on kind.
- [ ] **M4.3** (S) A sample app (nginx or a tiny Go server) with a Dockerfile (multi-stage, non-root), a Kubernetes Deployment, Service and Ingress, and a PodDisruptionBudget.

## M5: Serverless and data
- [ ] **M5.1** (M) `modules/queue`: SQS queue with a dead-letter queue, a redrive policy, KMS and an alarm on DLQ depth.
- [ ] **M5.2** (M) `modules/table`: DynamoDB table with on-demand billing, point-in-time recovery, TTL and KMS.
- [ ] **M5.3** (L) `modules/api-lambda`: Python Lambda behind API Gateway HTTP API, packaged with `archive_file`, with least-privilege IAM, X-Ray tracing and log retention. The Lambda reads and writes the M5.2 table.
- [ ] **M5.4** (S) S3 event notification to SQS, with an integration test that drops an object and checks the message arrives (in Moto).

## M6: Observability and cost
- [ ] **M6.1** (M) CloudWatch dashboard as code for the API, Lambda, SQS and EKS, plus alarms with sensible thresholds and an SNS topic.
- [ ] **M6.2** (S) AWS Budgets: a monthly budget with forecast alerts at 80% and 100%.
- [ ] **M6.3** (M) SLO example: availability SLI for the API from CloudWatch metrics, and a multi-window burn-rate alarm. Explain the math in the README.

## M7: CI/CD and docs
- [ ] **M7.1** (M) Workflow `plan.yml`: on pull requests, `terraform plan` for `envs/dev` using the M2.2 OIDC role. Disabled by default behind a repo variable, `ENABLE_AWS_PLAN`, so it never runs without a real account.
- [ ] **M7.2** (S) Pre-commit config (fmt, tflint, checkov, end-of-file fixer), documented in the README.
- [ ] **M7.3** (M) Architecture diagram in Mermaid in the README, plus `docs/deploy-it-yourself.md`: a free-tier-friendly walkthrough to apply, screenshot and destroy `envs/dev` in a real account, with cost warnings.
- [ ] **M7.4** (S) Runbook: `docs/runbook.md` covering how to rotate KMS, recover state, and respond to the alarms from M6.

## Done
When every box above is ticked, the daily run stops building and writes a final note saying the roadmap is complete.
