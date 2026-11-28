# Stage 1: build a static binary. The Go toolchain (hundreds of MB) stays in this stage.
FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY *.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/sample-app .

# Stage 2: an image with nothing but the binary. "nonroot" runs as UID 65532, not root.
#checkov:skip=CKV_DOCKER_2:Kubernetes liveness and readiness probes check /healthz; the distroless image has no shell or curl for a HEALTHCHECK command.
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/sample-app /sample-app
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/sample-app"]
