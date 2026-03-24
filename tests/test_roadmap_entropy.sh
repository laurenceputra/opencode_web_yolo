#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export HOME="${TMP_DIR}/home"
mkdir -p "${HOME}"
export OPENCODE_WEB_SKIP_UPDATE_CHECK=1

output="$("${ROOT_DIR}/.opencode_web_yolo.sh" check-roadmap 2>&1)"
assert_contains "$output" "opencode_web_yolo roadmap entropy report"
assert_contains "$output" "spec=docs/roadmap-entropy-detector.md"
assert_contains "$output" "status=ok"
assert_contains "$output" "checks="
assert_contains "$output" "PASS: roadmap entropy contract is aligned"

alias_output="$("${ROOT_DIR}/.opencode_web_yolo.sh" roadmap-entropy 2>&1)"
assert_contains "$alias_output" "status=ok"
assert_contains "$alias_output" "PASS: roadmap entropy contract is aligned"

printf '%s\n' "PASS: roadmap entropy detector"
