#!/usr/bin/env bash
# Every committed .terraform.lock.hcl must carry provider checksums for the four platforms this repo is
# worked on: Linux and macOS, on amd64 and arm64. Run by scripts/check.sh; nothing here needs a network.
#
# Why: `terraform init` on Linux writes one checksum, for Linux. With only that one, `terraform init` on
# a Mac fails with "Failed to install provider from shared cache ... doesn't match any of the checksums
# recorded in the dependency lock file", so the checks cannot run there. Six lock files written by the
# daily run had this on 2026-11-17.
#
# A lock file records one "h1:" checksum per platform it was locked for, so fewer than four for any
# provider means a platform is missing.
set -euo pipefail
cd "$(dirname "$0")/.."

want=4
fail=0
while IFS= read -r f; do
  # Count the "h1:" lines of each provider block.
  while IFS=$'\t' read -r provider count; do
    if [ "$count" -lt "$want" ]; then
      echo "FAIL $f: $provider has $count of $want platform checksums"
      fail=1
    fi
  done < <(awk '
    /^provider "/ { name=$2; gsub(/"/, "", name); n[name]=0; order[++k]=name; next }
    /"h1:/        { n[name]++ }
    END           { for (i=1; i<=k; i++) printf "%s\t%d\n", order[i], n[order[i]] }' "$f")
done < <(git ls-files '*.terraform.lock.hcl')

if [ "$fail" != 0 ]; then
  cat <<'EOF'

Lock each folder named above for all four platforms, then commit the lock file:

  terraform -chdir=<folder> providers lock \
    -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_amd64 -platform=darwin_arm64
EOF
  exit 1
fi
echo "lock files: every provider is locked for $want platforms"
