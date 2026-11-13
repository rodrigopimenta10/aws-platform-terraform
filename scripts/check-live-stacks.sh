#!/usr/bin/env bash
# Fails if the folders in live/stacks/ that contain .tf files and the top-level keys of live/screenshots.yml
# disagree: a stack missing from screenshots.yml has no console checklist, and an entry for a stack that
# doesn't exist is dead. (The drill workflow finds stacks by folder, so it needs no list.) Plain awk, no
# YAML tooling needed. Run by scripts/check.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
screens="live/screenshots.yml"
[ -d live/stacks ] || { echo "no live/stacks/: nothing to check"; exit 0; }
dirs="$(for d in live/stacks/*/; do compgen -G "$d*.tf" >/dev/null && basename "$d"; done | sort)"
keys="$(awk '/^[a-z0-9][a-z0-9_-]*:[[:space:]]*$/ { sub(/:.*/, ""); print }' "$screens" | sort)"
if [ "$keys" != "$dirs" ]; then
  echo "live stacks drift: $screens top-level keys do not match live/stacks/*" >&2
  diff <(printf '%s\n' "$dirs") <(printf '%s\n' "$keys") | sed 's/^/  /' >&2 || true
  echo "  (< only in live/stacks, > only in $screens)" >&2
  exit 1
fi
echo "live stacks match: $(printf '%s ' $dirs)"
