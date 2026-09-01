#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

TMP_DIR="$(mktemp -d)"
server_pid=""
cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

FAKE_BIN="${TMP_DIR}/bin"
WRAPPER_VERSION="$(tr -d '[:space:]' <"${ROOT_DIR}/VERSION")"
setup_fake_docker "$FAKE_BIN" "$WRAPPER_VERSION"
export PATH="${FAKE_BIN}:${PATH}"
export HOME="${TMP_DIR}/home"
mkdir -p "$HOME"
export OPENCODE_SERVER_PASSWORD=secret
export OPENCODE_WEB_SKIP_UPDATE_CHECK=1
export OPENCODE_WEB_SKIP_VERSION_CHECK=1
export OPENCODE_WEB_DRY_RUN=1

output="$("${ROOT_DIR}/.opencode_web_yolo.sh" --retention-days 5 2>&1)"
assert_contains "$output" "retention_days=5"
assert_contains "$output" "OPENCODE_WEB_RETENTION_DAYS=5"
assert_contains "$output" "-e OPENCODE_SERVER_PASSWORD"
assert_not_contains "$output" "secret"
assert_contains "$output" "retention_poll_seconds=3600"
assert_contains "$output" "retention_fetch_timeout_ms=10000"
assert_contains "$output" "retention_verify_timeout_ms=10000"
output_equals="$("${ROOT_DIR}/.opencode_web_yolo.sh" --retention-days=6 2>&1)"
assert_contains "$output_equals" "retention_days=6"

printf '%s\n' 'export OPENCODE_WEB_RETENTION_DAYS=7' >"${HOME}/.opencode_web_yolo-config.tmp"
mkdir -p "${HOME}/.opencode_web_yolo"
mv "${HOME}/.opencode_web_yolo-config.tmp" "${HOME}/.opencode_web_yolo/config"
unset OPENCODE_WEB_RETENTION_DAYS
output_config="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_contains "$output_config" "retention_days=7"
output_override="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run --retention-days 8 2>&1)"
assert_contains "$output_override" "retention_days=8"

