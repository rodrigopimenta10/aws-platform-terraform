# aws-platform-terraform

A production-style AWS platform in Terraform: networking, identity, EKS, serverless, observability and
CI/CD, built as reusable modules with tests.

**Status:** M1.2 done (NAT strategy in `modules/vpc`). Roadmap item M1.3 is next. See [ROADMAP.md](ROADMAP.md).

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
None of this touches a real AWS account. See [ADR 0001](docs/adr/0001-test-offline-with-moto.md). The
one exception is the live drill below, and only when I start and approve it.

```bash
scripts/bootstrap.sh   # installs the pinned toolchain into ~/.local/aws-platform-tools
scripts/check.sh       # everything CI runs
```

## Live drills
Tests prove the code; a live drill proves it works in a real account. In local Claude Code:

```bash
claude "/live-drill vpc 15"   # stack from live/stacks/, hold of 15, 30 or 60 minutes
```

- **What happens.** The command checks the AWS identity (an admin user, never root), the budget and CI on
  `main`, then dispatches [`live-drill.yml`](.github/workflows/live-drill.yml). Its apply job assumes the
  `platform-live-drill` role through GitHub OIDC (no AWS keys stored anywhere), applies the stack, saves
  read-only `aws ... describe` output with the account ID redacted, and writes a job summary. During the
  hold Claude takes console screenshots from [`live/screenshots.yml`](live/screenshots.yml) and redacts them.
  The destroy job then destroys the stack and fails loudly unless the state is empty and nothing tagged
  `live-stack=<stack>` is left. It runs even if the apply failed.
- **The approval.** Both jobs run in the `aws-live` GitHub environment: each waits for my approval, and only
  `main` can deploy. That environment is also the only thing AWS trusts to assume the role. The daily
  Claude run never dispatches or approves a drill.
- **What it costs.** The `vpc` stack: $0 (no NAT gateway; VPCs, subnets, route tables and internet gateways
  are free, see [VPC pricing](https://aws.amazon.com/vpc/pricing/)). The one-time
  [`live/bootstrap`](live/bootstrap/) stack (state bucket, OIDC provider, role) costs about $1 a month for
  its KMS key. Later milestone stacks note their own hourly cost.
- **Where results land.** `docs/live/<date>-<stack>.md` with the screenshots and evidence in
  `docs/live/<date>-<stack>/`, committed after I've looked at them.
- **The reaper.** [`live-reaper.yml`](.github/workflows/live-reaper.yml) runs daily at 13:00 UTC and destroys
  any live stack whose state isn't empty. It uses the same environment, so it also waits for my approval;
  the drill's own destroy is the main path, and AWS budget emails are the alarm if something is left.

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
live/         live drill: one-time bootstrap, drillable stacks, evidence and screenshot lists
platform/     Kubernetes manifests and Helm values
docs/adr/     architecture decision records
docs/daily/   daily learning notes
docs/milestones/  one recap per finished milestone, with steps to apply it in a real account
docs/live/    live drill write-ups with redacted screenshots and evidence
scripts/      bootstrap and check scripts
```

## License
MIT
