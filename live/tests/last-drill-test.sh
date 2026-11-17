#!/usr/bin/env bash
# Offline test of live/last-drill.sh. Run by scripts/check.sh; nothing here talks to GitHub.
#
# A fake `gh` command is put first on PATH and a small Git history is made in a temporary folder:
#   A -- B -- C -- D     on main,   X on a side branch that is not an ancestor of D
# The fake answers from RUNS, a list of "<run id>:<commit name>:<what its Drill jobs did>", newest first,
# where the last part is "success" (a drill passed), "none" (the run drilled nothing: no stack had
# changed, or it refused a push that changes protected paths) or "skipped".
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git -C "$tmp" init -q -b main
commit() {
  git -C "$tmp" -c user.name=test -c user.email=test@example.invalid commit -q --allow-empty -m "$1"
  git -C "$tmp" rev-parse HEAD
}
A="$(commit A)"; B="$(commit B)"; C="$(commit C)"; D="$(commit D)"
git -C "$tmp" checkout -q -b side "$A"; X="$(commit X)"; git -C "$tmp" checkout -q main
export A B C D X

cat > "$tmp/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
sha_of() { eval "printf '%s' \"\$$1\""; }
case "$1 $2" in
  "run list")
    for r in ${RUNS:-}; do
      id="${r%%:*}"; rest="${r#*:}"; name="${rest%%:*}"
      printf '%s %s\n' "$id" "$(sha_of "$name")"
    done ;;
  "api "*)
    id="$(printf '%s' "$2" | sed -E 's#.*/runs/([0-9]+)/jobs.*#\1#')"
    for r in ${RUNS:-}; do
      [ "${r%%:*}" = "$id" ] || continue
      case "${r##*:}" in success) echo 1 ;; *) echo 0 ;; esac
      exit 0
    done
    echo 0 ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 2 ;;
esac
STUB
chmod +x "$tmp/gh"

fail=0
check() { # name, expected commit name ("" for nothing), commit to ask about, RUNS
  local name="$1" want="$2" ask="$3" runs="$4" got want_sha=""
  [ -n "$want" ] && want_sha="$(eval "printf '%s' \"\$$want\"")"
  got="$(cd "$tmp" && PATH="$tmp:$PATH" GITHUB_REPOSITORY=o/r RUNS="$runs" "$ROOT/live/last-drill.sh" "$(eval "printf '%s' \"\$$ask\"")")"
  if [ "$got" = "$want_sha" ]; then echo "ok   $name"; else echo "FAIL $name: wanted ${want:-nothing}, got ${got:-nothing}"; fail=1; fi
}

check "the newest drill that passed is the one compared with"            C D "3:C:success 2:B:success 1:A:success"
check "a green run that drilled nothing is passed over"                  B D "3:C:none 2:B:success 1:A:success"
check "several green runs that drilled nothing are all passed over"      A D "4:D:none 3:C:none 2:B:none 1:A:success"
check "a run whose Drill jobs were skipped is passed over"               B D "3:C:skipped 2:B:success"
check "a drill on a commit that is not an ancestor is passed over"       B D "3:X:success 2:B:success"
check "a refused push and a drill by hand on the same commit: the drill" C D "4:C:success 3:C:none 2:B:success"
check "no drill has ever passed: nothing"                                "" D "3:C:none 2:B:none"
check "no runs at all: nothing"                                          "" D ""

[ "$fail" = 0 ] && echo "last-drill: all cases passed"
exit "$fail"
