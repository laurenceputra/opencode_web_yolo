#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

unset OPENCODE_SERVER_PASSWORD || true
export OPENCODE_WEB_RETENTION_DAYS=0
export OPENCODE_PASSWORD=preferred-alone-must-not-bypass-wrapper

set +e
output="$("${ROOT_DIR}/.opencode_web_yolo_entrypoint.sh" true 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  fail "expected entrypoint to fail when OPENCODE_SERVER_PASSWORD is missing"
fi
assert_contains "$output" "OPENCODE_SERVER_PASSWORD must be set and non-empty"

export OPENCODE_SERVER_PASSWORD=secret
if output="$(OPENCODE_SERVER_USERNAME=custom "${ROOT_DIR}/.opencode_web_yolo_entrypoint.sh" true 2>&1)"; then
  fail "entrypoint custom username must fail"
fi
assert_contains "$output" "requires OPENCODE_SERVER_USERNAME=opencode"
if output="$(OPENCODE_WEB_RETENTION_DAYS=30 "${ROOT_DIR}/.opencode_web_yolo_entrypoint.sh" true 2>&1)"; then
  fail "entrypoint enabled retention must fail"
fi
assert_contains "$output" "retention is unsupported on OpenCode 2.x"

printf '%s\n' "PASS: entrypoint password guard"
