#!/usr/bin/env bash
# Installs the three platform charts into a throwaway local cluster (kind = Kubernetes in Docker)
# and waits until every Deployment is available. No AWS account is involved.
#
# Usage: platform/smoke-test.sh            # create cluster, install, check, delete cluster
#        KEEP_CLUSTER=1 platform/smoke-test.sh   # leave the cluster up to poke at (kubectl --context kind-platform-smoke)
# Needs: docker (running), kind, helm, kubectl. Exits 2 if one is missing.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/charts.env"

CLUSTER="${KIND_CLUSTER_NAME:-platform-smoke}"
CTX="kind-$CLUSTER"
TIMEOUT="${SMOKE_TIMEOUT:-300s}"

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
kind create cluster --name "$CLUSTER" --config "$HERE/kind/cluster.yaml" --wait 120s

helm repo add eks "$LBC_CHART_REPO" >/dev/null
helm repo add metrics-server "$METRICS_SERVER_CHART_REPO" >/dev/null
helm repo add external-dns "$EXTERNAL_DNS_CHART_REPO" >/dev/null
helm repo update >/dev/null

install() { # name chart version dir namespace
  echo "== installing $1 $3"
  helm --kube-context "$CTX" upgrade --install "$1" "$2" --version "$3" \
    --namespace "$5" --create-namespace \
    -f "$HERE/$4/values.yaml" -f "$HERE/kind/$4.yaml" --wait --timeout "$TIMEOUT"
}

install metrics-server "$METRICS_SERVER_CHART" "$METRICS_SERVER_CHART_VERSION" metrics-server kube-system
install external-dns "$EXTERNAL_DNS_CHART" "$EXTERNAL_DNS_CHART_VERSION" external-dns external-dns
# The LBC webhook needs a certificate; the chart generates one itself when cert-manager is absent.
install aws-load-balancer-controller "$LBC_CHART" "$LBC_CHART_VERSION" aws-load-balancer-controller kube-system

echo "== checking deployments"
kubectl --context "$CTX" -n kube-system rollout status deploy/metrics-server --timeout="$TIMEOUT"
kubectl --context "$CTX" -n kube-system rollout status deploy/aws-load-balancer-controller --timeout="$TIMEOUT"
kubectl --context "$CTX" -n external-dns rollout status deploy/external-dns --timeout="$TIMEOUT"

echo "== metrics API answers (can take a minute after install)"
for _ in $(seq 1 30); do
  kubectl --context "$CTX" top nodes 2>/dev/null && ok=1 && break
  sleep 5
done
[ "${ok:-0}" = 1 ] || { echo "metrics-server never served node metrics" >&2; exit 1; }

echo "SMOKE TEST PASSED"
