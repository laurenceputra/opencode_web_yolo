#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

readme="$(cat "${ROOT_DIR}/README.md")"

assert_contains "$readme" "## Quickstart"
assert_contains "$readme" "## Authentication Requirement"
assert_contains "$readme" "## Persistence Paths"
assert_contains "$readme" "## Reverse Proxy (Nginx)"
assert_contains "$readme" "## Reverse Proxy (Apache)"
assert_contains "$readme" "## Security Notes"
assert_contains "$readme" "## Troubleshooting"

printf '%s\n' "PASS: README required sections"
