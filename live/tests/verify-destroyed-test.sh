#!/usr/bin/env bash
# Offline test of live/verify-destroyed.sh. Run by scripts/check.sh; nothing here talks to AWS.
#
# A fake `aws` command is put first on PATH. It answers from three lists the test sets:
#   LISTED    what the tagging index returns (ARNs), stale entries included
#   EXISTING  IDs that the owning service still has ("id" or "id=state")
#   DENIED    IDs whose describe call fails with AccessDenied
# Everything else answers the way AWS does for a deleted resource: "<Type>.NotFound" for EC2 and
# "NotFoundException" for KMS. The first two cases replay what the tagging index listed after the m1 and
# m2 drills of 2026-11-17, when Terraform had destroyed everything and this check still failed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/aws" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
has() { case " $2 " in *" $1 "*|*" $1="*) return 0 ;; esac; return 1; }
state_of() { local w; for w in $2; do case "$w" in "$1="*) echo "${w#*=}"; return ;; esac; done; echo "$3"; }
case "$1 $2" in
  "sts get-caller-identity") echo 123456789012; exit 0 ;;
  "resourcegroupstaggingapi get-resources")
    if [ -z "${LISTED:-}" ]; then echo None; else printf '%s' "$LISTED" | tr ' ' '\t'; echo; fi; exit 0 ;;
esac
# The ID is the argument after --<something>-ids, --group-ids or --key-id.
id=""; query=0; prev=""
for a in "$@"; do
  case "$prev" in --*-ids|--key-id) id="$a" ;; esac
  [ "$a" = "--query" ] && query=1
  prev="$a"
done
if has "$id" "${DENIED:-}"; then
  echo "An error occurred (AccessDenied) when calling the operation: not authorized" >&2; exit 254
fi
case "$1 $2" in
  "kms describe-key")
    has "$id" "${EXISTING:-}" || { echo "An error occurred (NotFoundException) when calling the DescribeKey operation: Key not found" >&2; exit 254; }
    state="$(state_of "$id" "${EXISTING:-}" Enabled)"
    if [ "$state" = PendingDeletion ]; then printf '%s\t%s\n' "$state" "2026-11-24T00:54:43+00:00"; else printf '%s\tNone\n' "$state"; fi ;;
  "ec2 describe-"*)
    if ! has "$id" "${EXISTING:-}"; then
      # Calls with --query are the ones the script expects an empty list or NotFound from; flow logs
      # answer with an empty list, the rest with an error.
      if [ "$2" = describe-flow-logs ]; then exit 0; fi
      echo "An error occurred (InvalidResourceID.NotFound) when calling the operation: '$id' does not exist" >&2; exit 254
    fi
    state="$(state_of "$id" "${EXISTING:-}" available)"
    # The script's queries drop resources in the state "deleted".
    if [ "$query" = 1 ] && [ "$state" = deleted ]; then exit 0; fi
    echo "$id" ;;
  *) echo "fake aws: unexpected call: $*" >&2; exit 2 ;;
esac
STUB
chmod +x "$tmp/aws"

A="arn:aws:ec2:us-east-1:123456789012"
K="arn:aws:kms:us-east-1:123456789012:key"
fail=0
# check <name> <expected exit code> <text the output must contain, or ""> ; reads LISTED, EXISTING, DENIED
check() {
  local name="$1" want="$2" text="$3" got=0 out
  out="$(PATH="$tmp:$PATH" AWS_REGION=us-east-1 VERIFY_ATTEMPTS=1 VERIFY_INTERVAL_SECONDS=0 \
    LISTED="${LISTED:-}" EXISTING="${EXISTING:-}" DENIED="${DENIED:-}" \
    "$ROOT/live/verify-destroyed.sh" teststack 2>&1)" || got=$?
  if [ "$got" != "$want" ] || { [ -n "$text" ] && ! grep -qF -- "$text" <<<"$out"; }; then
    echo "FAIL: $name (exit $got, wanted $want${text:+, wanted text: $text})"; sed 's/^/    /' <<<"$out"; fail=1
  else
    echo "ok:   $name"
  fi
  LISTED="" EXISTING="" DENIED=""
}

LISTED=""
check "nothing listed" 0 "nothing tagged live-stack=teststack remains"

