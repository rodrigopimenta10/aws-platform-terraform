#!/usr/bin/env bash
# Refuses a live-drill plan that could cost real money before `terraform apply` runs. Read-only.
#
# Usage: live/plan-gate.sh <plan.json>      (from `terraform show -json drill.tfplan`)
#
# The IAM guardrails (live/bootstrap) stop the drill role itself from launching big instances, but EKS
# node groups and Auto Scaling groups launch through AWS service-linked roles those rules can't bind. So
# the plan is checked here, where every resource is visible before it exists. Limits are deliberately
# tight: drills prove that modules work, they don't need size. Raising a limit is a change to this file,
# which unattended drills refuse to run with (see the workflow's protected-paths check).
set -euo pipefail
plan="${1:?usage: live/plan-gate.sh <plan.json>}"

MAX_RESOURCES="${MAX_RESOURCES:-150}"
MAX_NAT_GATEWAYS=1
MAX_EKS_CLUSTERS=1
MAX_NODES=3
MAX_INTERFACE_ENDPOINT_AZS=2
TYPE_RE='^(t3|t3a|t4g)\.(nano|micro|small|medium|large)$'

# Resource types a drill must never create, whatever their size.
FORBIDDEN_TYPES='^aws_(db_instance|rds_cluster|rds_cluster_instance|redshift_cluster|elasticache_cluster|elasticache_replication_group|opensearch_domain|elasticsearch_domain|msk_cluster|sagemaker_.*|ec2_host|ec2_capacity_reservation|ec2_capacity_block_reservation|instance_reserved|lightsail_.*|emr_cluster|neptune_cluster|docdb_cluster|globalaccelerator_.*|shield_.*|dx_.*|vpn_gateway|ec2_transit_gateway|networkfirewall_.*|fsx_.*|mq_broker|memorydb_cluster|batch_compute_environment|gamelift_.*|workspaces_.*|appstream_.*|mwaa_environment|kinesis_stream|kinesis_firehose_delivery_stream|bedrock.*)$'

fail=0
problem() { echo "plan-gate: $*" >&2; fail=1; }

# Everything the plan would create or update (a destroy-only change is always allowed).
changes="$(jq -c '[.resource_changes[]? | select(.change.actions | index("create") or index("update"))]' "$plan")"
count="$(jq 'length' <<<"$changes")"
echo "plan-gate: $count resources to create or update"
[ "$count" -le "$MAX_RESOURCES" ] || problem "$count resources is more than the limit of $MAX_RESOURCES"

forbidden="$(jq -r --arg re "$FORBIDDEN_TYPES" '.[] | select(.type | test($re)) | .address' <<<"$changes")"
[ -z "$forbidden" ] || problem "forbidden resource types: $(tr '\n' ' ' <<<"$forbidden")"

n_of() { jq --arg t "$1" '[.[] | select(.type == $t)] | length' <<<"$changes"; }
[ "$(n_of aws_nat_gateway)" -le "$MAX_NAT_GATEWAYS" ] || problem "more than $MAX_NAT_GATEWAYS NAT gateway"
[ "$(n_of aws_eks_cluster)" -le "$MAX_EKS_CLUSTERS" ] || problem "more than $MAX_EKS_CLUSTERS EKS cluster"

# Instance sizes, wherever they appear: aws_instance, launch templates, EKS node groups, Auto Scaling.
bad_types="$(jq -r --arg re "$TYPE_RE" '
  .[] | .address as $a | (.change.after // {}) |
  ([.instance_type?] + (.instance_types? // []) |
   map(select(. != null))) as $types |
  $types[] | select(test($re) | not) | "\($a)=\(.)"' <<<"$changes")"
[ -z "$bad_types" ] || problem "instance types outside $TYPE_RE: $(tr '\n' ' ' <<<"$bad_types")"

# Spot and GPU-style requests are never needed.
spot="$(jq -r '.[] | select(.type == "aws_spot_instance_request" or .type == "aws_spot_fleet_request" or .type == "aws_ec2_fleet") | .address' <<<"$changes")"
[ -z "$spot" ] || problem "spot or fleet requests: $(tr '\n' ' ' <<<"$spot")"

# Node counts: EKS node group scaling_config and Auto Scaling group sizes.
nodes="$(jq '[.[] | (.change.after // {}) |
  ((.scaling_config? // [])[]? | .max_size // 0), (.max_size? // 0)] | add // 0' <<<"$changes")"
[ "$nodes" -le "$MAX_NODES" ] || problem "node groups and Auto Scaling groups allow $nodes nodes in total; the limit is $MAX_NODES"

# Interface endpoints bill per AZ: keep each to MAX_INTERFACE_ENDPOINT_AZS subnets.
wide="$(jq -r --argjson max "$MAX_INTERFACE_ENDPOINT_AZS" '.[] | select(.type == "aws_vpc_endpoint") |
  (.change.after // {}) as $a | select(($a.vpc_endpoint_type // "") == "Interface" and (($a.subnet_ids // []) | length) > $max) | .address' <<<"$changes")"
[ -z "$wide" ] || problem "interface endpoints in more than $MAX_INTERFACE_ENDPOINT_AZS AZs: $(tr '\n' ' ' <<<"$wide")"

# Only the drill region (the role's guardrails also enforce this).
regions="$(jq -r '[.configuration.provider_config[]? | .expressions.region.constant_value? // empty] | unique | join(" ")' "$plan")"
for r in $regions; do
  [ "$r" = "${AWS_REGION:-us-east-1}" ] || problem "provider region $r is not the drill region ${AWS_REGION:-us-east-1}"
done

if [ "$fail" -ne 0 ]; then
  echo "plan-gate: REFUSED. Nothing was applied." >&2
  exit 1
fi
echo "plan-gate: ok"
