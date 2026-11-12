#!/usr/bin/env bash
# Fails if the three lists of live-drill stacks disagree:
#   1. the folders in live/stacks/ that contain .tf files,
#   2. the `stack` choice options in .github/workflows/live-drill.yml,
#   3. the top-level keys of live/screenshots.yml.
# A stack missing from the workflow can't be drilled; one missing from screenshots.yml has no console
# checklist. Plain awk, no YAML tooling needed. Run by scripts/check.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
workflow=".github/workflows/live-drill.yml"
screens="live/screenshots.yml"

[ -d live/stacks ] || { echo "no live/stacks/: nothing to check"; exit 0; }

dirs="$(for d in live/stacks/*/; do compgen -G "$d*.tf" >/dev/null && basename "$d"; done | sort)"

# The `options:` list directly under the `stack:` input.
options="$(awk '
  /^      stack:[[:space:]]*$/ { in_stack = 1; next }
  in_stack && /^      [a-z_]+:[[:space:]]*$/ { in_stack = 0 }
  in_stack && /^        options:[[:space:]]*$/ { in_opts = 1; next }
  in_opts && /^          - / { sub(/^          - /, ""); gsub(/["'\'' ]/, ""); print; next }
  in_opts { in_opts = 0; in_stack = 0 }
' "$workflow" | sort)"

keys="$(awk '/^[a-z0-9][a-z0-9_-]*:[[:space:]]*$/ { sub(/:.*/, ""); print }' "$screens" | sort)"

fail=0
compare() { # label, list
  if [ "$2" != "$dirs" ]; then
    echo "live stacks drift: $1 does not match live/stacks/*" >&2
    diff <(printf '%s\n' "$dirs") <(printf '%s\n' "$2") | sed 's/^/  /' >&2 || true
    fail=1
  fi
}
compare "$workflow stack options" "$options"
compare "$screens top-level keys" "$keys"

if [ $fail -ne 0 ]; then
  echo "  (< only in live/stacks, > only in the other file)" >&2
  exit 1
fi
echo "live stacks match: $(printf '%s ' $dirs)"
