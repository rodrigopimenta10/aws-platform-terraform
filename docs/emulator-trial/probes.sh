#!/usr/bin/env bash
# Probes for docs/emulator-trial.md: small configurations outside the repo's modules, applied with
# `terraform test` to Moto and to AWS Emulator, to compare the two on (a) the Moto gaps the module READMEs
# record and (b) requests that real AWS refuses. The .tf files are generated into $WORK, not committed,
# so the repo's fmt, tflint and checkov checks never see them.
#
# Usage: docs/emulator-trial/probes.sh moto|emulator
# Needs the same things as run.sh. Start nothing else on port 5000 (Moto) or 9297 (emulator).
set -uo pipefail

TARGET="${1:?usage: probes.sh moto|emulator}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="${WORK:-${TMPDIR:-/tmp}/emulator-trial}"
TOOLS_DIR="${TOOLS_DIR:-$HOME/.local/aws-platform-tools}"
# shellcheck disable=SC1091
[ -f "$TOOLS_DIR/env.sh" ] && . "$TOOLS_DIR/env.sh"
AWS_PROVIDER_VERSION="$(awk '$1=="terraform-provider-aws" {print $2}' "$ROOT/.tool-versions")"
P="$WORK/probes/$TARGET"
OUT="$WORK/results/probes/$TARGET"
EMU_HOME="$WORK/emulator-home"
EMU_NAME=aws-emulator-trial
rm -rf "$P"; mkdir -p "$P" "$OUT" "$EMU_HOME"

unset AWS_PROFILE AWS_SESSION_TOKEN AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_ENDPOINT_URL
export AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null
export AWS_EC2_METADATA_DISABLED=true AWS_DEFAULT_REGION=us-east-1 AWS_REGION=us-east-1

