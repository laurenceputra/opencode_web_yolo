#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
setup_fake_docker "${TMP_DIR}/bin" "$(<"${ROOT_DIR}/VERSION")"
export PATH="${TMP_DIR}/bin:${PATH}" HOME="${TMP_DIR}/home"
mkdir -p "$HOME"
export OPENCODE_SERVER_PASSWORD=secret OPENCODE_WEB_SKIP_UPDATE_CHECK=1 OPENCODE_WEB_SKIP_VERSION_CHECK=1
for days in 0 5; do
  output="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run --retention-days "$days" 2>&1)"
  assert_contains "$output" "retention_days=$days"
  output="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run --retention-days="$days" 2>&1)"
  assert_contains "$output" "retention_days=$days"
done
mkdir -p "${HOME}/.opencode_web_yolo"
printf '%s\n' 'export OPENCODE_WEB_RETENTION_DAYS=7' >"${HOME}/.opencode_web_yolo/config"
output="$(OPENCODE_WEB_RETENTION_DRY_RUN=1 "${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_contains "$output" 'retention_days=7'
assert_contains "$output" 'retention_dry_run=1'
assert_contains "$output" 'OPENCODE_WEB_RETENTION_DAYS=7'
assert_contains "$output" 'OPENCODE_WEB_RETENTION_DRY_RUN=1'
assert_contains "$output" 'session-retention.last-success'
output="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run --retention-days=0 2>&1)"
assert_contains "$output" 'retention_days=0'
rm "${HOME}/.opencode_web_yolo/config"
if output="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run --retention-days invalid 2>&1)"; then fail 'invalid days accepted'; fi
assert_contains "$output" 'must be a non-negative integer'
set +e
OPENCODE_WEB_RETENTION_DAYS=0 "${ROOT_DIR}/.opencode_web_yolo_runtime.sh" bash -c 'exit 23'
status=$?
set -e
assert_equals 23 "$status"
for poll in 0 2147483648; do
  if OPENCODE_WEB_RETENTION_DAYS=1 OPENCODE_WEB_RETENTION_POLL_SECONDS="$poll" "${ROOT_DIR}/.opencode_web_yolo_runtime.sh" true; then fail 'invalid poll accepted'; fi
done
node "${ROOT_DIR}/tests/retention_v2.cjs"
node "${ROOT_DIR}/tests/retention_lifecycle.cjs"
printf '%s\n' 'PASS: v2 session retention'
