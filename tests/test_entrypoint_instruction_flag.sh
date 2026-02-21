#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

entrypoint="$(cat "${ROOT_DIR}/.opencode_web_yolo_entrypoint.sh")"

assert_not_contains "$entrypoint" "set -- opencode web --instructions"
assert_not_contains "$entrypoint" "--instructions \"\${INSTRUCTIONS}\""

printf '%s\n' "PASS: entrypoint does not inject unsupported instruction flags"
