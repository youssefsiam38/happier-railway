#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016
# Local end-to-end smoke test against a fresh compose stack (the image must already be built).
# Covers: health, the embedded web app, auth gates, the sign-up lock (open -> first account -> closed), the owner's
# device-key login, sessions/messages/KV, the realtime WebSocket channel, terminal pairing, and the container layout.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

cleanup() { [ "${KEEP_STACK:-0}" = 1 ] || compose down -v --remove-orphans >/dev/null 2>&1 || true; rm -rf "$TEST_TMP"; }
trap cleanup EXIT

section "fail closed"
img=$(compose config --format json | jq -r .services.happier.image)
out=$(docker run --rm -e SIGNUP_ACCOUNT_LIMIT=abc "$img" 2>&1 || true)
assert_contains "a malformed SIGNUP_ACCOUNT_LIMIT refuses to start" "must be a whole number" "$out"
out=$(docker run --rm -e HAPPIER_DB_PROVIDER=postgres "$img" 2>&1 || true)
assert_contains "the lock refuses a non-SQLite database instead of leaving sign-up open" "needs the bundled SQLite database" "$out"

section "start-up"
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d >/dev/null 2>&1 || die "compose up failed"
wait_for_app || { compose logs --tail 80 >&2; die "Happier never became reachable"; }
pass "/health answers 200"
assert_contains "the lock starts open on an empty database" "sign-up open until 1 account(s) exist (0 so far)" "$(compose logs --no-color happier 2>&1)"
public_checks
security_checks

section "container"
in_c() { compose exec -T happier sh -c "$1" | tr -d '\r'; }
assert_eq "the server process runs as the non-root happier user" "happier" \
  "$(in_c 'for p in /proc/[0-9]*; do grep -q happier-server "$p/cmdline" 2>/dev/null && stat -c %U "$p" && break; done')"
assert_eq "the volume is owned by happier" "happier" "$(in_c 'stat -c %U /data')"
assert_eq "the SQLite database is on the volume" "yes" "$(in_c 'test -s /data/happier-server-light.sqlite && echo yes')"
assert_eq "crash reports to the upstream Sentry are off" "0" "$(in_c 'echo $HAPPIER_SENTRY_USE_CENTRAL_DSN')"

section "sign-up lock"
owner_signup
assert_contains "the lock restarted the server closed" "account limit reached (1 of 1)" "$(compose logs --no-color happier 2>&1)"
wait_for_app 60 || die "Happier did not come back after the lock restart"
locked_checks

section "product"
MARKER="smoke$(rand)"
product_write "$MARKER"
product_verify "$MARKER"
realtime_and_pairing

section "restart"
compose restart -t 5 happier >/dev/null 2>&1 || die "restart failed"
sleep 2
wait_for_app || die "Happier never came back"
assert_contains "after a restart the lock starts closed" "sign-up closed (1 of 1 accounts exist)" "$(compose logs --no-color --tail 40 happier 2>&1)"
locked_checks
product_verify "$MARKER"

summary
