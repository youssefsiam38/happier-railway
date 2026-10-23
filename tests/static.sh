#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016
# Static validation: syntax, shellcheck, compose shape, image pin and the sign-up lock. No Docker build.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
cd "$REPO_ROOT"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
trap 'rm -rf "$TEST_TMP"' EXIT

ST=images/happier/railway-start.sh
DF=images/happier/Dockerfile
CL=tests/client/happier-client.mjs

section "syntax"
for f in tests/*.sh "$ST"; do
  if bash -n "$f" 2>/dev/null; then pass "parses: $f"; else fail "syntax error: $f"; fi
done
if node --check "$CL" 2>/dev/null; then pass "parses: $CL"; else fail "syntax error: $CL"; fi

section "shellcheck"
if command -v shellcheck >/dev/null; then
  if shellcheck -x -s bash tests/*.sh "$ST"; then pass "shellcheck"; else fail "shellcheck"; fi
else
  echo "  SKIP  shellcheck not installed"
fi

section "compose"
if docker compose -f compose.yaml config -q; then pass "compose config"; else fail "compose config"; fi
cfg=$(docker compose -f compose.yaml config --format json)
assert_eq "one service" "happier" "$(jq -r '[.services | keys[]] | join(" ")' <<<"$cfg")"
assert_eq "the port binds to loopback" "127.0.0.1" "$(jq -r '[.services.happier.ports[]? | .host_ip] | join(" ")' <<<"$cfg")"
assert_eq "the published port is the server port" "3005" "$(jq -r '[.services.happier.ports[]? | .target] | join(" ")' <<<"$cfg")"
assert_eq "PORT is 3005" "3005" "$(jq -r '.services.happier.environment.PORT' <<<"$cfg")"
assert_eq "one volume, at /data" "/data" "$(jq -r '[.services.happier.volumes[]? | .target] | join(" ")' <<<"$cfg")"
assert_contains "the compose master secret is a placeholder" 'local-test-only' "$(jq -r '.services.happier.environment.HANDY_MASTER_SECRET' <<<"$cfg")"

section "image"
assert_contains "upstream pinned by tag and digest" '^ARG HAPPIER_IMAGE=happierdev/relay-server:stable-[0-9a-f]*@sha256:[0-9a-f]\{64\}$' "$(grep '^ARG HAPPIER_IMAGE=' "$DF")"
assert_contains "the lock defaults to one account" 'SIGNUP_ACCOUNT_LIMIT=1' "$(cat "$DF")"
assert_contains "upstream central crash reporting is off by default" 'HAPPIER_SENTRY_USE_CENTRAL_DSN=0' "$(cat "$DF")"
assert_contains "the start script is the CMD" '^CMD \["/usr/local/bin/railway-start"\]' "$(cat "$DF")"

section "sign-up lock"
assert_contains "privileges drop to happier before the server starts" 'exec setpriv --reuid=happier --regid=happier' "$(cat "$ST")"
assert_contains "the server is upstream's own entrypoint" 'run-server /opt/happier/server/happier-server' "$(cat "$ST")"
assert_contains "accounts are counted in the SQLite database" 'SELECT count(\*) FROM "Account"' "$(cat "$ST")"
assert_contains "the closed server uses upstream's switch" 'AUTH_ANONYMOUS_SIGNUP_ENABLED=false exec' "$(cat "$ST")"
assert_contains "an explicit AUTH_ANONYMOUS_SIGNUP_ENABLED wins" 'set explicitly; sign-up lock not used' "$(cat "$ST")"
assert_contains "a non-SQLite database fails closed" 'exit 1' "$(grep -A2 'provider" != "sqlite"' "$ST")"

section "secrets hygiene"
mapfile -t tracked < <(git ls-files 2>/dev/null | grep . || find . -type f -not -path './.git/*')
if [ "${#tracked[@]}" -gt 0 ] && grep -lE '(sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{32,}|ghp_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----)' "${tracked[@]}" 2>/dev/null; then
  fail "a credential-shaped string is in the repository"
else
  pass "no credential-shaped strings in ${#tracked[@]} files"
fi

summary
