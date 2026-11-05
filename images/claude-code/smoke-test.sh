# Image-specific checks (appended to scripts/smoke-common.sh).
[ "$(command -v claude)" = /usr/local/bin/claude ] || fail "claude not at /usr/local/bin/claude"
check_version "claude --version" "$(claude --version 2>&1)"
for v in DISABLE_AUTOUPDATER DISABLE_UPDATES CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC DISABLE_TELEMETRY DISABLE_ERROR_REPORTING; do
  [ "${!v:-}" = 1 ] || fail "$v not set to 1"
done
[ -z "${ANTHROPIC_API_KEY:-}${CLAUDE_CODE_OAUTH_TOKEN:-}" ] || fail "auth env baked into image"
[ ! -e /sandbox/.claude/.credentials.json ] || fail "claude --version created .credentials.json"
echo "ok: updater/telemetry env set, no auth env"
echo "SMOKE TEST PASSED"
