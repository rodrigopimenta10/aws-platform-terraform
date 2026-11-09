#!/usr/bin/env bash
# Installs the toolchain this repo needs: Terraform, the AWS provider, tflint, checkov and Moto.
# Safe to re-run. Works on Linux x86_64/arm64 (the Claude Code cloud VM, CI) and macOS.
#
# Tools go to $TOOLS_DIR (default: ~/.local/aws-platform-tools) so nothing system-wide changes.
# Versions are pinned in .tool-versions at the repo root.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS_DIR="${TOOLS_DIR:-$HOME/.local/aws-platform-tools}"
BIN="$TOOLS_DIR/bin"
mkdir -p "$BIN"

ver() { awk -v t="$1" '$1==t {print $2}' "$ROOT/.tool-versions"; }
TF_VERSION="$(ver terraform)"
AWS_PROVIDER_VERSION="$(ver terraform-provider-aws)"
TFLINT_VERSION="$(ver tflint)"
MOTO_VERSION="$(ver moto)"
CHECKOV_VERSION="$(ver checkov)"

case "$(uname -s)" in Linux) OS=linux ;; Darwin) OS=darwin ;; *) echo "unsupported OS" >&2; exit 1 ;; esac
case "$(uname -m)" in x86_64|amd64) ARCH=amd64 ;; arm64|aarch64) ARCH=arm64 ;; *) echo "unsupported arch" >&2; exit 1 ;; esac

need_unzip() {
  command -v unzip >/dev/null && return
  if command -v apt-get >/dev/null; then
    (sudo -n true 2>/dev/null && sudo apt-get install -y -qq unzip) || apt-get install -y -qq unzip
  else
    python3 -c 'import zipfile' # fall back to python's zipfile below
  fi
}
unzip_to() { # zip dest
  if command -v unzip >/dev/null; then unzip -oq "$1" -d "$2"
  else python3 -c 'import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$1" "$2"; fi
}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
need_unzip || true

# --- Terraform (from releases.hashicorp.com) ---
if ! "$BIN/terraform" version 2>/dev/null | grep -q "v$TF_VERSION"; then
  echo "Installing Terraform $TF_VERSION"
  curl -fsSL -o "$tmp/tf.zip" "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_${OS}_${ARCH}.zip"
  unzip_to "$tmp/tf.zip" "$tmp/tf" && install -m 0755 "$tmp/tf/terraform" "$BIN/terraform"
fi

# --- Provider install path ---
# Normally `terraform init` downloads providers via registry.terraform.io. If that host is blocked
# (some sandboxed networks only allow releases.hashicorp.com), build a local filesystem mirror instead.
TF_RC="$TOOLS_DIR/terraformrc"
if curl -fsS --max-time 10 -o /dev/null https://registry.terraform.io/.well-known/terraform.json; then
  echo "registry.terraform.io reachable: providers install normally"
  : > "$TF_RC"
else
  echo "registry.terraform.io not reachable: building a provider mirror from releases.hashicorp.com"
  MIRROR="$TOOLS_DIR/provider-mirror/registry.terraform.io/hashicorp/aws"
  mkdir -p "$MIRROR"
  zip="terraform-provider-aws_${AWS_PROVIDER_VERSION}_${OS}_${ARCH}.zip"
  [ -f "$MIRROR/$zip" ] || curl -fsSL -o "$MIRROR/$zip" \
    "https://releases.hashicorp.com/terraform-provider-aws/${AWS_PROVIDER_VERSION}/${zip}"
  cat > "$TF_RC" <<EOF
provider_installation {
  filesystem_mirror {
    path    = "$TOOLS_DIR/provider-mirror"
    include = ["registry.terraform.io/hashicorp/*"]
  }
  direct {
    exclude = ["registry.terraform.io/hashicorp/*"]
  }
}
EOF
fi

# --- tflint + AWS ruleset (from GitHub releases) ---
if ! "$BIN/tflint" --version 2>/dev/null | grep -q "${TFLINT_VERSION#v}"; then
  echo "Installing tflint $TFLINT_VERSION"
  curl -fsSL -o "$tmp/tflint.zip" \
    "https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}/tflint_${OS}_${ARCH}.zip"
  unzip_to "$tmp/tflint.zip" "$tmp/tflint" && install -m 0755 "$tmp/tflint/tflint" "$BIN/tflint"
fi

# --- checkov + Moto (from PyPI, in a venv) ---
VENV="$TOOLS_DIR/venv"
if [ ! -x "$VENV/bin/python" ]; then python3 -m venv "$VENV"; fi
"$VENV/bin/pip" install -q --upgrade pip
"$VENV/bin/pip" install -q "checkov==${CHECKOV_VERSION}" "moto[server]==${MOTO_VERSION}"
ln -sf "$VENV/bin/checkov" "$BIN/checkov"
ln -sf "$VENV/bin/moto_server" "$BIN/moto_server"

cat > "$TOOLS_DIR/env.sh" <<EOF
export PATH="$BIN:\$PATH"
export TF_CLI_CONFIG_FILE="$TF_RC"
export TF_PLUGIN_CACHE_DIR="$TOOLS_DIR/plugin-cache"
export TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true
export CHECKOV_RUN_SCA_PACKAGE_SCAN_V2=false
EOF
mkdir -p "$TOOLS_DIR/plugin-cache"

# shellcheck disable=SC1091
. "$TOOLS_DIR/env.sh"
terraform version | head -1
tflint --version | head -1
echo "checkov $(checkov --version)"
echo "Toolchain ready. Run: . $TOOLS_DIR/env.sh"
