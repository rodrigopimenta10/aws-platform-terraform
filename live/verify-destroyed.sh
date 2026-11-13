#!/usr/bin/env bash
# After `terraform destroy` of a live-drill stack: fail unless nothing tagged managed-by=terraform and
# live-stack=<stack> is left. Read-only.
#
# Usage (repo root, with AWS credentials):  live/verify-destroyed.sh <stack>
#
# Two lookups, because the first one alone is not enough:
#   1. The Resource Groups Tagging API lists every resource with the stack's tags. It is an index, and it
#      trails the deletes: on the first vpc drill (2026-11-12) it still listed two subnets and a security
#      group more than ten minutes after `terraform destroy`, while EC2 said none of them existed.
#   2. So each listed resource is asked for directly. For the EC2 types drills create (VPCs, subnets,
#      route tables, gateways, security groups, NAT gateways, Elastic IPs, network ACLs), a deleted one
#      answers "<Type>.NotFound". Anything else, including other services, counts as left over until the
#      index drops it, so a real leftover is never missed.
# The whole check is retried for up to five minutes before failing.
set -euo pipefail

stack="${1:?usage: live/verify-destroyed.sh <stack>}"
region="${AWS_REGION:-us-east-1}"
attempts="${VERIFY_ATTEMPTS:-10}"
interval="${VERIFY_INTERVAL_SECONDS:-30}"

account="$(aws sts get-caller-identity --query Account --output text)"

# Prints the ARN if the resource still exists (or cannot be checked), nothing if it is gone.
# EC2 types that drills create are asked for directly; AWS answers "<Type>.NotFound" for a deleted one.
# (EC2's own tag records trail deletes too: describe-tags still returned tags for two deleted subnets.)
still_there() {
  local arn="$1" service type id out
  service="$(printf '%s' "$arn" | cut -d: -f3)"
  type="$(printf '%s' "$arn" | cut -d: -f6 | cut -d/ -f1)"
  id="${arn##*/}"
  if [ "$service" = "ec2" ]; then
    case "$type" in
      vpc) out="$(aws ec2 describe-vpcs --region "$region" --vpc-ids "$id" 2>&1)" ;;
      subnet) out="$(aws ec2 describe-subnets --region "$region" --subnet-ids "$id" 2>&1)" ;;
      route-table) out="$(aws ec2 describe-route-tables --region "$region" --route-table-ids "$id" 2>&1)" ;;
      internet-gateway) out="$(aws ec2 describe-internet-gateways --region "$region" --internet-gateway-ids "$id" 2>&1)" ;;
      security-group) out="$(aws ec2 describe-security-groups --region "$region" --group-ids "$id" 2>&1)" ;;
      natgateway) out="$(aws ec2 describe-nat-gateways --region "$region" --nat-gateway-ids "$id" --query 'NatGateways[?State!=`deleted`]' --output text 2>&1)"
        [ -z "$out" ] && return 0 ;;
      elastic-ip) out="$(aws ec2 describe-addresses --region "$region" --allocation-ids "$id" 2>&1)" ;;
      network-acl) out="$(aws ec2 describe-network-acls --region "$region" --network-acl-ids "$id" 2>&1)" ;;
      *) out="" ;;
    esac
    if printf '%s' "$out" | grep -q '\.NotFound'; then
      return 0
    fi
  fi
  printf '%s\n' "$arn"
}

for i in $(seq 1 "$attempts"); do
  listed="$(aws resourcegroupstaggingapi get-resources --region "$region" \
    --tag-filters "Key=managed-by,Values=terraform" "Key=live-stack,Values=$stack" \
    --query 'ResourceTagMappingList[].ResourceARN' --output text)"
  left=""
  if [ -n "$listed" ] && [ "$listed" != "None" ]; then
    for arn in $(printf '%s' "$listed" | tr '\t' '\n'); do
      left="$left$(still_there "$arn")"$'\n'
    done
    left="$(printf '%s' "$left" | sed '/^$/d')"
  fi
  if [ -z "$left" ]; then
    if [ -n "$listed" ] && [ "$listed" != "None" ]; then
      echo "verify: the tagging index still lists resources for live-stack=$stack, but EC2 says none of them exist"
    fi
    echo "verify: nothing tagged live-stack=$stack remains in $region"
    exit 0
  fi
  echo "verify: attempt $i/$attempts, still there:"
  printf '%s\n' "$left" | sed "s/$account/<ACCOUNT_ID>/g"
  [ "$i" -lt "$attempts" ] && sleep "$interval"
done

echo "verify: resources tagged live-stack=$stack are still there after $((attempts * interval))s" >&2
exit 1
