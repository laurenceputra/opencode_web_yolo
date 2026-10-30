#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
FAKE_BIN="${TMP_DIR}/bin"
SQLITE_LOG="${TMP_DIR}/sqlite.log"
GOSU_LOG="${TMP_DIR}/gosu.log"
ENTRYPOINT_COPY="${TMP_DIR}/entrypoint.sh"
mkdir -p "$FAKE_BIN"

entrypoint_source="$(<"${ROOT_DIR}/.opencode_web_yolo_entrypoint.sh")"
fixed_sudoers_path=/etc/sudoers.d/90-opencode-web-yolo
assert_contains "$entrypoint_source" "$fixed_sudoers_path"
# Keep production's fixed root-owned path; redirect only this temporary test copy.
entrypoint_source="${entrypoint_source//"${fixed_sudoers_path}"/"${TMP_DIR}/sudoers"}"
printf '%s\n' "$entrypoint_source" >"$ENTRYPOINT_COPY"
chmod +x "$ENTRYPOINT_COPY"

cat >"${FAKE_BIN}/gosu" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
user="$1"
shift
printf 'user=%s command=%s\n' "$user" "$*" >>"${OPENCODE_WEB_TEST_GOSU_LOG}"
"$@"
EOF
chmod +x "${FAKE_BIN}/gosu"

cat >"${FAKE_BIN}/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
kill_after="$1"
test "$kill_after" = "--kill-after=5"
shift
timeout_seconds="$1"
shift
printf 'timeout=%s command=%s\n' "$timeout_seconds" "$*" >>"${OPENCODE_WEB_TEST_GOSU_LOG}"
if [ "${OPENCODE_WEB_TEST_TIMEOUT_EXIT:-0}" = "124" ]; then
  exit 124
fi
"$@"
EOF
chmod +x "${FAKE_BIN}/timeout"

cat >"${FAKE_BIN}/mkdir" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
last_arg="${!#}"
if [ "$last_arg" = "/workspace" ]; then
  exit 0
fi
exec /usr/bin/mkdir "$@"
EOF
chmod +x "${FAKE_BIN}/mkdir"

cat >"${FAKE_BIN}/chown" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "${FAKE_BIN}/chown"

cat >"${FAKE_BIN}/sqlite3" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${OPENCODE_WEB_TEST_SQLITE_LOG}"
if [ "${OPENCODE_WEB_TEST_SQLITE_FAIL:-0}" = "1" ]; then
  exit 1
fi
EOF
chmod +x "${FAKE_BIN}/sqlite3"

export PATH="${FAKE_BIN}:${PATH}"
export OPENCODE_SERVER_PASSWORD=secret
export OPENCODE_WEB_TEST_GOSU_LOG="$GOSU_LOG"
export OPENCODE_WEB_TEST_SQLITE_LOG="$SQLITE_LOG"
LOCAL_UID="$(id -u)"
LOCAL_GID="$(id -g)"
LOCAL_USER="$(id -un)"
export LOCAL_UID LOCAL_GID LOCAL_USER

run_entrypoint() {
  local home="$1" data_home="$2"
  shift 2
  mkdir -p "$home" "$data_home"
  rm -f "${TMP_DIR}/sudoers"
  : >"$GOSU_LOG"
  : >"$SQLITE_LOG"
  OPENCODE_WEB_YOLO_HOME="$home" \
    XDG_CONFIG_HOME="${home}/config" \
    XDG_DATA_HOME="$data_home" \
    XDG_STATE_HOME="${data_home}/opencode/state" \
    OPENCODE_WEB_RETENTION_DAYS=0 \
    OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS="${OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS-300}" \
    "$ENTRYPOINT_COPY" "$@"
}

existing_home="${TMP_DIR}/existing-home"
existing_data="${TMP_DIR}/custom-xdg-data"
existing_db="${existing_data}/opencode/opencode.db"
mkdir -p "$(dirname "$existing_db")"
: >"$existing_db"
existing_output="$(run_entrypoint "$existing_home" "$existing_data" true 2>&1)"
assert_contains "$existing_output" "VACUUM: compacting OpenCode database at ${existing_db}"
assert_contains "$(cat "$GOSU_LOG")" "user=${LOCAL_USER} command=timeout --kill-after=5 300 sqlite3 -cmd .timeout 5000 ${existing_db} VACUUM;"
assert_contains "$(cat "$SQLITE_LOG")" "-cmd .timeout 5000 ${existing_db} VACUUM;"

