#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2034
# Shared helpers for happier-railway tests. Source this file; do not execute it.
# Secrets (device keys, tokens) live in mode-600 files under KEY_DIR and are never echoed.

: "${APP_URL:=http://127.0.0.1:${HAPPIER_TEST_PORT:-13105}}"
: "${TEST_TIMEOUT:=300}"

TEST_TMP="${TEST_TMP:-$(mktemp -d)}"
chmod 700 "$TEST_TMP"
export TEST_TMP
: "${KEY_DIR:=$TEST_TMP/keys}"
mkdir -p "$KEY_DIR" && chmod 700 "$KEY_DIR"
export KEY_DIR
_PASS=0; _FAIL=0

pass() { _PASS=$((_PASS+1)); printf '  PASS  %s\n' "$*"; }
fail() { _FAIL=$((_FAIL+1)); printf '  FAIL  %s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
section() { printf '\n== %s ==\n' "$*"; }
summary() { printf '\n%d passed, %d failed\n' "$_PASS" "$_FAIL"; [ "$_FAIL" -eq 0 ]; }

assert_eq() { if [ "$2" = "$3" ]; then pass "$1 ($3)"; else fail "$1: expected [$2] got [$3]"; fi; }
assert_contains() { if grep -q -- "$2" <<<"$3"; then pass "$1"; else fail "$1: missing [$2]"; fi; }

http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$@" || true; }

wait_for_code() {
  local url=$1 want=$2 timeout=${3:-$TEST_TIMEOUT} start code
  start=$(date +%s)
  while :; do
    code=$(http_code "$url")
    [ "$code" = "$want" ] && return 0
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then printf 'timed out waiting for %s -> %s (last %s)\n' "$url" "$want" "$code" >&2; return 1; fi
    sleep 2
  done
}

wait_for_app() { wait_for_code "$APP_URL/health" 200 "${1:-$TEST_TIMEOUT}"; }

compose() { docker compose -f "$REPO_ROOT/compose.yaml" "$@"; }

rand() { head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n'; }

# client CMD NAME [ARG] -> one JSON line from the stdlib Node client (tests/client/happier-client.mjs).
client() { node "$REPO_ROOT/tests/client/happier-client.mjs" "$1" "$APP_URL" "${@:2}" 2>"$TEST_TMP/client.err" || true; }
j() { jq -r "$1" <<<"$2" 2>/dev/null; }

# provision_enabled -> "true"/"false": whether /v1/features currently advertises device-key account creation.
provision_enabled() {
  curl -s --max-time 15 "$APP_URL/v1/features" \
    | jq -r '[.capabilities.auth.methods[] | select(.id=="key_challenge") | .actions[] | select(.id=="provision") | .enabled][0]' 2>/dev/null
}

# wait_for_signup_closed -> 0 once the server is back up advertising no account creation.
wait_for_signup_closed() {
  local start; start=$(date +%s)
  while [ $(( $(date +%s) - start )) -lt "${1:-120}" ]; do
    [ "$(provision_enabled)" = "false" ] && return 0
    sleep 2
  done
  return 1
}

# public_checks -> health, readiness, the embedded web UI and the auth capabilities endpoint.
public_checks() {
  assert_eq "GET /health" "200" "$(http_code "$APP_URL/health")"
  assert_eq "GET /ready" "200" "$(http_code "$APP_URL/ready")"
  local body; body=$(curl -s --max-time 30 "$APP_URL/")
  assert_contains "the embedded web app is served at /" "<html" "$body"
  assert_eq "GET /v1/features" "200" "$(http_code "$APP_URL/v1/features")"
}

# security_checks -> anonymous API access and forged signatures are refused.
security_checks() {
  assert_eq "anonymous GET /v1/sessions is refused" "401" "$(http_code "$APP_URL/v1/sessions")"
  assert_eq "a bogus bearer token is refused" "401" "$(http_code -H 'Authorization: Bearer not-a-token' "$APP_URL/v1/account/profile")"
  local key sig chal
  key=$(head -c 32 /dev/urandom | base64 -w0); sig=$(head -c 64 /dev/urandom | base64 -w0); chal=$(head -c 32 /dev/urandom | base64 -w0)
  assert_eq "a forged signature is refused" "401" "$(http_code -X POST -H 'Content-Type: application/json' \
    --data "{\"publicKey\":\"$key\",\"challenge\":\"$chal\",\"signature\":\"$sig\"}" "$APP_URL/v1/auth")"
}

# owner_signup -> the first device-key account is created while sign-up is open, then the lock closes sign-up.
owner_signup() {
  local r
  assert_eq "account creation is advertised before the first account" "true" "$(provision_enabled)"
  r=$(client auth owner)
  assert_eq "the owner account is created" "200" "$(j .status "$r")"
  OWNER_ID=$(j .accountId "$r")
  [ -n "$OWNER_ID" ] && [ "$OWNER_ID" != "null" ] && pass "the owner has an account id" || fail "no owner account id"
  printf '%s' "$OWNER_ID" >"$KEY_DIR/owner.id"
  if wait_for_signup_closed 120; then pass "sign-up closes after the first account"; else fail "sign-up is still open after the first account"; fi
}

# locked_checks -> new accounts are refused; the owner still signs in to the same account.
locked_checks() {
  local r
  assert_eq "account creation is no longer advertised" "false" "$(provision_enabled)"
  r=$(client auth "intruder$(rand)")
  assert_eq "a second account is refused" "403" "$(j .status "$r")"
  assert_eq "...with upstream's signup-disabled error" "signup-disabled" "$(j .error "$r")"
  r=$(client auth owner)
  assert_eq "the owner signs in again" "200" "$(j .status "$r")"
  assert_eq "...to the same account" "$(cat "$KEY_DIR/owner.id")" "$(j .accountId "$r")"
}

# product_write MARKER -> a session with a message and a KV entry are stored for the owner.
product_write() {
  local r
  r=$(client write owner "$1")
  assert_eq "create a session" "200" "$(j .sessionStatus "$r")"
  assert_eq "post an encrypted message to it" "200" "$(j .messageStatus "$r")"
  assert_eq "store an encrypted KV entry" "200" "$(j .kvStatus "$r")"
}

# product_verify MARKER -> they read back.
product_verify() {
  local r
  r=$(client verify owner "$1")
  assert_eq "list sessions" "200" "$(j .listStatus "$r")"
  assert_eq "session '$1' is listed" "true" "$(j .sessionFound "$r")"
  assert_eq "its message reads back" "true" "$(j .messageFound "$r")"
  assert_eq "the KV entry reads back" "true" "$(j .kvValueMatches "$r")"
}

# realtime_and_pairing -> the Socket.IO channel accepts the owner, and a terminal can be paired to the account.
realtime_and_pairing() {
  local r
  r=$(client socket owner)
  assert_eq "realtime channel /v1/updates connects over WebSocket" "true" "$(j .connected "$r")"
  r=$(client pair owner "machine$(rand)")
  assert_eq "a terminal requests pairing" "requested" "$(j .requestState "$r")"
  assert_eq "the owner approves it" "200" "$(j .responseStatus "$r")"
  assert_eq "the terminal receives its token" "authorized" "$(j .pairedState "$r")"
  assert_eq "the terminal token acts as the owner's account" "true" "$(j .machineTokenWorks "$r")"
}
