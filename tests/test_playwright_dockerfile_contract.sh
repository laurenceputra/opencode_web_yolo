#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

dockerfile_contents="$(cat "${ROOT_DIR}/.opencode_web_yolo.Dockerfile")"

assert_contains "$dockerfile_contents" "ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright"
assert_contains "$dockerfile_contents" "mkdir -p \"\${PLAYWRIGHT_BROWSERS_PATH}\""
assert_contains "$dockerfile_contents" "chmod 1777 \"\${PLAYWRIGHT_BROWSERS_PATH}\""
assert_contains "$dockerfile_contents" "npm install -g playwright@latest"
assert_contains "$dockerfile_contents" "playwright install --with-deps chromium"
assert_contains "$dockerfile_contents" "chmod -R a+rX \"\${PLAYWRIGHT_BROWSERS_PATH}\""

printf '%s\n' "PASS: Playwright Dockerfile runtime contract"
