# aws-platform-terraform

A production-style AWS platform in Terraform: networking, identity, EKS, serverless, observability and
CI/CD, built as reusable modules with tests.

**Status:** M1.1 done (`modules/vpc`). Roadmap item M1.2 is next. See [ROADMAP.md](ROADMAP.md).

## What's in it (when the roadmap is done)

| Area | AWS services | Folder |
|---|---|---|
| Foundations | S3 remote state with native locking, KMS | `modules/state-backend`, `modules/labels` |
| Network | VPC across 3 AZs, NAT, VPC endpoints, flow logs | `modules/vpc` |
| Identity and security | IAM, GitHub Actions OIDC, permission boundaries, KMS | `modules/github-oidc`, `modules/kms` |
| Containers | ECR, EKS with managed node groups, add-ons, Pod Identity | `modules/ecr`, `modules/eks` |
| Kubernetes platform | Helm, Argo CD, AWS Load Balancer Controller | `platform/` |
| Serverless and data | Lambda, API Gateway, SQS with DLQ, DynamoDB | `modules/api-lambda`, `modules/queue`, `modules/table` |
| Observability and cost | CloudWatch dashboards and alarms, SLO burn-rate alerts, Budgets | `modules/observability` |
| CI/CD | GitHub Actions: checks on every push, `plan` via OIDC | `.github/workflows` |

## How it's tested, without an AWS account
Every module has `terraform test` files:
- **unit tests** with a mocked AWS provider (no network), and
- **integration tests** that really create and destroy resources against [Moto](https://github.com/getmoto/moto),
  a local AWS emulator.

CI also runs `terraform fmt`, `validate`, `tflint` (with the AWS ruleset) and `checkov` security scans.
Nothing here touches a real AWS account. See [ADR 0001](docs/adr/0001-test-offline-with-moto.md).

```bash
scripts/bootstrap.sh   # installs the pinned toolchain into ~/.local/aws-platform-tools
scripts/check.sh       # everything CI runs
```

## How this repo is built
I'm building this with [Claude Code](https://claude.com/claude-code) as a structured way to learn
AWS platform engineering. A scheduled cloud run takes the next item from the [roadmap](ROADMAP.md),
builds it with tests and pushes it once every check passes. It also writes a learning note in
[`docs/daily/`](docs/daily/) explaining what was built, why, the trade-offs, an exercise and interview-style
questions, so I can learn the material from each step. Commits written by Claude carry a
`Co-Authored-By: Claude` trailer.

## Layout
```
modules/      reusable modules, each with README and tests
envs/dev/     root module that wires the modules together
platform/     Kubernetes manifests and Helm values
docs/adr/     architecture decision records
docs/daily/   daily learning notes
docs/milestones/  one recap per finished milestone, with steps to apply it in a real account
scripts/      bootstrap and check scripts
```

## License
MIT
