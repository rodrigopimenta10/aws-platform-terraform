# ADR 0001: Test offline with mock providers and Moto, never real AWS

- **Status:** accepted
- **Date:** 2026-11-09

## Context
This platform is built by an unattended daily agent and pushed straight to `main`. Giving that agent real
AWS credentials would risk surprise bills and accidental changes to a real account. The code still has
to be proven to work, not just to pass `terraform validate`.

The usual offline option, LocalStack, has required an account and auth token for its container image
since March 2026, which would mean storing a token in the build environment.

## Decision
Two layers of tests, both inside `terraform test`:

1. **Unit tests** use `mock_provider "aws"` with `command = plan`. They check variable validation, naming,
   tags, counts, and the shape of IAM policies, with no network and no emulator.
2. **Integration tests** use `command = apply` against **Moto** (`moto[server]`, Apache-2.0, installed from
   PyPI). Moto runs locally on port 5000 and emulates AWS APIs closely enough for Terraform to create, read
   and destroy resources.

`scripts/check.sh` runs both, plus `fmt`, `validate`, `tflint` and `checkov`, the same way locally, in CI
and in the daily cloud run. Real deployment is a manual, human step described in
`docs/deploy-it-yourself.md` (roadmap M7.3).

## Consequences
- No credentials anywhere, and no cost.
- Moto doesn't emulate every resource fully (EKS internals, some networking behaviour). Those resources
  get unit tests only, and each module README says so.
- "Tests pass" is weaker evidence than "deployed". The manual deploy walkthrough closes that gap.