# The m1 list of 2026-11-17: endpoints, security group rules and a flow log that Terraform had deleted,
# this drill's key and the key of 2026-11-15, both scheduled for deletion.
LISTED="$A:vpc-endpoint/vpce-0f898927d11f1e7ee $A:vpc-endpoint/vpce-0f830813299644698 $A:vpc-endpoint/vpce-00f9a383f718469ae $K/58e12779-6d50-4159-8904-2465ed1466d7 $A:security-group-rule/sgr-00e7b78e3e47615f5 $A:vpc-flow-log/fl-04b76a0fcf0d32639 $A:security-group-rule/sgr-00d38caacab6da8ee $A:security-group-rule/sgr-09d66f7999e774a38 $A:vpc-endpoint/vpce-039ab45cfa1f58ab7 $A:security-group-rule/sgr-0ea691cdb35a06fd5 $A:vpc-endpoint/vpce-0671541b5cc67a845 $K/7cb8b175-04b8-4034-aab8-4a6d949ab1d3"
EXISTING="58e12779-6d50-4159-8904-2465ed1466d7=PendingDeletion 7cb8b175-04b8-4034-aab8-4a6d949ab1d3=PendingDeletion"
check "m1 2026-11-17: stale index entries and keys pending deletion" 0 "nothing tagged live-stack=teststack remains"

# The m2 list of 2026-11-17.
LISTED="$K/22360b4a-2d61-41b6-abb9-57f4bcd4e2fb $K/80043f78-def1-4e41-9095-6acbdbda685f"
EXISTING="22360b4a-2d61-41b6-abb9-57f4bcd4e2fb=PendingDeletion 80043f78-def1-4e41-9095-6acbdbda685f=PendingDeletion"
check "m2 2026-11-17: keys pending deletion, with the date" 0 "KMS key 80043f78-def1-4e41-9095-6acbdbda685f is scheduled for deletion (2026-11-24T00:54:43+00:00)"

LISTED="$K/11111111-1111-1111-1111-111111111111"
check "a key AWS has already removed" 0 ""

LISTED="$A:vpc-endpoint/vpce-0aaa"
EXISTING="vpce-0aaa=deleted"
check "an endpoint in the state deleted" 0 ""

# Real leftovers must still fail, and be named.
LISTED="$K/22222222-2222-2222-2222-222222222222"
EXISTING="22222222-2222-2222-2222-222222222222=Enabled"
check "a key that was never scheduled for deletion" 1 "key/22222222-2222-2222-2222-222222222222"

LISTED="$K/33333333-3333-3333-3333-333333333333"
EXISTING="33333333-3333-3333-3333-333333333333=Disabled"
check "a key whose deletion was cancelled" 1 "key/33333333-3333-3333-3333-333333333333"

LISTED="$A:vpc-endpoint/vpce-0bbb $A:vpc-endpoint/vpce-0ccc"
EXISTING="vpce-0bbb=available"
check "an endpoint that still exists" 1 "vpc-endpoint/vpce-0bbb"

LISTED="$A:vpc-endpoint/vpce-0ddd"
EXISTING="vpce-0ddd=deleting"
check "an endpoint still being deleted" 1 "vpc-endpoint/vpce-0ddd"

LISTED="$A:security-group-rule/sgr-0eee $A:vpc-flow-log/fl-0fff"
EXISTING="sgr-0eee fl-0fff"
check "a security group rule and a flow log that still exist" 1 "vpc-flow-log/fl-0fff"

LISTED="$A:vpc-endpoint/vpce-0abc $K/44444444-4444-4444-4444-444444444444"
DENIED="vpce-0abc 44444444-4444-4444-4444-444444444444"
check "lookups that fail count as left over" 1 "key/44444444-4444-4444-4444-444444444444"

LISTED="arn:aws:logs:us-east-1:123456789012:log-group:/aws/platform-live/app"
check "a type the script cannot ask about counts as left over" 1 "log-group:/aws/platform-live/app"

LISTED="$A:vpc/vpc-0123 $A:subnet/subnet-0123 $A:security-group/sg-0123"
check "the EC2 types of the vpc drill, all deleted" 0 "the services that own them say they are deleted"

[ "$fail" = 0 ] && echo "verify-destroyed: all cases passed"
exit "$fail"
