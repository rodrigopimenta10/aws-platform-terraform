#!/usr/bin/env bash
# Trial runner for docs/emulator-trial.md: runs every module's integration tests against Moto or against
# AWS Emulator and records pass/fail, timings and the server's request log. Not part of scripts/check.sh.
#
# The committed tests are never edited. The script copies modules/ and envs/ to a work folder outside the
# repo and tests the copies. For the emulator, the copies get two mechanical changes (see prepare()):
# the endpoint URL (http://127.0.0.1:5000 becomes https://127.0.0.1:9297) and, with authentication on,
# the two hard-coded fake access key lines are removed so the emulator's own keys are used.
#
# Usage: docs/emulator-trial/run.sh moto|emulator [pass-label] [dir...]
#   EMULATOR_AUTH=off   start the emulator with --auth off and keep the tests' fake keys   (default: on)
#   ALIGN_ACCOUNT=1     diagnostic: replace Moto's account ID in the test copies with the emulator's
#   DROP_RUN=name       diagnostic: delete one run block from the test copies, to see what follows a failure
#   TF_DEBUG=1          write Terraform's debug log per module (lists every AWS API call and its status)
#   WORK=/some/dir      where copies, logs and results go       (default: $TMPDIR/emulator-trial)
#
# Needs: the repo toolchain (scripts/bootstrap.sh), Docker, and the image built from
# docs/emulator-trial/Dockerfile as "aws-emulator-trial". No real AWS credentials are read or used.
set -uo pipefail

