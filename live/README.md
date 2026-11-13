# live/

Real applies of this repo's modules into a real AWS account, unattended: after CI passes on a push to
`main`, [`live-drill.yml`](../.github/workflows/live-drill.yml) applies every stack the push changed,
captures evidence and console screenshots, destroys it, proves nothing is left, and commits a report to
[`docs/live/`](../docs/live/). Resources use the `live` environment (`platform-live-*` names,
`environment = live` tag, [ADR 0002](../docs/adr/0002-naming-and-tagging.md)), so anything tagged `live`
that outlives a drill is a leak.

| Path | What it is |
|---|---|
| [`bootstrap/`](bootstrap/) | One-time stack an admin applies by hand: state bucket, GitHub OIDC provider, the `platform-live-drill` role, its guardrails and boundary, and the budget that can switch it off. |
| `stacks/<stack>/` | One root module per drill. Empty `backend "s3" {}` filled by the workflow; key `live/<stack>/terraform.tfstate`. |
| [`screenshots.yml`](screenshots.yml) | Per stack, the console pages to capture, how to get there, and what each must prove. |
| [`plan-gate.sh`](plan-gate.sh) | Refuses a plan before apply: forbidden resource types, big instances, many nodes or NAT gateways. |
| [`evidence.sh`](evidence.sh) | Read-only `describe` calls saved as JSON with the account ID replaced by `<ACCOUNT_ID>`. |
| [`console-shots.mjs`](console-shots.mjs) | Headless Chromium on the runner, signed in through the AWS federation endpoint as the drill role; 2x screenshots with the account ID removed. |
| [`summary.sh`](summary.sh), [`report.sh`](report.sh) | The run's job summary, and the committed report. |
| [`verify-destroyed.sh`](verify-destroyed.sh) | After destroy: fails if anything tagged `live-stack=<stack>` still exists. |

## How a drill runs

```
routine pushes to main ─▶ ci ─▶ live-drill: select (which stacks changed since the last drill)
                                   └▶ drill (one stack at a time, one job each, aws-live environment):
                                        OIDC ─▶ 1-hour role credentials
                                        plan ─▶ plan-gate ─▶ apply ─▶ evidence ─▶ console screenshots
                                        destroy (always) ─▶ verify
                                   └▶ publish: report + screenshots committed to docs/live/ (no AWS access)
live-reaper (hourly): destroys any stack whose state is not empty
```

A stack is drilled when its own folder, `screenshots.yml`, or any module it uses changed since the last
successful drill. Start one by hand from the Actions tab or with `/live-drill` in local Claude Code.

## Why it's safe without a human click

No agent ever holds AWS credentials. Only a GitHub Actions job in the `aws-live` environment, running on
this repository's `main`, can assume the role. On top of that:

1. **Trigger:** only a successful CI run of a push to this repo's `main`. Fork and pull-request runs are
   refused, including a fork's PR from a branch named `main`.
2. **Protected paths:** a push that changes the drill machinery (`live/bootstrap/`, `live/*.sh`,
   `live/*.mjs`, `.github/`, `scripts/check-live-stacks.sh`, `.tool-versions`) is refused, so a bad commit
   can't loosen the limits it runs under. Rodrigo checks such changes and starts a drill by hand.
3. **Plan gate:** at most 150 resources, 1 NAT gateway, 1 EKS cluster, 3 nodes in total, `t3`/`t3a`/`t4g` up
   to `large`, interface endpoints in at most 2 AZs, and no RDS, OpenSearch, SageMaker, dedicated hosts,
   reservations, spot fleets or transit gateways.
4. **IAM, in `bootstrap/`:**
   - only the services drills use (EC2, EKS, IAM, S3, KMS, Logs, Lambda, API Gateway, ...); everything
     else is denied, including Service Quotas, Support, Savings Plans and the Marketplace;
   - `us-east-1` only; small instance types only; no IAM users, access keys or passwords;
   - every role a drill creates must carry the permissions boundary, which applies the same limits, so a
     drill can't make itself a more powerful role;
   - the role can't change itself, its trust, the boundary, the OIDC provider, the state bucket or the
     guard budget.
5. **Spend stop:** the `platform-live-drill-guard` budget attaches a deny-all policy to the role when the
   month passes $15. Billing data lags by hours, so this is the last line, not the first.
6. **Account limits:** a new account can run 5 vCPUs of on-demand instances and 0 GPU instances; the
   role can't ask for more.
7. **Cleanup:** destroy runs in the same job whatever happened before it, one drill runs at a time, and
   the reaper retries hourly.

What it does not stop: a drill that is cheap per hour but left behind for days if destroy keeps failing
and nobody reads the failure. The workflow fails loudly, the report says "Destroy verified: NO", and the
budget emails start at $7.50.

## What it costs

A VPC drill is free. NAT gateways ($0.045 an hour), interface endpoints ($0.01 per AZ-hour) and an EKS
control plane ($0.10 an hour) cost cents for the 10 to 40 minutes a drill lasts. Runner minutes are free
for a public repository. The standing cost is the state bucket's KMS key, about $1 a month.

## Adding a stack

1. `live/stacks/<stack>/` with `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` (empty
   `backend "s3" {}`), `README.md`, `tests/*.tftest.hcl` and a lock file. Cheapest settings,
   `force_destroy = true`, the shortest KMS deletion window, and
   `extra_tags = { "live-stack" = "<stack>" }` on the labels module that feeds the provider's
   `default_tags`. Modules that create IAM roles get `permissions_boundary = var.permissions_boundary_arn`.
2. Its entry in `live/screenshots.yml`.
3. Optionally a `case` in `evidence.sh` (a protected file: Rodrigo adds it).

`scripts/check.sh` fails until 1 and 2 agree.
