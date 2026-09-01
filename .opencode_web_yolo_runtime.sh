#!/usr/bin/env bash
set -euo pipefail

RETENTION_HELPER="${OPENCODE_WEB_RETENTION_HELPER:-/usr/local/bin/opencode_web_yolo_retention.js}"
RETENTION_DAYS="${OPENCODE_WEB_RETENTION_DAYS-0}"
RETENTION_POLL_SECONDS="${OPENCODE_WEB_RETENTION_POLL_SECONDS-3600}"
RETENTION_URL="${OPENCODE_WEB_RETENTION_URL:-http://127.0.0.1:${OPENCODE_WEB_PORT:-4096}}"
app_pid=""
scheduler_pid=""
stopping=0

case "$RETENTION_DAYS" in
  ''|*[!0-9]*)
    printf '%s\n' "[opencode_web_yolo retention] ERROR: OPENCODE_WEB_RETENTION_DAYS must be a non-negative integer." >&2
    exit 1
    ;;
esac
while [ "${RETENTION_DAYS#0}" != "$RETENTION_DAYS" ]; do RETENTION_DAYS="${RETENTION_DAYS#0}"; done
RETENTION_DAYS="${RETENTION_DAYS:-0}"

if [ "$RETENTION_DAYS" = "0" ]; then
  exec "$@"
fi

if ! [[ "$RETENTION_POLL_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  printf '%s\n' "[opencode_web_yolo retention] ERROR: OPENCODE_WEB_RETENTION_POLL_SECONDS must be a positive integer (minimum 1 second)." >&2
  exit 1
fi
if [ "${#RETENTION_POLL_SECONDS}" -gt 10 ] || { [ "${#RETENTION_POLL_SECONDS}" -eq 10 ] && (( RETENTION_POLL_SECONDS > 2147483647 )); }; then
  printf '%s\n' "[opencode_web_yolo retention] ERROR: OPENCODE_WEB_RETENTION_POLL_SECONDS is outside the supported positive integer range." >&2
  exit 1
fi

forward_signal() {
  local signal="$1"
  stopping=1
  if [ -n "$app_pid" ]; then kill -"$signal" "$app_pid" >/dev/null 2>&1 || true; fi
  if [ -n "$scheduler_pid" ]; then kill -"$signal" "$scheduler_pid" >/dev/null 2>&1 || true; fi
}

trap 'forward_signal TERM' TERM
trap 'forward_signal INT' INT

health_ok() {
  local health_body auth
  if ! auth="$(node -e 'process.stdout.write(Buffer.from(`${process.env.OPENCODE_SERVER_USERNAME || "opencode"}:${process.env.OPENCODE_SERVER_PASSWORD || ""}`).toString("base64"))')"; then
    return 1
  fi
  if ! health_body="$(printf 'header = "Authorization: Basic %s"\n' "$auth" | curl --config - -fsS --max-time 2 "${RETENTION_URL}/global/health" 2>/dev/null)"; then
    return 1
  fi
  node -e 'const value = JSON.parse(require("fs").readFileSync(0, "utf8")); process.exit(value && value.healthy === true ? 0 : 1)' <<<"$health_body" >/dev/null 2>&1
}

wait_for_health() {
  while [ "$stopping" -eq 0 ] && app_running; do
    if health_ok; then return 0; fi
    sleep 1 || true
  done
  return 1
}

app_running() {
  kill -0 "$app_pid" >/dev/null 2>&1 || return 1
  if [ -r "/proc/${app_pid}/stat" ]; then
    local process_state
    read -r _ _ process_state _ <"/proc/${app_pid}/stat" || return 1
    [ "$process_state" != Z ]
  fi
}

run_scheduler() {
  while [ "$stopping" -eq 0 ]; do
    if ! OPENCODE_WEB_RETENTION_DAYS="$RETENTION_DAYS" \
      OPENCODE_WEB_RETENTION_URL="$RETENTION_URL" \
      node "$RETENTION_HELPER" --run-once; then
      printf '%s\n' "[opencode_web_yolo retention] WARNING: cleanup failed; success marker was not advanced. It will retry later." >&2
    fi
    sleep "$RETENTION_POLL_SECONDS" || true
  done
}

"$@" &
app_pid=$!

if wait_for_health; then
  run_scheduler &
  scheduler_pid=$!
fi

set +e
wait "$app_pid"
app_status=$?
if [ "$stopping" -eq 1 ] && kill -0 "$app_pid" >/dev/null 2>&1; then
  wait "$app_pid"
  app_status=$?
fi
set -e
stopping=1
if [ -n "$scheduler_pid" ]; then
  kill -TERM "$scheduler_pid" >/dev/null 2>&1 || true
  wait "$scheduler_pid" >/dev/null 2>&1 || true
fi
exit "$app_status"
