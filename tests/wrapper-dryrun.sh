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
unset XDG_CONFIG_HOME XDG_DATA_HOME || true
mkdir -p "${HOME}"
export OPENCODE_WEB_SKIP_UPDATE_CHECK=1
export OPENCODE_WEB_SKIP_VERSION_CHECK=1
export OPENCODE_SERVER_PASSWORD="secret"

default_agents_dir="${HOME}/.codex"
mkdir -p "$default_agents_dir"
printf '%s\n' "default" >"${default_agents_dir}/AGENTS.md"

output_default="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_contains "$output_default" "-v ${HOME}/.codex/AGENTS.md:/etc/opencode/AGENTS.md:ro"
assert_contains "$output_default" "-e OPENCODE_INSTRUCTION_PATH=/etc/opencode/AGENTS.md"
assert_contains "$output_default" "Using host AGENTS.md from default: ${HOME}/.codex/AGENTS.md"

mkdir -p "${TMP_DIR}/custom"
printf '%s\n' "custom" >"${TMP_DIR}/custom/AGENTS.md"
output_cli="$("${ROOT_DIR}/.opencode_web_yolo.sh" --agents-file "${TMP_DIR}/custom/AGENTS.md" --dry-run 2>&1)"
assert_contains "$output_cli" "-v ${TMP_DIR}/custom/AGENTS.md:/etc/opencode/AGENTS.md:ro"
assert_contains "$output_cli" "Using host AGENTS.md from flag: ${TMP_DIR}/custom/AGENTS.md"

mkdir -p "${TMP_DIR}/env"
printf '%s\n' "env" >"${TMP_DIR}/env/AGENTS.md"
output_env="$(OPENCODE_HOST_AGENTS="${TMP_DIR}/env/AGENTS.md" "${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_contains "$output_env" "-v ${TMP_DIR}/env/AGENTS.md:/etc/opencode/AGENTS.md:ro"
assert_contains "$output_env" "Using host AGENTS.md from env: ${TMP_DIR}/env/AGENTS.md"

output_no_host="$("${ROOT_DIR}/.opencode_web_yolo.sh" --no-host-agents --dry-run 2>&1)"
assert_not_contains "$output_no_host" "/etc/opencode/AGENTS.md"
assert_contains "$output_no_host" "Host AGENTS.md mount disabled by --no-host-agents."

set +e
output_invalid="$("${ROOT_DIR}/.opencode_web_yolo.sh" --agents-file "${TMP_DIR}/missing/AGENTS.md" --dry-run 2>&1)"
status=$?
set -e
if [ "$status" -eq 0 ]; then
  fail "expected failure for invalid host AGENTS.md path"
fi
assert_contains "$output_invalid" "Host AGENTS.md not found"

rm -f "${default_agents_dir}/AGENTS.md"
output_missing_default="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_not_contains "$output_missing_default" "/etc/opencode/AGENTS.md"
assert_contains "$output_missing_default" "host_agents_source=default"

printf '%s\n' "PASS: wrapper host AGENTS dry-run"
