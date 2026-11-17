#!/usr/bin/env bash
# Prints the commit of the last live drill that really drilled something and succeeded, among the
# ancestors of the commit given. Prints nothing when there is none.
#
#   live/last-drill.sh <commit>
#
# The drill workflow compares a push with this commit to decide which stacks changed and whether the
# push touches the drill machinery (protected paths), which unattended drills refuse.
#
# Why "really drilled": a run of live-drill.yml that drills nothing still ends green. That happens when
# no stack changed, and when the run refuses a push because it changes protected paths. Counting such a
# run as the last drill would move the comparison past the protected change, and the next push would be
# drilled unattended with machinery nobody had checked: the refusal would hold for one push only. So a
# run counts only if at least one of its "Drill <stack>" jobs succeeded. After a refused push, every
# later push is refused too, until a drill started by hand has passed on the changed machinery.
#
# Needs `gh` signed in (GH_TOKEN in the workflow) with actions: read, and GITHUB_REPOSITORY.
set -euo pipefail

sha="${1:?usage: live/last-drill.sh <commit>}"
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"
limit="${LAST_DRILL_LIMIT:-200}"

gh run list --repo "$repo" --workflow live-drill.yml --status success --limit "$limit" \
  --json databaseId,headSha --jq '.[] | "\(.databaseId) \(.headSha)"' |
  while read -r id run_sha; do
    [ -n "$id" ] || continue
    git merge-base --is-ancestor "$run_sha" "$sha" 2>/dev/null || continue
    drilled="$(gh api "repos/$repo/actions/runs/$id/jobs?per_page=100" \
      --jq '[.jobs[] | select(.name | startswith("Drill ")) | select(.conclusion == "success")] | length')"
    if [ "${drilled:-0}" -gt 0 ]; then
      echo "$run_sha"
      break
    fi
  done
