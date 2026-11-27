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
for v in LBC_CHART_VERSION METRICS_SERVER_CHART_VERSION EXTERNAL_DNS_CHART_VERSION ARGOCD_CHART_VERSION; do
  [[ "${!v}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "FAIL: $v='${!v}' is not a pinned x.y.z version"; fail=1; }
done

for sh in "$HERE/smoke-test.sh" "$HERE/argocd/smoke-test.sh"; do
  bash -n "$sh" || { echo "FAIL: $sh syntax"; fail=1; }
done

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

# app-of-apps: every child Application must match charts.env and point at an existing values file
import os, re
env = dict(re.findall(r"^([A-Z_]+)=(\S+)", open(here + "/charts.env").read(), re.M))
expect = {
    "aws-load-balancer-controller": ("LBC", "aws-load-balancer-controller"),
    "metrics-server": ("METRICS_SERVER", "metrics-server"),
    "external-dns": ("EXTERNAL_DNS", "external-dns"),
}
apps = sorted(glob.glob(here + "/argocd/apps/*.yaml"))
names = sorted(os.path.basename(a)[:-5] for a in apps)
if names != sorted(expect):
    print("FAIL: argocd/apps has", names, "expected", sorted(expect)); bad = 1
root = get("argocd/bootstrap/root-app.yaml")
if root.get("spec", {}).get("source", {}).get("path") != "platform/argocd/apps":
    print("FAIL: root Application must point at platform/argocd/apps"); bad = 1
for a in apps:
    d = docs[a]; n = os.path.basename(a)[:-5]
    if n not in expect: continue
    prefix, chart = expect[n]
    srcs = d["spec"]["sources"]
    c = [s for s in srcs if "chart" in s]
    refs = [s for s in srcs if s.get("ref") == "values"]
    if len(c) != 1 or len(refs) != 1:
        print(f"FAIL: {n} needs one chart source and one ref: values source"); bad = 1; continue
    if c[0]["chart"] != chart or c[0]["targetRevision"] != env[prefix + "_CHART_VERSION"]:
        print(f"FAIL: {n} chart/version differs from charts.env"); bad = 1
    if c[0]["repoURL"].rstrip("/") != env[prefix + "_CHART_REPO"].rstrip("/"):
        print(f"FAIL: {n} chart repo differs from charts.env"); bad = 1
    for vf in c[0]["helm"]["valueFiles"]:
        if not os.path.isfile(here + "/" + vf.replace("$values/platform/", "")):
            print(f"FAIL: {n} values file {vf} does not exist"); bad = 1
    if d["spec"]["project"] != "platform":
        print(f"FAIL: {n} must use the platform AppProject"); bad = 1
    allowed = get("argocd/bootstrap/project.yaml")["spec"]["sourceRepos"]
    for s in srcs:
        if s["repoURL"].rstrip("/") not in [x.rstrip("/") for x in allowed]:
            print(f"FAIL: {n} source {s['repoURL']} not allowed by the AppProject"); bad = 1
sys.exit(bad)
PYEOF

[ $fail -eq 0 ] && echo "platform lint passed" || { echo "platform lint FAILED"; exit 1; }
