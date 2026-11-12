# CLAUDE.md

This repo is a learning portfolio: a production-style AWS platform in Terraform, built one roadmap item
at a time by a daily Claude Code cloud run and reviewed by Rodrigo. Agents never apply it to a real AWS
account **except** through the live drill (`.github/workflows/live-drill.yml`), which only runs when
Rodrigo starts it and approves the `aws-live` environment. The daily routine never runs it.
Everything else is tested offline: mock providers and a local Moto server.

## Ground rules
- **No real AWS.** Never configure real credentials, never run `terraform apply` outside `terraform test`
  against Moto, never add a backend that points at real S3. `scripts/check.sh` sets fake credentials.
  The only exception is the live drill above: its stacks under `live/stacks/` carry an empty
  `backend "s3" {}` that the workflow fills at run time.
- **No secrets in the repo.** It's public. No keys, tokens, account IDs, emails or IPs that aren't
  documentation examples (`123456789012`, `203.0.113.0/24`).
- **Production-style, not toy.** Encryption on by default, least-privilege IAM, no `*` actions without
  a written reason, variables validated with `validation` blocks, outputs documented.
- **checkov skips need a reason** inline: `#checkov:skip=CKV_AWS_xxx:why`. Don't skip to get green.
- **Terraform style:** `terraform fmt`, snake_case, one module per folder under `modules/`, each with
  `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `README.md`, `tests/*.tftest.hcl`.
  Pin `required_version = ">= 1.10"` and the AWS provider to `~> 6.0`.
- **Tests:** unit tests use `mock_provider "aws"` with `command = plan`. Integration tests use a provider
  pointed at Moto (`endpoints` block, `http://127.0.0.1:5000`, `skip_credentials_validation`,
  `skip_requesting_account_id`, `skip_metadata_api_check`, `s3_use_path_style`) with `command = apply`.
- **Commits:** Conventional Commits (`feat(vpc): ...`, `test(ecr): ...`, `docs: ...`). One logical change
  per commit. Never squash a day's work into one commit, and never split one change just to add
  commits. Keep the `Co-Authored-By: Claude` trailer. Never rewrite history, force-push, or set
  `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE`.
- **Explain for a learner.** Rodrigo reads every daily note to learn. Write for a strong engineer who is
  new to AWS: define AWS terms the first time, and say why, not just what.

## Commands
- `scripts/bootstrap.sh`: install the pinned toolchain (`.tool-versions`) into `~/.local/aws-platform-tools`
- `scripts/check.sh [dir]`: everything CI runs. Must pass before any push.

## Daily run
The scheduled task follows `.claude/daily-run.md`.
