# live/

Everything the [live drill](../README.md#live-drills) needs: short-lived, human-approved applies of this
repo's modules into a real AWS account, with evidence, then a verified destroy. Resources here use the
`live` environment (`platform-live-*` names, `environment = live` tag, see
[ADR 0002](../docs/adr/0002-naming-and-tagging.md)), so anything tagged `live` that outlives a drill is a leak.

| Path | What it is |
|---|---|
| [`bootstrap/`](bootstrap/) | One-time stack an admin applies by hand: state bucket, GitHub OIDC provider, the `platform-live-drill` role and its guardrails. Agents never edit it. |
| `stacks/<stack>/` | One root module per drill. Empty `backend "s3" {}` filled by the workflow; key `live/<stack>/terraform.tfstate`. |
| [`screenshots.yml`](screenshots.yml) | Per stack, the console pages to capture and what each must prove. |
| [`evidence.sh`](evidence.sh) | Read-only `describe` calls saved as JSON with the account ID replaced by `<ACCOUNT_ID>`. |
| [`summary.sh`](summary.sh) | The apply job's summary: resources by type, console links. |
| [`verify-destroyed.sh`](verify-destroyed.sh) | After destroy: fails if anything tagged `managed-by=terraform`, `live-stack=<stack>` remains. |

The workflows are [`live-drill.yml`](../.github/workflows/live-drill.yml) and
[`live-reaper.yml`](../.github/workflows/live-reaper.yml); the local command is
[`.claude/commands/live-drill.md`](../.claude/commands/live-drill.md).

## Adding a stack

1. `live/stacks/<stack>/` with `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` (empty
   `backend "s3" {}`), `README.md`, `tests/*.tftest.hcl` and a lock file. Use the cheapest settings,
   `force_destroy = true` and the shortest KMS deletion window where they exist, and pass
   `extra_tags = { "live-stack" = "<stack>" }` to the labels module that feeds the provider's
   `default_tags`.
2. Its entry in `live/screenshots.yml`.
3. Its name in the `stack` options of `live-drill.yml`.
4. Optionally a `case` in `evidence.sh` for service-specific describes.

`scripts/check.sh` fails until 1, 2 and 3 agree.
