#!/bin/bash
# Railway start script for the Happier relay server (wrapper around the official image, run unmodified).
#
#  1. As root: make the Railway volume (mounted root-owned) writable by the image's `happier` user, then re-exec
#     this script as `happier`.
#  2. Sign-up lock: while the SQLite database holds fewer than SIGNUP_ACCOUNT_LIMIT accounts, run the server with
#     anonymous sign-up open and watch the account count. Once the limit is reached, restart the server with
#     AUTH_ANONYMOUS_SIGNUP_ENABLED=false (upstream's own switch: existing accounts keep signing in, new
#     accounts get 403 signup-disabled). Every later boot starts closed.
#     SIGNUP_ACCOUNT_LIMIT=0 turns the lock off (upstream behaviour). An explicit AUTH_ANONYMOUS_SIGNUP_ENABLED
#     always wins over the lock.
set -euo pipefail

log() { printf '[railway-start] %s\n' "$*"; }

DATA_DIR=${HAPPIER_SERVER_LIGHT_DATA_DIR:-/data}
SERVER=(run-server /opt/happier/server/happier-server)

if [ "$(id -u)" = "0" ]; then
  mkdir -p "$DATA_DIR"
  if [ "$(stat -c %U "$DATA_DIR")" != "happier" ] || [ -n "$(find "$DATA_DIR" ! -user happier -print -quit)" ]; then
    log "fixing ownership of $DATA_DIR"
    chown -R happier:happier "$DATA_DIR"
  fi
  exec setpriv --reuid=happier --regid=happier --init-groups env HOME=/home/happier "$0" "$@"
fi

LIMIT=${SIGNUP_ACCOUNT_LIMIT:-1}
POLL=${SIGNUP_LOCK_POLL_SECONDS:-2}
[[ "$LIMIT" =~ ^[0-9]+$ ]] || { log "SIGNUP_ACCOUNT_LIMIT must be a whole number (got '$LIMIT')"; exit 1; }
[[ "$POLL" =~ ^[1-9][0-9]*$ ]] || { log "SIGNUP_LOCK_POLL_SECONDS must be a positive whole number"; exit 1; }

explicit=$(printf '%s' "${AUTH_ANONYMOUS_SIGNUP_ENABLED:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
provider=$(printf '%s' "${HAPPIER_DB_PROVIDER:-sqlite}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

if [ -n "$explicit" ]; then
  log "AUTH_ANONYMOUS_SIGNUP_ENABLED is set explicitly; sign-up lock not used"
  exec "${SERVER[@]}"
fi
if [ "$LIMIT" = "0" ]; then
  log "SIGNUP_ACCOUNT_LIMIT=0: anonymous sign-up stays open (upstream default)"
  exec "${SERVER[@]}"
fi
if [ "$provider" != "sqlite" ]; then
  log "the sign-up lock needs the bundled SQLite database; set SIGNUP_ACCOUNT_LIMIT=0 or AUTH_ANONYMOUS_SIGNUP_ENABLED with $provider"
  exit 1
fi

DB="$DATA_DIR/happier-server-light.sqlite"
account_count() {
  local n
  [ -f "$DB" ] || { echo 0; return; }
  n=$(sqlite3 -cmd '.timeout 5000' "$DB" 'SELECT count(*) FROM "Account";' 2>/dev/null) || n=0
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  echo "$n"
}

child=0
# The light server runs its shutdown handlers (database closed) on SIGTERM but its process does not always exit
# afterwards, so give it a grace period and then SIGKILL it.
stop_child() {
  kill -TERM "$child" 2>/dev/null || true
  for _ in $(seq 1 "${SHUTDOWN_GRACE_SECONDS:-5}"); do
    kill -0 "$child" 2>/dev/null || break
    sleep 1
  done
  kill -KILL "$child" 2>/dev/null || true
  wait "$child" 2>/dev/null || true
}
on_term() {
  if [ "$child" -gt 0 ]; then stop_child; fi
  exit 0
}
trap on_term TERM INT

n=$(account_count)
if [ "$n" -ge "$LIMIT" ]; then
  log "sign-up closed ($n of $LIMIT accounts exist)"
  trap - TERM INT
  AUTH_ANONYMOUS_SIGNUP_ENABLED=false exec "${SERVER[@]}"
fi

log "sign-up open until $LIMIT account(s) exist ($n so far)"
AUTH_ANONYMOUS_SIGNUP_ENABLED=true "${SERVER[@]}" &
child=$!
while kill -0 "$child" 2>/dev/null; do
  sleep "$POLL" & wait $! || true
  n=$(account_count)
  if [ "$n" -ge "$LIMIT" ]; then
    log "account limit reached ($n of $LIMIT); restarting the server with sign-up closed"
    stop_child
    trap - TERM INT
    AUTH_ANONYMOUS_SIGNUP_ENABLED=false exec "${SERVER[@]}"
  fi
done
wait "$child"
