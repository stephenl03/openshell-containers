# Common checks, run inside the image as 10001:10001 (piped in by smoke-test.sh).
# $1 = expected tool version from images/<name>/VERSION.
set -euo pipefail
expected_version="$1"

fail() { echo "FAIL: $*" >&2; exit 1; }

[ "$(id -u):$(id -g)" = "10001:10001" ] || fail "running as $(id -u):$(id -g), want 10001:10001"
[ "$HOME" = /sandbox ] || fail "HOME=$HOME, want /sandbox"
[ -w /sandbox ] || fail "/sandbox not writable by 10001"
echo "ok: uid/gid $(id -u):$(id -g), HOME=$HOME, /sandbox writable"

# No credentials baked into the image.
creds=$(find / -xdev \( -name auth.json -o -name .credentials.json \) -print 2>/dev/null || true)
[ -z "$creds" ] || fail "credential files present in image: $creds"
echo "ok: no auth.json / .credentials.json in image"

# Shared tooling.
for t in git gh rg fd jq curl; do command -v "$t" >/dev/null || fail "missing $t"; done
grep -q 'gh auth git-credential' /etc/gitconfig || fail "/etc/gitconfig credential helper missing"
[ -f /etc/openshell/policy.yaml ] || fail "/etc/openshell/policy.yaml missing"
echo "ok: $(git --version), $(gh --version | head -1), $(rg --version | head -1), fd $(fd --version | awk '{print $2}'), $(jq --version)"

check_version() { # <label> <output>
  echo "$1: $2"
  case "$2" in *"$expected_version"*) ;; *) fail "$1 does not report $expected_version";; esac
}
