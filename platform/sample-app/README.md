# sample-app

A tiny Go HTTP server plus everything needed to run it on the cluster: a multi-stage Dockerfile, and a
Deployment, Service, Ingress, PodDisruptionBudget and NetworkPolicy. Its job is to be a realistic workload
that exercises the platform: the Ingress is turned into an Application Load Balancer by the
aws-load-balancer-controller, external-dns publishes its hostname, and the PodDisruptionBudget shows how
node drains stay safe.

## Layout
```
sample-app/
  main.go, main_test.go, go.mod   the server: / , /healthz, graceful shutdown on SIGTERM
  Dockerfile                      stage 1 builds a static binary, stage 2 is distroless and non-root
  k8s/namespace.yaml              one namespace, so everything can be removed with one delete
  k8s/deployment.yaml             2 replicas, rolling update with no unavailable pods, probes, hardened
  k8s/service.yaml                ClusterIP on port 80 -> container port "http"
  k8s/ingress.yaml                class alb, HTTPS, target-type ip, health check on /healthz
  k8s/pdb.yaml                    minAvailable: 1
  k8s/networkpolicy.yaml          only TCP 8080 in, nothing out
```

## Run it
```bash
cd platform/sample-app && go test ./...         # unit tests, no Docker
docker build -t sample-app:dev .                # needs Docker
docker run --rm -p 8080:8080 sample-app:dev && curl localhost:8080/healthz
platform/tests/lint.sh                          # from the repo root: manifests agree with each other
```

To deploy: push the image to the ECR repository from `modules/ecr`, replace the three `REPLACE_ME` values
(image tag, `APP_VERSION`, certificate ARN) and the hostname, then `kubectl apply -f k8s/`. It can also be
added to Argo CD as one more Application that points at `platform/sample-app/k8s`.

## Why it's built this way
- **Multi-stage build:** the Go toolchain is only in the build stage. The final image holds one static
  binary (a few MB), so there is less to scan and less for an attacker to use.
- **Distroless `nonroot` base and `USER 65532`:** no shell, no package manager, not root. The Deployment
  repeats this with `runAsNonRoot`, a read-only root filesystem, dropped capabilities and no service
  account token, so the manifest is safe even if someone swaps the image.
- **Probes on `/healthz`:** readiness decides when the load balancer may send traffic; liveness restarts a
  stuck process. `maxUnavailable: 0` means a new pod must be ready before an old one stops.
- **Graceful shutdown:** on SIGTERM the server finishes in-flight requests, so rollouts and drains do not
  drop them.
- **PodDisruptionBudget:** a *voluntary* disruption (node drain, Karpenter consolidation, cluster upgrade)
  may evict one of the two pods at a time, never both. `minAvailable` must stay below `replicas`, or the
  node could never be drained; `platform/tests/lint.sh` enforces this.
- **`target-type: ip`:** the ALB sends to pod IPs directly (works with the VPC CNI), skipping an extra hop
  through node ports.
- **NetworkPolicy:** default-deny egress for an app that calls nothing. It only takes effect if the CNI
  enforces policies (the vpc-cni add-on must have network policy enabled).
- **checkov skips:** `CKV_K8S_43` (image digest) because the image is a placeholder, and `CKV_DOCKER_2`
  (HEALTHCHECK) because Kubernetes probes replace it and distroless has no shell. Both are written next to
  the code with the reason.

## Not tested here
`docker build` and a real deploy need Docker and a cluster; the sandbox had neither. Offline coverage is the
Go tests, `platform/tests/lint.sh` and checkov (`checkov -d platform/sample-app --framework kubernetes,dockerfile`).
`scripts/check.sh` does not run the platform lint or the Kubernetes scan.
