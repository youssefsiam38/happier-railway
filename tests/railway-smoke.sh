#!/usr/bin/env bash
# shellcheck disable=SC2015
# Live end-to-end test against a deployed template over HTTPS.
#   tests/railway-smoke.sh https://<domain>            fresh deploy: claim the owner account, then every product flow
#   tests/railway-smoke.sh https://<domain> --verify   after a redeploy: same owner, data intact, sign-up still closed
# KEY_DIR must be a private directory kept between the two runs (it holds the owner's device key, mode 600).
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
APP_URL=${1:?usage: railway-smoke.sh https://<domain> [--verify]}; APP_URL=${APP_URL%/}; export APP_URL
MODE=${2:-full}
[ -n "${KEY_DIR:-}" ] || { echo "set KEY_DIR to a private directory kept between runs" >&2; exit 2; }
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
trap 'rm -rf "$TEST_TMP"' EXIT

case "$APP_URL" in https://*) ;; *) die "the live test runs over HTTPS" ;; esac

section "public"
wait_for_app 300 || die "the deployment is not reachable"
public_checks
security_checks
assert_eq "plain HTTP is redirected to HTTPS" "301" "$(http_code "http://${APP_URL#https://}/health")"

if [ "$MODE" = "--verify" ]; then
  section "after redeploy"
  locked_checks
  product_verify "$(cat "$KEY_DIR/marker")"
  realtime_and_pairing
else
  section "sign-up lock"
  owner_signup
  wait_for_app 120 || die "the deployment did not come back after the lock restart"
  locked_checks

  section "product"
  MARKER="live$(rand)"
  printf '%s' "$MARKER" >"$KEY_DIR/marker"
  product_write "$MARKER"
  product_verify "$MARKER"
  realtime_and_pairing
fi

summary