set +e
rm -f "${HOME}/.opencode_web_yolo/config"
invalid_output="$(OPENCODE_WEB_RETENTION_DAYS=invalid "${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
invalid_status=$?
set -e
if [ "$invalid_status" -eq 0 ]; then fail "invalid retention value should fail"; fi
assert_contains "$invalid_output" "must be a non-negative integer"
set +e
missing_output="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run --retention-days 2>&1)"
missing_status=$?
set -e
if [ "$missing_status" -eq 0 ]; then fail "missing retention value should fail"; fi
assert_contains "$missing_output" "requires a non-negative integer value"
set +e
poll_output="$(OPENCODE_WEB_RETENTION_DAYS=1 OPENCODE_WEB_RETENTION_POLL_SECONDS=0 "${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
poll_wrapper_status=$?
set -e
if [ "$poll_wrapper_status" -eq 0 ]; then fail "zero scheduler poll interval should fail"; fi
assert_contains "$poll_output" "OPENCODE_WEB_RETENTION_POLL_SECONDS must be a positive integer"

set +e
range_output="$(OPENCODE_WEB_RETENTION_DAYS=1 OPENCODE_WEB_RETENTION_POLL_SECONDS=2147483648 "${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
range_wrapper_status=$?
set -e
if [ "$range_wrapper_status" -eq 0 ]; then fail "out-of-range scheduler poll interval should fail"; fi
assert_contains "$range_output" "outside the supported positive integer range"

if ! command -v node >/dev/null 2>&1; then
  printf '%s\n' "PASS: session retention wrapper coverage (node unavailable; API mock skipped)"
  exit 0
fi

MODE_FILE="${TMP_DIR}/mode"
DELETE_LOG="${TMP_DIR}/deletions"
REQUEST_LOG="${TMP_DIR}/requests"
PORT_FILE="${TMP_DIR}/port"
NOW=2000000000000
printf '%s\n' normal >"$MODE_FILE"
: >"$DELETE_LOG"
: >"$REQUEST_LOG"

node - "$MODE_FILE" "$DELETE_LOG" "$REQUEST_LOG" >"$PORT_FILE" <<'NODE' &
const fs = require("node:fs")
const http = require("node:http")
const modeFile = process.argv[2]
const deleteLog = process.argv[3]
const requestLog = process.argv[4]
const now = 2000000000000
const sessions = [
  { id: "recent", directory: "/four", time: { updated: now - 2 * 86400000 } },
  { id: "old-a", directory: "/one", time: { updated: now - 8 * 86400000 } },
  { id: "child-cross", directory: "/two", parentID: "old-a", time: { updated: now - 9 * 86400000 } },
  { id: "old-b", directory: "/one", time: { updated: now - 10 * 86400000 } },
  { id: "active-old", directory: "/three", time: { updated: now - 10 * 86400000 } },
]
function listedSessions(mode) {
  if (mode === "missing-parent") {
    return sessions.map((session) => session.id === "child-cross" ? { ...session, parentID: "missing" } : session)
  }
  if (mode === "cycle") {
    return sessions.map((session) => {
      if (session.id === "old-a") return { ...session, parentID: "child-cross" }
      if (session.id === "child-cross") return { ...session, parentID: "old-a" }
      return session
    })
  }
  if (mode === "duplicate-id") return [...sessions, { ...sessions[0] }]
  return sessions
}
const deleted = new Set()
const statusCalls = new Map()
let lastMode
const server = http.createServer((request, response) => {
  const url = new URL(request.url, "http://localhost")
  fs.appendFileSync(requestLog, `${request.method} ${url.pathname}${url.search}\n`)
  response.setHeader("content-type", "application/json")
  if (request.headers.authorization !== `Basic ${Buffer.from("opencode:secret").toString("base64")}`) {
    response.statusCode = 401
    response.end("{}")
    return
  }
  const mode = fs.readFileSync(modeFile, "utf8").trim()
  if (mode !== lastMode) {
    statusCalls.clear()
    deleted.clear()
    lastMode = mode
  }
  if (url.pathname === "/global/health" && request.method === "GET") {
    response.end(JSON.stringify({ healthy: true, version: mode === "unsupported" ? "2.0.0" : "1.18.25" }))
    return
  }
  if (url.pathname === "/experimental/session" && request.method === "GET") {
    if (mode === "stall") {
      setTimeout(() => response.end(JSON.stringify(sessions)), 500)
      return
    }
    if (mode === "malformed") {
      response.end(JSON.stringify({ sessions }))
      return
    }
    const listed = listedSessions(mode)
    const first = listed.slice(0, 3)
    const second = listed.slice(3)
    if (url.searchParams.has("cursor")) {
      response.end(JSON.stringify(second))
    } else {
      response.setHeader("x-next-cursor", String(first[first.length - 1].time.updated))
      response.end(JSON.stringify(first))
    }
    return
  }
  if (url.pathname === "/session/status" && request.method === "GET") {
    const directory = url.searchParams.get("directory")
    const calls = (statusCalls.get(directory) || 0) + 1
    statusCalls.set(directory, calls)
    if (mode === "cross-directory-child" && directory === "/two") {
      response.end(JSON.stringify({ "child-cross": { type: "busy" } }))
    } else if (mode === "unknown-retry") {
      response.end(JSON.stringify({ "unknown-active": { type: "retry" } }))
    } else if (mode === "status-change" && directory === "/two" && calls === 2) {
      response.end(JSON.stringify({ "child-cross": { type: "retry" } }))
    } else if (["normal", "stale-refresh", "status-change", "cross-directory-child"].includes(mode) && directory === "/three") {
      response.end(JSON.stringify({ "active-old": { type: "busy" } }))
    } else {
      response.end("{}")
    }
    return
  }
  if (url.pathname.startsWith("/session/") && request.method === "GET") {
    const id = decodeURIComponent(url.pathname.slice("/session/".length))
    if (deleted.has(id)) {
      response.statusCode = 404
      response.end("{}")
      return
    }
    const session = sessions.find((item) => item.id === id)
    if (!session) {
      response.statusCode = 404
      response.end("{}")
      return
    }
    const refreshed = mode === "stale-refresh" && id === "old-a"
      ? { ...session, time: { updated: now - 1 * 86400000 } }
      : session
    response.end(JSON.stringify(refreshed))
    return
  }
  if (url.pathname.startsWith("/session/") && request.method === "DELETE") {
    if (mode === "failure") {
      response.statusCode = 500
      response.end(JSON.stringify({ error: "failure" }))
      return
    }
    const id = decodeURIComponent(url.pathname.slice("/session/".length))
    fs.appendFileSync(deleteLog, `${id}\n`)
    if (mode !== "stuck") deleted.add(id)
    response.end("true")
    return
  }
  response.statusCode = 404
  response.end("{}")
})
server.listen(0, "127.0.0.1", () => process.stdout.write(`${server.address().port}\n`))
NODE
server_pid=$!
while [ ! -s "$PORT_FILE" ]; do sleep 0.05; done
port="$(tr -d '[:space:]' <"$PORT_FILE")"
marker="${TMP_DIR}/state/last-success"

OPENCODE_WEB_RETENTION_DAYS=7 \
OPENCODE_WEB_RETENTION_NOW_MS="$NOW" \
OPENCODE_WEB_RETENTION_URL="http://127.0.0.1:${port}" \
OPENCODE_WEB_RETENTION_MARKER="$marker" \
OPENCODE_SERVER_USERNAME=opencode \
node "${ROOT_DIR}/.opencode_web_yolo_retention.js" --run-once
assert_contains "$(tr '\n' ' ' <"$DELETE_LOG")" "old-a"
assert_contains "$(tr '\n' ' ' <"$DELETE_LOG")" "old-b"
assert_not_contains "$(tr '\n' ' ' <"$DELETE_LOG")" "active-old"
[ -s "$marker" ] || fail "successful cleanup should write marker"
requests="$(cat "$REQUEST_LOG")"
assert_contains "$requests" "GET /global/health"
assert_contains "$requests" "GET /experimental/session?roots=false&archived=true&limit=100"
assert_contains "$requests" "GET /experimental/session?roots=false&archived=true&limit=100&cursor="
assert_contains "$requests" "cursor=1999222400000"
assert_contains "$requests" "GET /session/status?directory=%2Fone"
assert_contains "$requests" "GET /session/status?directory=%2Ftwo"
assert_contains "$requests" "GET /session/old-a?directory=%2Fone"
assert_contains "$requests" "DELETE /session/old-a?directory=%2Fone"

before="$(wc -l <"$DELETE_LOG")"
OPENCODE_WEB_RETENTION_DAYS=7 OPENCODE_WEB_RETENTION_NOW_MS="$NOW" OPENCODE_WEB_RETENTION_URL="http://127.0.0.1:${port}" OPENCODE_WEB_RETENTION_MARKER="$marker" node "${ROOT_DIR}/.opencode_web_yolo_retention.js" --run-once >/dev/null
assert_equals "$before" "$(wc -l <"$DELETE_LOG")"

rm -f "$marker"
OPENCODE_WEB_RETENTION_DAYS=7 OPENCODE_WEB_RETENTION_NOW_MS="$NOW" OPENCODE_WEB_RETENTION_URL="http://127.0.0.1:${port}" OPENCODE_WEB_RETENTION_MARKER="$marker" OPENCODE_WEB_RETENTION_DRY_RUN=1 node "${ROOT_DIR}/.opencode_web_yolo_retention.js" --run-once >/dev/null
[ ! -e "$marker" ] || fail "dry-run should not write marker"
assert_equals "$before" "$(wc -l <"$DELETE_LOG")"

printf '%s\n' failure >"$MODE_FILE"
set +e
OPENCODE_WEB_RETENTION_DAYS=7 OPENCODE_WEB_RETENTION_NOW_MS="$NOW" OPENCODE_WEB_RETENTION_URL="http://127.0.0.1:${port}" OPENCODE_WEB_RETENTION_MARKER="$marker" node "${ROOT_DIR}/.opencode_web_yolo_retention.js" --run-once >/dev/null 2>&1
failure_status=$?
set -e
if [ "$failure_status" -eq 0 ]; then fail "API failure should fail cleanup"; fi
[ ! -e "$marker" ] || fail "failed cleanup should not write marker"

printf '%s\n' cross-directory-child >"$MODE_FILE"
: >"$DELETE_LOG"
rm -f "$marker"
OPENCODE_WEB_RETENTION_DAYS=7 OPENCODE_WEB_RETENTION_NOW_MS="$NOW" OPENCODE_WEB_RETENTION_URL="http://127.0.0.1:${port}" OPENCODE_WEB_RETENTION_MARKER="$marker" node "${ROOT_DIR}/.opencode_web_yolo_retention.js" --run-once >/dev/null
cross_deletions="$(tr '\n' ' ' <"$DELETE_LOG")"
assert_not_contains "$cross_deletions" "old-a"
assert_contains "$cross_deletions" "old-b"
assert_not_contains "$cross_deletions" "active-old"

printf '%s\n' unknown-retry >"$MODE_FILE"
rm -f "$marker"
before="$(wc -l <"$DELETE_LOG")"
set +e
OPENCODE_WEB_RETENTION_DAYS=7 OPENCODE_WEB_RETENTION_NOW_MS="$NOW" OPENCODE_WEB_RETENTION_URL="http://127.0.0.1:${port}" OPENCODE_WEB_RETENTION_MARKER="$marker" node "${ROOT_DIR}/.opencode_web_yolo_retention.js" --run-once >/dev/null 2>&1
unknown_status=$?
set -e
if [ "$unknown_status" -eq 0 ]; then fail "unmapped active status should fail closed"; fi
assert_equals "$before" "$(wc -l <"$DELETE_LOG")"

for hierarchy_mode in missing-parent cycle duplicate-id; do
  printf '%s\n' "$hierarchy_mode" >"$MODE_FILE"
  rm -f "$marker"
  before="$(wc -l <"$DELETE_LOG")"
  set +e
  OPENCODE_WEB_RETENTION_DAYS=7 OPENCODE_WEB_RETENTION_NOW_MS="$NOW" OPENCODE_WEB_RETENTION_URL="http://127.0.0.1:${port}" OPENCODE_WEB_RETENTION_MARKER="$marker" node "${ROOT_DIR}/.opencode_web_yolo_retention.js" --run-once >/dev/null 2>&1
  hierarchy_status=$?
  set -e
  if [ "$hierarchy_status" -eq 0 ]; then fail "${hierarchy_mode} hierarchy should fail closed"; fi
  assert_equals "$before" "$(wc -l <"$DELETE_LOG")"
  [ ! -e "$marker" ] || fail "${hierarchy_mode} hierarchy should not write marker"
done

printf '%s\n' stale-refresh >"$MODE_FILE"
: >"$DELETE_LOG"
rm -f "$marker"
OPENCODE_WEB_RETENTION_DAYS=7 OPENCODE_WEB_RETENTION_NOW_MS="$NOW" OPENCODE_WEB_RETENTION_URL="http://127.0.0.1:${port}" OPENCODE_WEB_RETENTION_MARKER="$marker" node "${ROOT_DIR}/.opencode_web_yolo_retention.js" --run-once >/dev/null
stale_deletions="$(tr '\n' ' ' <"$DELETE_LOG")"
assert_not_contains "$stale_deletions" "old-a"
assert_contains "$stale_deletions" "old-b"
assert_not_contains "$stale_deletions" "active-old"

printf '%s\n' status-change >"$MODE_FILE"
: >"$DELETE_LOG"
rm -f "$marker"
before="$(wc -l <"$DELETE_LOG")"
OPENCODE_WEB_RETENTION_DAYS=7 OPENCODE_WEB_RETENTION_NOW_MS="$NOW" OPENCODE_WEB_RETENTION_URL="http://127.0.0.1:${port}" OPENCODE_WEB_RETENTION_MARKER="$marker" node "${ROOT_DIR}/.opencode_web_yolo_retention.js" --run-once >/dev/null
assert_equals "$((before + 1))" "$(wc -l <"$DELETE_LOG")"
status_deletions="$(tr '\n' ' ' <"$DELETE_LOG")"
assert_not_contains "$status_deletions" "old-a"
assert_contains "$status_deletions" "old-b"
assert_not_contains "$status_deletions" "active-old"

printf '%s\n' unsupported >"$MODE_FILE"
rm -f "$marker"
before="$(wc -l <"$DELETE_LOG")"
set +e
OPENCODE_WEB_RETENTION_DAYS=7 OPENCODE_WEB_RETENTION_NOW_MS="$NOW" OPENCODE_WEB_RETENTION_URL="http://127.0.0.1:${port}" OPENCODE_WEB_RETENTION_MARKER="$marker" node "${ROOT_DIR}/.opencode_web_yolo_retention.js" --run-once >/dev/null 2>&1
unsupported_status=$?
set -e
if [ "$unsupported_status" -eq 0 ]; then fail "unsupported OpenCode version should fail closed"; fi
assert_equals "$before" "$(wc -l <"$DELETE_LOG")"
[ ! -e "$marker" ] || fail "unsupported version should not write marker"

printf '%s\n' malformed >"$MODE_FILE"
set +e
OPENCODE_WEB_RETENTION_DAYS=7 OPENCODE_WEB_RETENTION_NOW_MS="$NOW" OPENCODE_WEB_RETENTION_URL="http://127.0.0.1:${port}" OPENCODE_WEB_RETENTION_MARKER="$marker" node "${ROOT_DIR}/.opencode_web_yolo_retention.js" --run-once >/dev/null 2>&1
malformed_status=$?
set -e
if [ "$malformed_status" -eq 0 ]; then fail "malformed list response should fail closed"; fi
[ ! -e "$marker" ] || fail "malformed response should not write marker"

future_marker="${TMP_DIR}/future-marker"
printf '%s\n' "$((NOW + 86400000))" >"$future_marker"
set +e
OPENCODE_WEB_RETENTION_DAYS=7 OPENCODE_WEB_RETENTION_NOW_MS="$NOW" OPENCODE_WEB_RETENTION_URL="http://127.0.0.1:${port}" OPENCODE_WEB_RETENTION_MARKER="$future_marker" node "${ROOT_DIR}/.opencode_web_yolo_retention.js" --run-once >/dev/null 2>&1
future_status=$?
set -e
if [ "$future_status" -eq 0 ]; then fail "future marker should be treated as due"; fi

printf '%s\n' stuck >"$MODE_FILE"
rm -f "$marker"
before="$(wc -l <"$DELETE_LOG")"
set +e
OPENCODE_WEB_RETENTION_DAYS=7 OPENCODE_WEB_RETENTION_NOW_MS="$NOW" OPENCODE_WEB_RETENTION_VERIFY_TIMEOUT_MS=300 OPENCODE_WEB_RETENTION_URL="http://127.0.0.1:${port}" OPENCODE_WEB_RETENTION_MARKER="$marker" node "${ROOT_DIR}/.opencode_web_yolo_retention.js" --run-once >/dev/null 2>&1
stuck_status=$?
set -e
if [ "$stuck_status" -eq 0 ]; then fail "remaining deleted session should fail verification"; fi
assert_equals "$((before + 1))" "$(wc -l <"$DELETE_LOG")"
[ ! -e "$marker" ] || fail "failed deletion verification should not write marker"

printf '%s\n' stall >"$MODE_FILE"
set +e
OPENCODE_WEB_RETENTION_DAYS=7 OPENCODE_WEB_RETENTION_NOW_MS="$NOW" OPENCODE_WEB_RETENTION_FETCH_TIMEOUT_MS=50 OPENCODE_WEB_RETENTION_URL="http://127.0.0.1:${port}" OPENCODE_WEB_RETENTION_MARKER="$marker" node "${ROOT_DIR}/.opencode_web_yolo_retention.js" --run-once >/dev/null 2>&1
stall_status=$?
set -e
if [ "$stall_status" -eq 0 ]; then fail "stalled API request should fail"; fi
[ ! -e "$marker" ] || fail "stalled request should not write marker"

kill "$server_pid" >/dev/null 2>&1 || true
wait "$server_pid" >/dev/null 2>&1 || true

runtime="$(cat "${ROOT_DIR}/.opencode_web_yolo_runtime.sh")"
assert_contains "$runtime" "trap 'forward_signal TERM' TERM"
assert_contains "$runtime" "trap 'forward_signal INT' INT"
assert_contains "$runtime" "wait \"\$app_pid\""
assert_contains "$runtime" "exit \"\$app_status\""
dockerfile="$(cat "${ROOT_DIR}/.opencode_web_yolo.Dockerfile")"
assert_contains "$dockerfile" ".opencode_web_yolo_retention.js"
assert_contains "$dockerfile" "tini"
assert_contains "$dockerfile" 'ENTRYPOINT ["/usr/bin/tini", "-s", "-g"'
assert_contains "$(cat "${ROOT_DIR}/install.sh")" ".opencode_web_yolo_runtime.sh"
assert_contains "$(cat "${ROOT_DIR}/install.sh")" ".opencode_web_yolo_retention.js"

cat >"${FAKE_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
[ -z "${CURL_ARGS_LOG:-}" ] || printf '%s\n' "$*" >"$CURL_ARGS_LOG"
printf '%s\n' '{"healthy":true,"version":"1.18.25"}'
EOF
chmod +x "${FAKE_BIN}/curl"
runtime_helper="${TMP_DIR}/runtime-helper"
cat >"$runtime_helper" <<'EOF'
require("node:fs").writeFileSync(process.env.RUNTIME_HELPER_CALLED, "called\n")
EOF

set +e
OPENCODE_WEB_RETENTION_DAYS=0 "${ROOT_DIR}/.opencode_web_yolo_runtime.sh" bash -c 'exit 23'
disabled_status=$?
set -e
assert_equals 23 "$disabled_status"

set +e
OPENCODE_WEB_RETENTION_DAYS=1 OPENCODE_WEB_RETENTION_POLL_SECONDS=0 "${ROOT_DIR}/.opencode_web_yolo_runtime.sh" true >/dev/null 2>&1
poll_status=$?
set -e
if [ "$poll_status" -eq 0 ]; then fail "zero poll interval should fail"; fi

set +e
OPENCODE_WEB_RETENTION_DAYS=1 OPENCODE_WEB_RETENTION_POLL_SECONDS=2147483648 "${ROOT_DIR}/.opencode_web_yolo_runtime.sh" true >/dev/null 2>&1
poll_range_status=$?
set -e
if [ "$poll_range_status" -eq 0 ]; then fail "out-of-range poll interval should fail"; fi

app_command="${TMP_DIR}/app-command"
cat >"$app_command" <<'EOF'
#!/usr/bin/env bash
sleep 0.3
exit 23
EOF
chmod +x "$app_command"
set +e
CURL_ARGS_LOG="${TMP_DIR}/curl-args" RUNTIME_HELPER_CALLED="${TMP_DIR}/helper-called" OPENCODE_SERVER_PASSWORD=secret OPENCODE_WEB_RETENTION_DAYS=1 OPENCODE_WEB_RETENTION_HELPER="$runtime_helper" OPENCODE_WEB_RETENTION_POLL_SECONDS=1 "${ROOT_DIR}/.opencode_web_yolo_runtime.sh" "$app_command"
app_status=$?
set -e
assert_equals 23 "$app_status"
[ -e "${TMP_DIR}/helper-called" ] || fail "scheduler should start after health"
curl_args="$(<"${TMP_DIR}/curl-args")"
assert_not_contains "$curl_args" "secret"

cat >"$app_command" <<'EOF'
#!/usr/bin/env bash
trap 'exit 0' TERM INT
while true; do sleep 1; done
EOF
chmod +x "$app_command"
RUNTIME_HELPER_CALLED="${TMP_DIR}/signal-helper-called" OPENCODE_WEB_RETENTION_DAYS=1 OPENCODE_WEB_RETENTION_HELPER="$runtime_helper" OPENCODE_WEB_RETENTION_POLL_SECONDS=1 "${ROOT_DIR}/.opencode_web_yolo_runtime.sh" "$app_command" >/dev/null 2>&1 &
runtime_pid=$!
sleep 0.3
kill -TERM "$runtime_pid"
wait "$runtime_pid"

printf '%s\n' "PASS: session retention coverage"
