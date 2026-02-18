#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

entrypoint="$(cat "${ROOT_DIR}/.opencode_web_yolo_entrypoint.sh")"

assert_contains "$entrypoint" "useradd -m -d \"\${OPENCODE_WEB_YOLO_HOME}\""
assert_contains "$entrypoint" "usermod -d \"\${OPENCODE_WEB_YOLO_HOME}\" \"\${runtime_user}\""

printf '%s\n' "PASS: entrypoint home pin contract"
