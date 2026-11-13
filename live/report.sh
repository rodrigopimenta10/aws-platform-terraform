#!/usr/bin/env bash
# Writes the drill report docs/live/<date>-<stack>.md, with its screenshots and evidence next to it in
# docs/live/<date>-<stack>/. Runs in the workflow's publish job (no AWS access). Read-only except for docs/.
#
# Usage: live/report.sh <stack> <artifact_dir>
#   <artifact_dir> holds the drill job's upload: evidence/*.json|txt|md, shots/*.png, shots/screenshots.json,
#   result.json (apply, destroy and verify outcomes and timings).
set -euo pipefail
stack="${1:?usage: live/report.sh <stack> <artifact_dir>}"
art="${2:?artifact_dir}"
date="$(TZ=America/New_York date +%F)"
name="$date-$stack"
n=2
while [ -e "docs/live/$name.md" ]; do name="$date-$stack-$n"; n=$((n + 1)); done
dir="docs/live/$name"
mkdir -p "$dir/evidence"
cp "$art"/evidence/* "$dir/evidence/" 2>/dev/null || true

result="$art/result.json"
r() { jq -r "$1" "$result"; }

# Screenshots: lossless WebP at full resolution (about half the size of PNG, same pixels).
shots_md=""
if [ -f "$art/shots/screenshots.json" ]; then
  while IFS= read -r s; do
    sname="$(jq -r '.name' <<<"$s")"
    proves="$(jq -r '.proves' <<<"$s")"
    if [ "$(jq -r '.ok' <<<"$s")" = "true" ] && [ -f "$art/shots/$sname.png" ]; then
      if command -v cwebp >/dev/null; then
        cwebp -quiet -lossless -z 6 "$art/shots/$sname.png" -o "$dir/$sname.webp"
        img="$sname.webp"
      else
        cp "$art/shots/$sname.png" "$dir/$sname.png"
        img="$sname.png"
      fi
      size="$(identify -format '%wx%h' "$dir/$img" 2>/dev/null || echo "?")"
      shots_md+=$'\n'"**$sname** ($size): $proves"$'\n\n'"![$sname]($name/$img)"$'\n'
    else
      err="$(jq -r '.error // "not captured"' <<<"$s")"
      shots_md+=$'\n'"**$sname**: not captured ($err). Should show: $proves"$'\n'
    fi
  done < <(jq -c '.[]' "$art/shots/screenshots.json")
fi

resources="$(grep -Ev '(^|\.)data\.' "$dir/evidence/state-list.txt" 2>/dev/null | grep -c . || true)"
by_type="$(grep -Ev '(^|\.)data\.' "$dir/evidence/state-list.txt" 2>/dev/null | sed -E 's/\[[^]]*\]$//' |
  awk -F. '{print $(NF-1)}' | sort | uniq -c | awk '{printf "| `%s` | %s |\n", $2, $1}' || true)"

verified="$(r '.destroy_verified')"
{
  echo "# Live drill: \`$stack\`, $date"
  echo
  echo "Applied to the real AWS account by \`.github/workflows/live-drill.yml\` ($(r .reason)),"
  echo "screenshotted in a headless browser signed in as the drill role, then destroyed. No human step."
  echo
  echo "| | |"
  echo "| --- | --- |"
  echo "| Stack | \`live/stacks/$stack\` |"
  echo "| Commit applied | \`$(r '.commit')\` |"
  echo "| Why it ran | $(r '.reason') |"
  echo "| Run | [$(r '.run_id')](https://github.com/$GITHUB_REPOSITORY/actions/runs/$(r '.run_id')) |"
  echo "| Plan gate | $(r '.gate') |"
  echo "| Apply | $(r '.apply_outcome'), $(r '.apply_seconds // "n/a"') s, $resources resources |"
  echo "| Destroy | $(r '.destroy_outcome'), $(r '.destroy_seconds // "n/a"') s |"
  echo "| Destroy verified | $([ "$verified" = true ] && echo "**yes**" || echo "**NO: check the account**") |"
  echo
  if [ -n "$by_type" ]; then
    echo "## What was created"
    echo
    echo "| Type | Count |"
    echo "| --- | --- |"
    echo "$by_type"
    echo
  fi
  echo "## Screenshots"
  echo
  echo "Captured at 2x device pixels in the AWS console, signed in through the AWS federation endpoint as the drill"
  echo "role. Before each capture every occurrence of the account ID was replaced and the console header masked."
  echo "${shots_md:-$'\n'No screenshots for this stack.}"
  echo
  echo "## Evidence"
  echo
  echo "Read-only describe calls right after the apply, account ID replaced by \`<ACCOUNT_ID>\`:"
  for f in "$dir"/evidence/*; do
    [ -e "$f" ] || continue
    b="$(basename "$f")"
    echo "- [\`$b\`]($name/evidence/$b)"
  done
} >"docs/live/$name.md"

# Belt and braces: nothing written may contain a 12-digit account ID.
if grep -rqE '(^|[^0-9a-fA-F])[0-9]{12}([^0-9a-fA-F]|$)' "docs/live/$name.md" "$dir/evidence" 2>/dev/null; then
  echo "report: a 12-digit number survived redaction; refusing to publish" >&2
  grep -rlE '(^|[^0-9a-fA-F])[0-9]{12}([^0-9a-fA-F]|$)' "docs/live/$name.md" "$dir/evidence" >&2 || true
  exit 1
fi
echo "report: docs/live/$name.md"