TARGET="${1:?usage: run.sh moto|emulator [pass-label] [dir...]}"; shift
PASS="${1:-1}"; [ $# -gt 0 ] && shift
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="${WORK:-${TMPDIR:-/tmp}/emulator-trial}"
TOOLS_DIR="${TOOLS_DIR:-$HOME/.local/aws-platform-tools}"
# shellcheck disable=SC1091
[ -f "$TOOLS_DIR/env.sh" ] && . "$TOOLS_DIR/env.sh"
AWS_PROVIDER_VERSION="$(awk '$1=="terraform-provider-aws" {print $2}' "$ROOT/.tool-versions")"

MOTO_PORT=5000
EMU_PORT=9297
EMU_IMAGE="${EMU_IMAGE:-aws-emulator-trial}"
EMU_NAME=aws-emulator-trial
EMU_HOME="$WORK/emulator-home"   # mounted as the emulator's ~/.aws/emulator; the real ~/.aws is never touched
EMULATOR_AUTH="${EMULATOR_AUTH:-on}"
ALIGN_ACCOUNT="${ALIGN_ACCOUNT:-0}"   # Moto answers as account 123456789012, the emulator as 000000000000
TF_DEBUG="${TF_DEBUG:-0}"
DROP_RUN="${DROP_RUN:-}"

SRC="$WORK/src-$TARGET"
OUT="$WORK/results/$TARGET/$PASS"
mkdir -p "$OUT" "$EMU_HOME"

# Never let real credentials or the user's AWS config reach either server.
unset AWS_PROFILE AWS_SESSION_TOKEN AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_ENDPOINT_URL
export AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null
export AWS_EC2_METADATA_DISABLED=true AWS_DEFAULT_REGION=us-east-1 AWS_REGION=us-east-1

now() { python3 -c 'import time; print(f"{time.time():.3f}")'; }
since() { python3 -c 'import sys,time; print(f"{time.time()-float(sys.argv[1]):.2f}")' "$1"; }

prepare() {
  rm -rf "$SRC"; mkdir -p "$SRC"
  rsync -a --exclude .terraform --exclude .terraform.lock.hcl "$ROOT/modules" "$ROOT/envs" "$SRC/"
  # The lock files written on Linux hold one checksum, which macOS rejects. The copies drop the lock file
  # and install the pinned provider from a private mirror of the plugin cache, with no network.
  local mirror="$WORK/mirror-$TARGET/registry.terraform.io/hashicorp/aws"
  rm -rf "$WORK/mirror-$TARGET"; mkdir -p "$mirror/$AWS_PROVIDER_VERSION"
  for p in "$TF_PLUGIN_CACHE_DIR/registry.terraform.io/hashicorp/aws/$AWS_PROVIDER_VERSION"/*; do
    ln -sfn "$p" "$mirror/$AWS_PROVIDER_VERSION/$(basename "$p")"
  done
  cat > "$WORK/terraformrc-$TARGET" <<EOF
provider_installation {
  filesystem_mirror {
    path = "$WORK/mirror-$TARGET"
  }
}
EOF
  export TF_CLI_CONFIG_FILE="$WORK/terraformrc-$TARGET"
  unset TF_PLUGIN_CACHE_DIR

  if [ "$TARGET" = emulator ]; then
    find "$SRC" -name 'integration.tftest.hcl' | while read -r f; do
      sed -i.bak "s#http://127.0.0.1:$MOTO_PORT#https://127.0.0.1:$EMU_PORT#g" "$f"
      if [ "$EMULATOR_AUTH" = on ]; then
        # The emulator only accepts the keys it generated for this run; they come from its credentials file.
        sed -i.bak -E '/^[[:space:]]*(access_key|secret_key)[[:space:]]*=/d' "$f"
      fi
      [ "$ALIGN_ACCOUNT" = 1 ] && sed -i.bak 's/123456789012/000000000000/g' "$f"
      [ -n "$DROP_RUN" ] && DROP_RUN="$DROP_RUN" perl -0pi -e 's/^run "\Q$ENV{DROP_RUN}\E" \{.*?^\}\n//ms' "$f"
      rm -f "$f.bak"
    done
  fi
}

moto_start() {
  if curl -fsS -o /dev/null "http://127.0.0.1:$MOTO_PORT/moto-api/" 2>/dev/null; then
    echo "a Moto server is already answering on port $MOTO_PORT: stop it first" >&2; exit 1
  fi
  local t0; t0="$(now)"
  moto_server -H 127.0.0.1 -p "$MOTO_PORT" >"$OUT/$1.server.log" 2>&1 &
  SERVER_PID=$!
  for _ in $(seq 1 300); do curl -fsS -o /dev/null "http://127.0.0.1:$MOTO_PORT/moto-api/" 2>/dev/null && break; sleep 0.1; done
  STARTUP="$(since "$t0")"
}
moto_stop() { kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; }

emu_start() {
  docker rm -f "$EMU_NAME" >/dev/null 2>&1
  rm -rf "${EMU_HOME:?}/$EMU_PORT"
  local t0; t0="$(now)"
  # AWS's documented command (getting-started-docker), detached, with telemetry off. Published on loopback only.
  docker run -d --name "$EMU_NAME" --memory=2g --memory-swap=2g -p "127.0.0.1:$EMU_PORT:$EMU_PORT" \
    -e EMULATOR_TELEMETRY=off -v "$EMU_HOME:/home/emulator/.aws/emulator" \
    "$EMU_IMAGE" -p "$EMU_PORT" --telemetry off --auth "$EMULATOR_AUTH" >/dev/null
  for _ in $(seq 1 600); do
    [ -f "$EMU_HOME/$EMU_PORT/ca.pem" ] && curl -fsS -o /dev/null --cacert "$EMU_HOME/$EMU_PORT/ca.pem" \
      "https://127.0.0.1:$EMU_PORT/__admin/health" 2>/dev/null && break
    sleep 0.1
  done
  STARTUP="$(since "$t0")"
  export AWS_CA_BUNDLE="$EMU_HOME/$EMU_PORT/ca.pem"
  if [ "$EMULATOR_AUTH" = on ]; then
    export AWS_SHARED_CREDENTIALS_FILE="$EMU_HOME/$EMU_PORT/emulator_credentials"
  fi
}
emu_stop() {
  docker logs "$EMU_NAME" >"$OUT/$1.server.log" 2>"$OUT/$1.server.stderr"
  docker stats --no-stream --format '{{.MemUsage}}' "$EMU_NAME" >"$OUT/$1.mem" 2>/dev/null
  docker rm -f "$EMU_NAME" >/dev/null 2>&1
}

prepare
if [ $# -gt 0 ]; then dirs=("$@"); else
  dirs=()
  for d in modules/* envs/*; do [ -f "$ROOT/$d/tests/integration.tftest.hcl" ] && dirs+=("$d"); done
fi

printf 'target\tpass\tmodule\tresult\tstartup_s\tinit_s\ttest_s\tsummary\n' >"$OUT/summary.tsv"
for d in "${dirs[@]}"; do
  name="${d//\//_}"
  # A fresh server per module: Moto has a reset route, the emulator has none, so both are restarted
  # to keep the two sides comparable.
  if [ "$TARGET" = moto ]; then
    export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test
    moto_start "$name"
  else
    emu_start "$name"
  fi
  export TF_DATA_DIR="$WORK/tfdata/$TARGET/$name"
  rm -rf "$TF_DATA_DIR"
  t0="$(now)"
  (cd "$SRC/$d" && terraform init -backend=false -input=false -no-color >"$OUT/$name.init.log" 2>&1)
  init_s="$(since "$t0")"
  t0="$(now)"
  if [ "$TF_DEBUG" = 1 ]; then export TF_LOG=DEBUG TF_LOG_PATH="$OUT/$name.tf-debug.log"; rm -f "$TF_LOG_PATH"; fi
  (cd "$SRC/$d" && terraform test -no-color -verbose -filter=tests/integration.tftest.hcl >"$OUT/$name.test.log" 2>&1)
  rc=$?
  test_s="$(since "$t0")"
  if [ "$TARGET" = moto ]; then moto_stop; else emu_stop "$name"; fi
  result=pass; [ $rc -ne 0 ] && result=FAIL
  summary="$(grep -E '^(Success|Failure)!' "$OUT/$name.test.log" | tail -1)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$TARGET" "$PASS" "$d" "$result" "$STARTUP" "$init_s" "$test_s" "$summary" | tee -a "$OUT/summary.tsv"
done
