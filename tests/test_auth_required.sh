#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
FAKE_BIN="${TMP_DIR}/bin"
WRAPPER_VERSION="$(tr -d '[:space:]' <"${ROOT_DIR}/VERSION")"

setup_fake_docker "$FAKE_BIN" "$WRAPPER_VERSION"

export PATH="${FAKE_BIN}:${PATH}"
export HOME="${TMP_DIR}/home"
unset OPENCODE_SERVER_PASSWORD || true
mkdir -p "${HOME}"
export OPENCODE_WEB_SKIP_UPDATE_CHECK=1
export OPENCODE_WEB_SKIP_VERSION_CHECK=1

set +e
output="$("${ROOT_DIR}/.opencode_web_yolo.sh" 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  fail "expected failure when OPENCODE_SERVER_PASSWORD is missing"
fi
assert_contains "$output" "OPENCODE_SERVER_PASSWORD must be set and non-empty"
assert_contains "$output" "Initial setup:"
assert_contains "$output" "opencode_web_yolo config"
assert_contains "$output" "${HOME}/.opencode_web_yolo/config"
assert_contains "$output" "export OPENCODE_SERVER_PASSWORD='change-me-now'"

set +e
output_rehearsal="$("${ROOT_DIR}/.opencode_web_yolo.sh" rehearse-migrations 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  fail "expected rehearsal mode to fail when OPENCODE_SERVER_PASSWORD is missing"
fi
assert_contains "$output_rehearsal" "OPENCODE_SERVER_PASSWORD must be set and non-empty"
assert_contains "$output_rehearsal" "Authentication is mandatory for all access, including localhost."

printf '%s\n' "PASS: password-required gate"
