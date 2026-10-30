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
export OPENCODE_PASSWORD=preferred-alone-must-not-bypass-wrapper
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

export OPENCODE_SERVER_PASSWORD=secret
if output="$(OPENCODE_SERVER_USERNAME=custom "${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"; then
  fail "custom username must fail"
fi
assert_contains "$output" "requires OPENCODE_SERVER_USERNAME=opencode"
for version in latest 1.19.5 3.0.0 '2.2.1;bad'; do
  if output="$(OPENCODE_WEB_EXPECTED_OPENCODE_VERSION="$version" "${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"; then
    fail "unsupported version $version must fail"
  fi
  assert_contains "$output" "must be an exact stable 2.x version"
done
output="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_contains "$output" "-e OPENCODE_PASSWORD"
assert_not_contains "$output" "preferred-alone-must-not-bypass-wrapper"
assert_not_contains "$output" "secret"

printf '%s\n' "PASS: password-required and v2 compatibility gates"
