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
#   2. So each listed resource is asked for directly, from the service that owns it:
#      - EC2 types drills create (VPCs, subnets, route tables, gateways, security groups and their rules,
#        NAT gateways, Elastic IPs, network ACLs, VPC endpoints, flow logs): a deleted one answers
#        "<Type>.NotFound", an empty list, or the state "deleted".
#      - KMS keys: AWS never deletes a key at once. `terraform destroy` schedules the deletion, and the
#        key then sits in the state PendingDeletion for the waiting period (7 days in the drill stacks),
#        still tagged and still in the index. In that state it cannot be used and is not billed, and AWS
#        removes it on its own, so it counts as destroyed and the date is printed. Any other state
#        (Enabled, Disabled, a cancelled deletion) counts as left over.
#      Anything else, including other services, counts as left over until the index drops it, so a real
#      leftover is never missed. A lookup that fails (access denied, throttling) also counts as left over.
#      The m1 and m2 drills of 2026-11-14 to 2026-11-17 failed here because endpoints, security group
#      rules, flow logs and keys were not in this list: Terraform had destroyed all of them.
# The whole check is retried for up to five minutes before failing.
set -euo pipefail

stack="${1:?usage: live/verify-destroyed.sh <stack>}"
region="${AWS_REGION:-us-east-1}"
attempts="${VERIFY_ATTEMPTS:-10}"
interval="${VERIFY_INTERVAL_SECONDS:-30}"

account="$(aws sts get-caller-identity --query Account --output text)"

# Prints the ARN if the resource still exists (or cannot be checked), nothing if it is gone.
# EC2's own tag records trail deletes too (describe-tags still returned tags for two deleted subnets), so
# each resource is described by ID. `out` holds the IDs that are left, or the error text of a failed call.
still_there() {
  local arn="$1" service type id out state deletion_date
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
      # A deleted interface endpoint can show as "deleted" for a while before EC2 forgets its ID.
      vpc-endpoint) out="$(aws ec2 describe-vpc-endpoints --region "$region" --vpc-endpoint-ids "$id" --query 'VpcEndpoints[?State!=`deleted`].VpcEndpointId' --output text 2>&1)"
        [ -z "$out" ] && return 0 ;;
      security-group-rule) out="$(aws ec2 describe-security-group-rules --region "$region" --security-group-rule-ids "$id" --query 'SecurityGroupRules[].SecurityGroupRuleId' --output text 2>&1)"
        [ -z "$out" ] && return 0 ;;
      vpc-flow-log) out="$(aws ec2 describe-flow-logs --region "$region" --flow-log-ids "$id" --query 'FlowLogs[].FlowLogId' --output text 2>&1)"
        [ -z "$out" ] && return 0 ;;
      *) out="" ;;
    esac
    if printf '%s' "$out" | grep -q '\.NotFound'; then
      return 0
    fi
  elif [ "$service" = "kms" ] && [ "$type" = "key" ]; then
    out="$(aws kms describe-key --region "$region" --key-id "$id" --query 'KeyMetadata.[KeyState,DeletionDate]' --output text 2>&1)"
    if printf '%s' "$out" | grep -q 'NotFoundException'; then
      return 0
    fi
    read -r state deletion_date <<<"$out" || true
    if [ "$state" = "PendingDeletion" ]; then
      # To the job log, not to the list of leftovers on stdout.
      echo "verify: KMS key $id is scheduled for deletion (${deletion_date:-date unknown}); it cannot be used and is not billed until AWS removes it" >&2
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
      echo "verify: the tagging index still lists resources for live-stack=$stack, but the services that own them say they are deleted or scheduled for deletion"
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
