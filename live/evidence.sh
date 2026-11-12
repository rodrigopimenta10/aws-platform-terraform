#!/usr/bin/env bash
# Read-only evidence of an applied live-drill stack: AWS "describe" calls saved as JSON, with the account
# ID replaced by <ACCOUNT_ID> before anything is written. Nothing here creates, changes or deletes.
#
# Usage (repo root, after `terraform apply`, with AWS credentials):
#   live/evidence.sh <stack> [out_dir]        # out_dir defaults to evidence/<stack>
#
# Every stack gets the generic files (state addresses, outputs, everything tagged live-stack=<stack>).
# Stacks listed in the case below also get service-specific describes. A new stack works without editing
# this file; add a case when the generic files don't show what the drill should prove.
set -euo pipefail

stack="${1:?usage: live/evidence.sh <stack> [out_dir]}"
root="$(cd "$(dirname "$0")/.." && pwd)"
dir="$root/live/stacks/$stack"
out="${2:-evidence/$stack}"
region="${AWS_REGION:-us-east-1}"

[ -d "$dir" ] || { echo "no such stack: live/stacks/$stack" >&2; exit 1; }
mkdir -p "$out"

account="$(aws sts get-caller-identity --query Account --output text)"
[[ "$account" =~ ^[0-9]{12}$ ]] || { echo "could not read the account ID" >&2; exit 1; }
redact() { sed "s/$account/<ACCOUNT_ID>/g"; }

# save <name> <aws command...>: run a read-only call and write redacted JSON to <out>/<name>.json.
save() {
  local name="$1"
  shift
  "$@" --region "$region" --output json | redact >"$out/$name.json"
  echo "evidence: $name.json"
}

tf_output() { terraform -chdir="$dir" output -raw "$1"; }

# Generic: what Terraform manages (addresses only, no IDs), its outputs, and everything carrying the tag.
terraform -chdir="$dir" state list | redact >"$out/state-list.txt"
terraform -chdir="$dir" output -json | redact >"$out/outputs.json"
save tagged-resources aws resourcegroupstaggingapi get-resources \
  --tag-filters "Key=live-stack,Values=$stack"

case "$stack" in
  vpc)
    vpc_id="$(tf_output vpc_id)"
    save vpc aws ec2 describe-vpcs --vpc-ids "$vpc_id"
    save vpc-dns-support aws ec2 describe-vpc-attribute --vpc-id "$vpc_id" --attribute enableDnsSupport
    save vpc-dns-hostnames aws ec2 describe-vpc-attribute --vpc-id "$vpc_id" --attribute enableDnsHostnames
    save subnets aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id"
    save route-tables aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id"
    save internet-gateways aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id"
    save security-groups aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id"
    # Should be empty: the stack has no NAT gateway. (This call takes --filter, singular.)
    save nat-gateways aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc_id"
    ;;
  *)
    echo "evidence: no service-specific calls for '$stack', generic files only"
    ;;
esac

# Belt and braces: fail if the account ID survived anywhere.
if grep -rqF "$account" "$out"; then
  echo "account ID found in $out after redaction" >&2
  exit 1
fi
