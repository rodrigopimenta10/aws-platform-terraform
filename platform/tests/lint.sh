#!/usr/bin/env bash
# Offline checks for platform/: no Docker, no cluster, no network.
#   - every YAML file parses
#   - chart versions are pinned (plain x.y.z, never "latest" or a range)
#   - every chart has a base values file and a kind override, and both parse
#   - the smoke test script has valid bash syntax
#   - the ServiceAccount names that Pod Identity associations must match are set
# Usage: platform/tests/lint.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PY="${PYTHON:-python3}"
command -v "$PY" >/dev/null
"$PY" -c 'import yaml' 2>/dev/null || PY="$HOME/.local/aws-platform-tools/venv/bin/python"

fail=0
. "$HERE/charts.env"
for v in LBC_CHART_VERSION METRICS_SERVER_CHART_VERSION EXTERNAL_DNS_CHART_VERSION; do
  [[ "${!v}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "FAIL: $v='${!v}' is not a pinned x.y.z version"; fail=1; }
done

bash -n "$HERE/smoke-test.sh" || { echo "FAIL: smoke-test.sh syntax"; fail=1; }

for c in aws-load-balancer-controller metrics-server external-dns; do
  for f in "$HERE/$c/values.yaml" "$HERE/kind/$c.yaml"; do
    [ -f "$f" ] || { echo "FAIL: missing $f"; fail=1; }
  done
done

"$PY" - "$HERE" <<'PYEOF' || fail=1
import sys, glob, yaml
here = sys.argv[1]
bad = 0
docs = {}
for f in sorted(glob.glob(here + "/**/*.yaml", recursive=True)):
    try:
        docs[f] = yaml.safe_load(open(f))
    except yaml.YAMLError as e:
        print("FAIL: cannot parse", f, e); bad = 1
def get(rel):
    return docs.get(here + "/" + rel) or {}
for chart, sa in (("aws-load-balancer-controller", "aws-load-balancer-controller"), ("external-dns", "external-dns")):
    name = get(chart + "/values.yaml").get("serviceAccount", {}).get("name")
    if name != sa:
        print(f"FAIL: {chart} serviceAccount.name is {name!r}, expected {sa!r}"); bad = 1
sys.exit(bad)
PYEOF

[ $fail -eq 0 ] && echo "platform lint passed" || { echo "platform lint FAILED"; exit 1; }
