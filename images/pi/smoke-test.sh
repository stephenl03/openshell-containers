# Image-specific checks (appended to scripts/smoke-common.sh).
check_version "pi --version" "$(pi --version 2>&1)"
[ -f /sandbox/.pi/agent/settings.json ] || fail "pi settings.json missing"
pi list 2>&1 | grep -q pi-claude-auth || fail "pi-claude-auth not installed"
[ ! -e /sandbox/.pi/agent/auth.json ] || fail "pi --version created auth.json"
echo "ok: pi settings + pi-claude-auth present, PI_TELEMETRY=${PI_TELEMETRY:-unset}"
echo "SMOKE TEST PASSED"
