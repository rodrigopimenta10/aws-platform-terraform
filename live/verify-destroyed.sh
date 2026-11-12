#!/usr/bin/env bash
# After `terraform destroy` of a live-drill stack: fail unless nothing tagged managed-by=terraform and
# live-stack=<stack> is left, according to the Resource Groups Tagging API. Read-only.
#
# Usage (repo root, with AWS credentials):  live/verify-destroyed.sh <stack>
#
# The lookup is retried for up to five minutes before failing, in case the tagging index trails the
# deletes. A resource that is still there after that is a real leftover.
set -euo pipefail

stack="${1:?usage: live/verify-destroyed.sh <stack>}"
region="${AWS_REGION:-us-east-1}"
attempts="${VERIFY_ATTEMPTS:-10}"
interval="${VERIFY_INTERVAL_SECONDS:-30}"

account="$(aws sts get-caller-identity --query Account --output text)"

for i in $(seq 1 "$attempts"); do
  left="$(aws resourcegroupstaggingapi get-resources --region "$region" \
    --tag-filters "Key=managed-by,Values=terraform" "Key=live-stack,Values=$stack" \
    --query 'ResourceTagMappingList[].ResourceARN' --output text)"
  if [ -z "$left" ] || [ "$left" = "None" ]; then
    echo "verify: nothing tagged live-stack=$stack remains in $region"
    exit 0
  fi
  echo "verify: attempt $i/$attempts, still tagged:"
  printf '%s\n' "$left" | tr '\t' '\n' | sed "s/$account/<ACCOUNT_ID>/g"
  [ "$i" -lt "$attempts" ] && sleep "$interval"
done

echo "verify: resources tagged live-stack=$stack are still there after $((attempts * interval))s" >&2
exit 1
