#!/usr/bin/env bash
# Persistence: create the owner and data, recreate the container (keeping the volume), verify everything survived
# and that sign-up is still closed.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

cleanup() { compose down -v --remove-orphans >/dev/null 2>&1 || true; rm -rf "$TEST_TMP"; }
trap cleanup EXIT

section "first boot"
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d >/dev/null 2>&1 || die "compose up failed"
wait_for_app || die "Happier never became reachable"
owner_signup
wait_for_app 60 || die "Happier did not come back after the lock restart"
MARKER="persist$(rand)"
product_write "$MARKER"
product_verify "$MARKER"

section "recreate (volume kept)"
compose down -t 5 >/dev/null 2>&1 || die "compose down failed"
compose up -d >/dev/null 2>&1 || die "compose up failed"
wait_for_app || die "Happier never came back"
assert_contains "the lock starts closed from the stored accounts" "sign-up closed (1 of 1 accounts exist)" "$(compose logs --no-color happier 2>&1)"
locked_checks
product_verify "$MARKER"

summary
