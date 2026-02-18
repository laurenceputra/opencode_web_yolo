#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

technical="$(cat "${ROOT_DIR}/TECHNICAL.md")"

assert_contains "$technical" "## Runtime Architecture"
assert_contains "$technical" "## Security Model"
assert_contains "$technical" "## Proxy Streaming Notes"
assert_contains "$technical" "## Update and Re-exec"
assert_contains "$technical" "## Rebuild Decision Logic"
assert_contains "$technical" "## Test and CI Strategy"
assert_contains "$technical" "## Release Checklist"

printf '%s\n' "PASS: TECHNICAL required sections"