custom_home="${TMP_DIR}/custom-timeout-home"
custom_data="${TMP_DIR}/custom-timeout-data"
custom_db="${custom_data}/opencode/opencode.db"
mkdir -p "$(dirname "$custom_db")"
: >"$custom_db"
custom_output="$(OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS=42 run_entrypoint "$custom_home" "$custom_data" true 2>&1)"
assert_contains "$custom_output" "VACUUM: compacting OpenCode database at ${custom_db}"
assert_contains "$(cat "$GOSU_LOG")" "user=${LOCAL_USER} command=timeout --kill-after=5 42 sqlite3 -cmd .timeout 5000 ${custom_db} VACUUM;"

missing_home="${TMP_DIR}/missing-home"
missing_data="${TMP_DIR}/missing-data"
missing_output="$(run_entrypoint "$missing_home" "$missing_data" touch "${TMP_DIR}/app-ran" 2>&1)"
assert_not_contains "$missing_output" "VACUUM:"
assert_not_contains "$(cat "$GOSU_LOG")" "sqlite3"
if [ -e "${missing_data}/opencode/opencode.db" ]; then
  fail "missing database must not be created"
fi
if [ ! -e "${TMP_DIR}/app-ran" ]; then
  fail "application did not execute when the database was missing"
fi

failure_home="${TMP_DIR}/failure-home"
failure_data="${TMP_DIR}/failure-data"
failure_db="${failure_data}/opencode/opencode.db"
mkdir -p "$(dirname "$failure_db")"
: >"$failure_db"
set +e
failure_output="$(OPENCODE_WEB_TEST_SQLITE_FAIL=1 run_entrypoint "$failure_home" "$failure_data" touch "${TMP_DIR}/app-ran-after-failure" 2>&1)"
failure_status=$?
set -e
assert_equals "0" "$failure_status"
assert_contains "$failure_output" "WARNING: startup VACUUM failed for ${failure_db}; continuing startup."
assert_contains "$(cat "$GOSU_LOG")" "user=${LOCAL_USER} command=timeout --kill-after=5 300 sqlite3 -cmd .timeout 5000 ${failure_db} VACUUM;"
if [ ! -e "${TMP_DIR}/app-ran-after-failure" ]; then
  fail "application did not continue after startup VACUUM failure"
fi

timeout_home="${TMP_DIR}/timeout-home"
timeout_data="${TMP_DIR}/timeout-data"
timeout_db="${timeout_data}/opencode/opencode.db"
mkdir -p "$(dirname "$timeout_db")"
: >"$timeout_db"
set +e
timeout_output="$(OPENCODE_WEB_TEST_TIMEOUT_EXIT=124 run_entrypoint "$timeout_home" "$timeout_data" touch "${TMP_DIR}/app-ran-after-timeout" 2>&1)"
timeout_status=$?
set -e
assert_equals "0" "$timeout_status"
assert_contains "$timeout_output" "WARNING: startup VACUUM timed out after the 300-second TERM deadline (KILL escalation after 5 additional seconds); continuing startup."
assert_contains "$(cat "$GOSU_LOG")" "user=${LOCAL_USER} command=timeout --kill-after=5 300 sqlite3 -cmd .timeout 5000 ${timeout_db} VACUUM;"
if [ ! -e "${TMP_DIR}/app-ran-after-timeout" ]; then
  fail "application did not continue after startup VACUUM timeout"
fi

custom_timeout_home="${TMP_DIR}/custom-timeout-warning-home"
custom_timeout_data="${TMP_DIR}/custom-timeout-warning-data"
custom_timeout_db="${custom_timeout_data}/opencode/opencode.db"
mkdir -p "$(dirname "$custom_timeout_db")"
: >"$custom_timeout_db"
set +e
custom_timeout_output="$(OPENCODE_WEB_TEST_TIMEOUT_EXIT=124 OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS=42 run_entrypoint "$custom_timeout_home" "$custom_timeout_data" true 2>&1)"
custom_timeout_status=$?
set -e
assert_equals "0" "$custom_timeout_status"
assert_contains "$custom_timeout_output" "WARNING: startup VACUUM timed out after the 42-second TERM deadline (KILL escalation after 5 additional seconds); continuing startup."

for invalid_timeout in '' 0 01 2147483648 invalid; do
  set +e
  invalid_output="$(OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS="$invalid_timeout" run_entrypoint "${TMP_DIR}/invalid-home-${invalid_timeout}" "${TMP_DIR}/invalid-data-${invalid_timeout}" true 2>&1)"
  invalid_status=$?
  set -e
  assert_equals 1 "$invalid_status"
  assert_contains "$invalid_output" "OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS"
done

printf '%s\n' "PASS: startup VACUUM behavior"
