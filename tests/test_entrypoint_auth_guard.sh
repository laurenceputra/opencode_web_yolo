#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

unset OPENCODE_SERVER_PASSWORD || true

set +e
output="$("${ROOT_DIR}/.opencode_web_yolo_entrypoint.sh" true 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  fail "expected entrypoint to fail when OPENCODE_SERVER_PASSWORD is missing"
fi
assert_contains "$output" "OPENCODE_SERVER_PASSWORD must be set and non-empty"

printf '%s\n' "PASS: entrypoint password guard"
