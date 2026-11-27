#!/usr/bin/env bash
# Installs Argo CD into a throwaway kind cluster, applies the app-of-apps root and checks that
# Argo CD creates the three child Applications and can render each chart with its values file.
# The children are not required to become Healthy: they need per-cluster inputs and AWS.
#
# Usage: platform/argocd/smoke-test.sh
#        REPO_URL=https://github.com/me/fork.git REVISION=my-branch platform/argocd/smoke-test.sh
#        KEEP_CLUSTER=1 platform/argocd/smoke-test.sh
# Needs: docker (running), kind, helm, kubectl, network access to GitHub. Exits 2 if a tool is missing.
# Argo CD pulls from Git, so the revision under test must be pushed first.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/../charts.env"

CLUSTER="${KIND_CLUSTER_NAME:-argocd-smoke}"
CTX="kind-$CLUSTER"
TIMEOUT="${SMOKE_TIMEOUT:-300s}"
REPO_URL="${REPO_URL:-}"
REVISION="${REVISION:-}"

for t in docker kind helm kubectl; do
  command -v "$t" >/dev/null || { echo "missing $t: install it to run the smoke test" >&2; exit 2; }
done
docker info >/dev/null 2>&1 || { echo "docker daemon is not running" >&2; exit 2; }

cleanup() {
  if [ "${KEEP_CLUSTER:-0}" = 1 ]; then
    echo "KEEP_CLUSTER=1: cluster '$CLUSTER' left running; delete with: kind delete cluster --name $CLUSTER"
  else
    kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true
kind create cluster --name "$CLUSTER" --config "$HERE/../kind/cluster.yaml" --wait 120s

helm repo add argo "$ARGOCD_CHART_REPO" >/dev/null
helm repo update >/dev/null
echo "== installing argo-cd $ARGOCD_CHART_VERSION"
helm --kube-context "$CTX" upgrade --install argocd "$ARGOCD_CHART" --version "$ARGOCD_CHART_VERSION" \
  --namespace argocd --create-namespace -f "$HERE/values.yaml" --wait --timeout "$TIMEOUT"

echo "== applying project and root Application"
kubectl --context "$CTX" apply -f "$HERE/bootstrap/project.yaml"
root="$HERE/bootstrap/root-app.yaml"
if [ -n "$REPO_URL" ] || [ -n "$REVISION" ]; then
  # Point the root at a fork or branch without editing the committed file.
  sed -e "s#^\( *repoURL:\).*#\1 ${REPO_URL:-https://github.com/rodrigopimenta10/aws-platform-terraform.git}#" \
      -e "s#^\( *targetRevision:\).*#\1 ${REVISION:-main}#" "$root" | kubectl --context "$CTX" apply -f -
else
  kubectl --context "$CTX" apply -f "$root"
fi

echo "== waiting for the child Applications to appear"
want="aws-load-balancer-controller external-dns metrics-server"
for _ in $(seq 1 60); do
  have="$(kubectl --context "$CTX" -n argocd get applications -o name 2>/dev/null | sed 's#.*/##' | grep -v '^platform$' | sort | tr '\n' ' ' || true)"
  [ "$have" = "$want " ] && break
  sleep 5
done
[ "$have" = "$want " ] || { echo "expected applications: $want; found: $have" >&2; exit 1; }

echo "== checking each Application rendered (no ComparisonError)"
for app in $want; do
  for _ in $(seq 1 30); do
    status="$(kubectl --context "$CTX" -n argocd get application "$app" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
    [ -n "$status" ] && [ "$status" != Unknown ] && break
    sleep 5
  done
  err="$(kubectl --context "$CTX" -n argocd get application "$app" \
    -o jsonpath='{.status.conditions[?(@.type=="ComparisonError")].message}' 2>/dev/null || true)"
  [ -z "$err" ] || { echo "$app: ComparisonError: $err" >&2; exit 1; }
  echo "$app: sync=$status"
done

echo "SMOKE TEST PASSED"
