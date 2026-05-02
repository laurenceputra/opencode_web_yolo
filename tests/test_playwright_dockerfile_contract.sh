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

line_arg_npm_package="$(grep -n '^ARG OPENCODE_NPM_PACKAGE=' "${ROOT_DIR}/.opencode_web_yolo.Dockerfile" | cut -d: -f1)"
line_npm_install="$(grep -n '^RUN npm install -g \"\${OPENCODE_NPM_PACKAGE}@\${OPENCODE_VERSION}\"$' "${ROOT_DIR}/.opencode_web_yolo.Dockerfile" | cut -d: -f1)"
line_arg_playwright="$(grep -n '^ARG OPENCODE_WEB_BUILD_PLAYWRIGHT=' "${ROOT_DIR}/.opencode_web_yolo.Dockerfile" | cut -d: -f1)"
line_playwright_layer="$(grep -n '^RUN if \[ "\${OPENCODE_WEB_BUILD_PLAYWRIGHT}" = "1" \]; then \\$' "${ROOT_DIR}/.opencode_web_yolo.Dockerfile" | cut -d: -f1)"
line_arg_wrapper_version="$(grep -n '^ARG WRAPPER_VERSION=' "${ROOT_DIR}/.opencode_web_yolo.Dockerfile" | cut -d: -f1)"
line_metadata_layer="$(grep -n '^RUN mkdir -p /opt /workspace "\${OPENCODE_WEB_YOLO_HOME}" /app \\$' "${ROOT_DIR}/.opencode_web_yolo.Dockerfile" | cut -d: -f1)"

[ -n "$line_arg_npm_package" ] || fail "missing OPENCODE_NPM_PACKAGE arg declaration"
[ -n "$line_npm_install" ] || fail "missing opencode npm install layer"
[ -n "$line_arg_playwright" ] || fail "missing OPENCODE_WEB_BUILD_PLAYWRIGHT arg declaration"
[ -n "$line_playwright_layer" ] || fail "missing playwright layer"
[ -n "$line_arg_wrapper_version" ] || fail "missing WRAPPER_VERSION arg declaration"
[ -n "$line_metadata_layer" ] || fail "missing metadata layer"

[ "$line_arg_npm_package" -lt "$line_npm_install" ] || fail "expected OPENCODE_NPM_PACKAGE arg before npm install layer"
[ "$line_arg_playwright" -lt "$line_playwright_layer" ] || fail "expected OPENCODE_WEB_BUILD_PLAYWRIGHT arg before playwright layer"
[ "$line_arg_wrapper_version" -lt "$line_metadata_layer" ] || fail "expected WRAPPER_VERSION arg before metadata layer"

printf '%s\n' "PASS: Playwright Dockerfile runtime contract"
