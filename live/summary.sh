#!/usr/bin/env bash
# Prints the Markdown job summary for a live-drill apply: what was created (counted by resource type, no
# IDs in the text), console links from live/screenshots.yml (links may carry resource IDs, never the
# account ID), and when the destroy will start. Read-only.
#
# Usage (repo root, after `terraform apply`): live/summary.sh <stack> <hold_minutes> <apply_seconds>
# Needs terraform and jq; console links also need yq (mikefarah v4, preinstalled on GitHub's Ubuntu images).
set -euo pipefail

stack="${1:?usage: live/summary.sh <stack> <hold_minutes> <apply_seconds>}"
hold="${2:?hold_minutes}"
apply_seconds="${3:?apply_seconds}"
root="$(cd "$(dirname "$0")/.." && pwd)"
dir="$root/live/stacks/$stack"
region="${AWS_REGION:-us-east-1}"
sha="${GITHUB_SHA:-$(git -C "$root" rev-parse HEAD)}"

# GNU date on the runner, BSD date on macOS.
earliest="$(date -u -d "+${hold} minutes" '+%H:%M UTC' 2>/dev/null || date -u -v+"${hold}"M '+%H:%M UTC')"

# Managed resources only: data sources are reads, not things that were created.
resources="$(terraform -chdir="$dir" state list | grep -Ev '(^|\.)data\.' || true)"
count="$(printf '%s\n' "$resources" | grep -c . || true)"

echo "## Live drill: \`$stack\` applied"
echo
echo "- Commit: \`$sha\`"
echo "- Region: \`$region\`"
echo "- Apply took ${apply_seconds}s and created ${count} resources."
echo "- Hold: ${hold} minutes. The destroy job starts its hold when it is approved, so destroy begins"
echo "  ${hold} minutes after that approval: ${earliest} at the earliest."
echo
echo "### Resources by type"
echo
echo "| Type | Count |"
echo "|---|---|"
# module.vpc.aws_subnet.public[0] -> aws_subnet
printf '%s\n' "$resources" | grep . | sed -E 's/\[[^]]*\]$//' | awk -F. '{print $(NF-1)}' |
  sort | uniq -c | awk '{printf "| `%s` | %s |\n", $2, $1}'

if command -v yq >/dev/null && [ -f "$root/live/screenshots.yml" ]; then
  outputs="$(terraform -chdir="$dir" output -json)"
  pages="$(yq -o=json '.' "$root/live/screenshots.yml" | jq -c --arg s "$stack" '.[$s] // [] | .[]')"
  if [ -n "$pages" ]; then
    echo
    echo "### Console (what each screenshot should prove)"
    echo
    while IFS= read -r page; do
      name="$(jq -r '.name' <<<"$page")"
      url="$(jq -r '.url' <<<"$page")"
      proves="$(jq -r '.proves' <<<"$page")"
      url="${url//\{region\}/$region}"
      while IFS=$'\t' read -r key value; do
        [ -n "$key" ] && url="${url//\{$key\}/$value}"
      done < <(jq -r 'to_entries[] | select(.value.type == "string") | "\(.key)\t\(.value.value)"' <<<"$outputs")
      echo "- [$name]($url): $proves"
    done <<<"$pages"
  fi
fi
