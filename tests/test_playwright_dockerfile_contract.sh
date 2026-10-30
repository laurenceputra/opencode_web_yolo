#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

dockerfile_contents="$(cat "${ROOT_DIR}/.opencode_web_yolo.Dockerfile")"

assert_contains "$dockerfile_contents" "ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright"
assert_contains "$dockerfile_contents" "FROM node:22-slim"
assert_not_contains "$dockerfile_contents" "ARG BASE_IMAGE"
assert_contains "$dockerfile_contents" "node_version=\"\$(node --version)\""
assert_contains "$dockerfile_contents" "grep -Eq '^v22\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$'"
assert_contains "$dockerfile_contents" "node_major=\"\${node_major%%.*}\""
assert_contains "$dockerfile_contents" "/opt/opencode-web-yolo-node-version"
assert_contains "$dockerfile_contents" "/opt/opencode-web-yolo-node-major"
assert_contains "$dockerfile_contents" "npm install -g \"opencode-ai@\${OPENCODE_VERSION}\""
assert_not_contains "$dockerfile_contents" "ARG OPENCODE_NPM_PACKAGE"
assert_contains "$dockerfile_contents" "mkdir -p \"\${PLAYWRIGHT_BROWSERS_PATH}\""
assert_contains "$dockerfile_contents" "chmod 1777 \"\${PLAYWRIGHT_BROWSERS_PATH}\""
assert_contains "$dockerfile_contents" "ARG PLAYWRIGHT_VERSION=1.62.1"
assert_contains "$dockerfile_contents" "npm install -g \"@playwright/test@\${PLAYWRIGHT_VERSION}\""
assert_not_contains "$dockerfile_contents" "npm install -g playwright@latest"
assert_contains "$dockerfile_contents" "playwright_package_dir=\"\$(npm root -g)/@playwright/test\""
assert_contains "$dockerfile_contents" "installed_playwright_version"
assert_contains "$dockerfile_contents" "[ \"\${installed_playwright_version}\" = \"\${PLAYWRIGHT_VERSION}\" ]"
assert_contains "$dockerfile_contents" "playwright install --with-deps chromium"
assert_contains "$dockerfile_contents" "chmod -R a+rX \"\${PLAYWRIGHT_BROWSERS_PATH}\""
assert_contains "$dockerfile_contents" "/opt/opencode-web-yolo-playwright-version"
assert_contains "$dockerfile_contents" "/opt/opencode-web-yolo-playwright-expected-version"
assert_contains "$dockerfile_contents" "npm install -g wrangler@latest"
assert_contains "$dockerfile_contents" "/opt/opencode-web-yolo-wrangler"

line_arg_playwright="$(grep -n '^ARG OPENCODE_WEB_BUILD_PLAYWRIGHT=' "${ROOT_DIR}/.opencode_web_yolo.Dockerfile" | cut -d: -f1)"
line_arg_playwright_version="$(grep -n '^ARG PLAYWRIGHT_VERSION=' "${ROOT_DIR}/.opencode_web_yolo.Dockerfile" | cut -d: -f1)"
# shellcheck disable=SC2016 # Single quotes intentionally preserve literal Dockerfile shell syntax.
line_playwright_layer="$(grep -n '^RUN if \[ "\${OPENCODE_WEB_BUILD_PLAYWRIGHT}" = "1" \]; then \\$' "${ROOT_DIR}/.opencode_web_yolo.Dockerfile" | cut -d: -f1)"
line_arg_wrangler="$(grep -n '^ARG OPENCODE_WEB_BUILD_WRANGLER=' "${ROOT_DIR}/.opencode_web_yolo.Dockerfile" | cut -d: -f1)"
# shellcheck disable=SC2016 # Single quotes intentionally preserve literal Dockerfile shell syntax.
line_wrangler_layer="$(grep -n '^RUN if \[ "\${OPENCODE_WEB_BUILD_WRANGLER}" = "1" \]; then \\$' "${ROOT_DIR}/.opencode_web_yolo.Dockerfile" | cut -d: -f1)"
line_arg_wrapper_version="$(grep -n '^ARG WRAPPER_VERSION=' "${ROOT_DIR}/.opencode_web_yolo.Dockerfile" | cut -d: -f1)"
line_node_assertion="$(grep -n '^RUN node_version=' "${ROOT_DIR}/.opencode_web_yolo.Dockerfile" | cut -d: -f1)"
line_apt_layer="$(grep -n '^RUN apt-get update' "${ROOT_DIR}/.opencode_web_yolo.Dockerfile" | cut -d: -f1)"
# shellcheck disable=SC2016 # Single quotes intentionally preserve literal Dockerfile shell syntax.
line_metadata_layer="$(grep -n '^RUN mkdir -p /opt /workspace "\${OPENCODE_WEB_YOLO_HOME}" /app \\$' "${ROOT_DIR}/.opencode_web_yolo.Dockerfile" | cut -d: -f1)"

[ -n "$line_arg_playwright" ] || fail "missing OPENCODE_WEB_BUILD_PLAYWRIGHT arg declaration"
[ -n "$line_arg_playwright_version" ] || fail "missing PLAYWRIGHT_VERSION arg declaration"
[ -n "$line_playwright_layer" ] || fail "missing playwright layer"
[ -n "$line_arg_wrangler" ] || fail "missing OPENCODE_WEB_BUILD_WRANGLER arg declaration"
[ -n "$line_wrangler_layer" ] || fail "missing wrangler layer"
[ -n "$line_arg_wrapper_version" ] || fail "missing WRAPPER_VERSION arg declaration"
[ -n "$line_metadata_layer" ] || fail "missing metadata layer"
[ -n "$line_node_assertion" ] || fail "missing early Node 22 assertion"
[ -n "$line_apt_layer" ] || fail "missing apt layer"

[ "$line_arg_playwright" -lt "$line_playwright_layer" ] || fail "expected OPENCODE_WEB_BUILD_PLAYWRIGHT arg before playwright layer"
[ "$line_arg_playwright_version" -lt "$line_playwright_layer" ] || fail "expected PLAYWRIGHT_VERSION arg before playwright layer"
[ "$line_arg_wrangler" -lt "$line_wrangler_layer" ] || fail "expected OPENCODE_WEB_BUILD_WRANGLER arg before wrangler layer"
[ "$line_arg_wrapper_version" -lt "$line_metadata_layer" ] || fail "expected WRAPPER_VERSION arg before metadata layer"
[ "$line_node_assertion" -lt "$line_apt_layer" ] || fail "Node 22 assertion must precede apt/npm work"

printf '%s\n' "PASS: Playwright Dockerfile runtime contract"
