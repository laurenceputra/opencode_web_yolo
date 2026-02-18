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

output_long="$("${ROOT_DIR}/.opencode_web_yolo.sh" --help 2>&1)"
assert_contains "$output_long" "Usage:"
assert_contains "$output_long" "--help, -h, help"
assert_contains "$output_long" "--foreground, -f"
assert_contains "$output_long" "--no-pull"
assert_contains "$output_long" "opencode_web_yolo config"

output_short="$("${ROOT_DIR}/.opencode_web_yolo.sh" -h 2>&1)"
assert_contains "$output_short" "Usage:"
assert_contains "$output_short" "Wrapper flags:"

output_cmd="$("${ROOT_DIR}/.opencode_web_yolo.sh" help 2>&1)"
assert_contains "$output_cmd" "First-time setup:"

printf '%s\n' "PASS: help output"
