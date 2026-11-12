#!/usr/bin/env bash
# Runs every check CI runs: fmt, the live-drill stack lists, validate, tflint, checkov, and `terraform test`
# (unit tests with mock providers + integration tests applied against a local Moto server).
# Nothing here talks to real AWS.
#
# Usage: scripts/check.sh            # everything
#        scripts/check.sh modules/vpc  # one module
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TOOLS_DIR="${TOOLS_DIR:-$HOME/.local/aws-platform-tools}"
if [ -f "$TOOLS_DIR/env.sh" ]; then
  # shellcheck disable=SC1091
  . "$TOOLS_DIR/env.sh"
fi
for t in terraform tflint checkov moto_server; do
  command -v "$t" >/dev/null || { echo "missing $t: run scripts/bootstrap.sh first" >&2; exit 1; }
done

# Fake credentials so the AWS provider never looks for real ones.
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
unset AWS_PROFILE AWS_SESSION_TOKEN
export MOTO_ENDPOINT="${MOTO_ENDPOINT:-http://127.0.0.1:5000}"

if [ $# -gt 0 ]; then dirs=("$@"); else
  dirs=()
  for d in modules/* envs/* live/bootstrap live/stacks/*; do
    [ -d "$d" ] && compgen -G "$d/*.tf" >/dev/null && dirs+=("$d")
  done
fi

fail=0
step() { printf '\n== %s\n' "$*"; }

step "terraform fmt"
terraform fmt -check -recursive -diff || fail=1

step "live drill stack lists"
scripts/check-live-stacks.sh || fail=1

if [ ${#dirs[@]} -eq 0 ]; then
  echo "No Terraform modules yet. Nothing else to check."
  exit $fail
fi

# Start Moto for integration tests.
moto_pid=""
if ! curl -fsS -o /dev/null "$MOTO_ENDPOINT/moto-api/" 2>/dev/null; then
  moto_server -H 127.0.0.1 -p 5000 >/tmp/moto.log 2>&1 &
  moto_pid=$!
  for _ in $(seq 1 30); do curl -fsS -o /dev/null "$MOTO_ENDPOINT/moto-api/" 2>/dev/null && break; sleep 0.5; done
fi
trap '[ -n "$moto_pid" ] && kill "$moto_pid" 2>/dev/null || true' EXIT

for d in "${dirs[@]}"; do
  step "$d: init + validate"
  (cd "$d" && terraform init -backend=false -input=false -no-color >/dev/null && terraform validate -no-color) || { fail=1; continue; }
  if compgen -G "$d/tests/*.tftest.hcl" >/dev/null; then
    step "$d: terraform test"
    (cd "$d" && curl -fsS -X POST -o /dev/null "$MOTO_ENDPOINT/moto-api/reset" 2>/dev/null; terraform test -no-color) || fail=1
  fi
done

step "tflint"
# bootstrap.sh installs the AWS ruleset directly; only fall back to --init if it's missing.
compgen -G "$HOME/.tflint.d/plugins/github.com/terraform-linters/tflint-ruleset-aws/*/tflint-ruleset-aws" >/dev/null \
  || tflint --init --config "$ROOT/.tflint.hcl" >/dev/null
tflint --recursive --config "$ROOT/.tflint.hcl" --format compact || fail=1

step "checkov"
# --skip-download: don't call the Prisma Cloud API for guideline links (blocked in sandboxes, not needed).
checkov -d . --config-file .checkov.yaml --quiet --compact --skip-download || fail=1

if [ $fail -ne 0 ]; then echo; echo "CHECKS FAILED"; exit 1; fi
echo; echo "ALL CHECKS PASSED"