mirror="$WORK/mirror-probes-$TARGET/registry.terraform.io/hashicorp/aws"
rm -rf "$WORK/mirror-probes-$TARGET"; mkdir -p "$mirror/$AWS_PROVIDER_VERSION"
for p in "$TF_PLUGIN_CACHE_DIR/registry.terraform.io/hashicorp/aws/$AWS_PROVIDER_VERSION"/*; do
  ln -sfn "$p" "$mirror/$AWS_PROVIDER_VERSION/$(basename "$p")"
done
printf 'provider_installation {\n  filesystem_mirror {\n    path = "%s"\n  }\n}\n' "$WORK/mirror-probes-$TARGET" >"$WORK/terraformrc-probes-$TARGET"
export TF_CLI_CONFIG_FILE="$WORK/terraformrc-probes-$TARGET"
unset TF_PLUGIN_CACHE_DIR

if [ "$TARGET" = moto ]; then ENDPOINT="http://127.0.0.1:5000"; else ENDPOINT="https://127.0.0.1:9297"; fi

server_start() {
  if [ "$TARGET" = moto ]; then
    export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test
    moto_server -H 127.0.0.1 -p 5000 >"$OUT/$1.server.log" 2>&1 &
    SERVER_PID=$!
    for _ in $(seq 1 300); do curl -fsS -o /dev/null "$ENDPOINT/moto-api/" 2>/dev/null && break; sleep 0.1; done
  else
    docker rm -f "$EMU_NAME" >/dev/null 2>&1; rm -rf "${EMU_HOME:?}/9297"
    docker run -d --name "$EMU_NAME" --memory=2g --memory-swap=2g -p 127.0.0.1:9297:9297 \
      -e EMULATOR_TELEMETRY=off -v "$EMU_HOME:/home/emulator/.aws/emulator" \
      "${EMU_IMAGE:-aws-emulator-trial}" -p 9297 --telemetry off >/dev/null
    for _ in $(seq 1 600); do
      [ -f "$EMU_HOME/9297/ca.pem" ] && curl -fsS -o /dev/null --cacert "$EMU_HOME/9297/ca.pem" "$ENDPOINT/__admin/health" 2>/dev/null && break
      sleep 0.1
    done
    export AWS_CA_BUNDLE="$EMU_HOME/9297/ca.pem" AWS_SHARED_CREDENTIALS_FILE="$EMU_HOME/9297/emulator_credentials"
  fi
}
server_stop() {
  if [ "$TARGET" = moto ]; then kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null
  else docker rm -f "$EMU_NAME" >/dev/null 2>&1; fi
}

# probe <name> <timeout seconds>: main.tf comes on stdin.
probe() {
  local name="$1" limit="$2" d="$P/$1"
  mkdir -p "$d/tests"
  {
    cat <<'EOF'
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

data "aws_caller_identity" "current" {}

EOF
    cat
  } >"$d/main.tf"
  cat >"$d/tests/probe.tftest.hcl" <<EOF
provider "aws" {
  region                      = "us-east-1"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  s3_use_path_style           = true

  endpoints {
    ec2 = "$ENDPOINT"
    iam = "$ENDPOINT"
    kms = "$ENDPOINT"
    s3  = "$ENDPOINT"
    sts = "$ENDPOINT"
  }
}

run "apply" {
  command = apply
}
EOF
  server_start "$name"
  export TF_DATA_DIR="$WORK/tfdata/probes-$TARGET/$name"; rm -rf "$TF_DATA_DIR"
  local t0 rc
  t0="$(python3 -c 'import time; print(time.time())')"
  (
    cd "$d" && terraform init -backend=false -input=false -no-color >"$OUT/$name.init.log" 2>&1 &&
      perl -e 'alarm shift; exec @ARGV' "$limit" terraform test -no-color -verbose >"$OUT/$name.test.log" 2>&1
  )
  rc=$?
  local secs; secs="$(python3 -c 'import sys,time; print(f"{time.time()-float(sys.argv[1]):.1f}")' "$t0")"
  pkill -f "terraform-provider-aws_v$AWS_PROVIDER_VERSION" 2>/dev/null
  server_stop
  local verdict="applied"
  [ $rc -ne 0 ] && verdict="refused"
  [ $rc -eq 142 ] && verdict="hung (stopped after ${limit}s)"
  local err; err="$(grep -m1 -E '^Error: ' "$OUT/$name.test.log" | cut -c1-300)"
  printf '%s\t%s\t%s\t%ss\t%s\n' "$TARGET" "$name" "$verdict" "$secs" "$err" | tee -a "$OUT/summary.tsv"
}

: >"$OUT/summary.tsv"

# --- Moto gaps the module READMEs record ---------------------------------------------------------------

# modules/state-backend/README.md: Moto does not return NewerNoncurrentVersions, so the provider waits.
probe s3-lifecycle-newer-noncurrent-versions 240 <<'EOF'
resource "aws_s3_bucket" "this" {
  bucket        = "emulator-trial-lifecycle-probe"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket     = aws_s3_bucket.this.id
  depends_on = [aws_s3_bucket_versioning.this]

  rule {
    id     = "keep-last-three"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      newer_noncurrent_versions = 3
      noncurrent_days           = 30
    }
  }
}
EOF

# modules/github-oidc/README.md: Moto ships no AWS-managed policies such as ReadOnlyAccess.
probe iam-attach-aws-managed-policy 120 <<'EOF'
resource "aws_iam_role" "this" {
  name = "emulator-trial-managed-policy-probe"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
EOF

# --- Requests real AWS refuses -------------------------------------------------------------------------

# AWS: MalformedPolicyDocumentException, the key policy names a principal that does not exist.
probe kms-key-policy-unknown-principal 120 <<'EOF'
resource "aws_kms_key" "this" {
  description             = "emulator trial probe"
  deletion_window_in_days = 7
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Root"
        Effect    = "Allow"
        Action    = "kms:*"
        Resource  = "*"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      },
      {
        Sid       = "Ghost"
        Effect    = "Allow"
        Action    = "kms:Decrypt"
        Resource  = "*"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/does-not-exist" }
      },
    ]
  })
}
EOF

# AWS: MalformedPolicyDocument "Invalid principal in policy", the trust policy names a role that does not exist.
probe iam-trust-policy-unknown-principal 120 <<'EOF'
resource "aws_iam_role" "this" {
  name = "emulator-trial-trust-probe"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/does-not-exist" }
    }]
  })
}
EOF

# AWS: InvalidSubnet.Range, the subnet's CIDR is outside the VPC's.
probe ec2-subnet-outside-vpc-cidr 120 <<'EOF'
resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "this" {
  vpc_id     = aws_vpc.this.id
  cidr_block = "192.168.0.0/24"
}
EOF

# AWS: InvalidParameterValue, a NAT gateway needs an Elastic IP allocation that exists.
probe ec2-nat-gateway-unknown-eip 120 <<'EOF'
resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "this" {
  vpc_id     = aws_vpc.this.id
  cidr_block = "10.0.0.0/24"
}

resource "aws_nat_gateway" "this" {
  subnet_id     = aws_subnet.this.id
  allocation_id = "eipalloc-0123456789abcdef0"
}
EOF

# AWS: MalformedPolicy, a bucket policy whose Resource is another bucket.
probe s3-bucket-policy-wrong-resource 120 <<'EOF'
resource "aws_s3_bucket" "this" {
  bucket        = "emulator-trial-policy-probe"
  force_destroy = true
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Deny"
      Action    = "s3:*"
      Principal = "*"
      Resource  = "arn:aws:s3:::some-other-bucket/*"
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}
EOF
