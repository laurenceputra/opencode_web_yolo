#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

readme="$(cat "${ROOT_DIR}/README.md")"

assert_contains "$readme" "ProxyPass        /global/event"
assert_contains "$readme" "ProxyPass        /event"
assert_contains "$readme" "SetEnvIfNoCase Request_URI \"^/(global/event|event)\" no-gzip=1"
assert_not_contains "$readme" "/session/event"

printf '%s\n' "PASS: apache endpoint docs contract"
