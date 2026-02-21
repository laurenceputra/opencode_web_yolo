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

opencode_dir="${HOME}/.config/opencode"
codex_dir="${HOME}/.codex"
copilot_dir="${HOME}/.copilot"
claude_dir="${HOME}/.claude"

mkdir -p "$opencode_dir" "$codex_dir" "$copilot_dir" "$claude_dir"

printf '%s\n' "opencode" >"${opencode_dir}/AGENTS.md"
printf '%s\n' "codex" >"${codex_dir}/AGENTS.md"
printf '%s\n' "copilot" >"${copilot_dir}/copilot-instructions.md"
printf '%s\n' "claude" >"${claude_dir}/CLAUDE.md"

output_default="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_contains "$output_default" "-v ${HOME}/.config/opencode:/home/opencode/.config/opencode"
assert_contains "$output_default" "-v ${HOME}/.config/opencode/AGENTS.md:/home/opencode/.config/opencode/AGENTS.md:ro"
assert_not_contains "$output_default" "/etc/opencode/AGENTS.md"
assert_not_contains "$output_default" "OPENCODE_INSTRUCTION_PATH="
assert_contains "$output_default" "host_agents_source=opencode"
assert_contains "$output_default" "Using host instruction file from opencode: ${HOME}/.config/opencode/AGENTS.md"

rm -f "${opencode_dir}/AGENTS.md"
output_codex="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_contains "$output_codex" "host_agents_source=codex"
assert_contains "$output_codex" "host_agents_path=${HOME}/.codex/AGENTS.md"
assert_contains "$output_codex" "-v ${HOME}/.codex/AGENTS.md:/home/opencode/.config/opencode/AGENTS.md:ro"

rm -f "${codex_dir}/AGENTS.md"
output_copilot="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_contains "$output_copilot" "host_agents_source=copilot"
assert_contains "$output_copilot" "host_agents_path=${HOME}/.copilot/copilot-instructions.md"
assert_contains "$output_copilot" "-v ${HOME}/.copilot/copilot-instructions.md:/home/opencode/.config/opencode/AGENTS.md:ro"

rm -f "${copilot_dir}/copilot-instructions.md"
output_claude="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_contains "$output_claude" "host_agents_source=claude"
assert_contains "$output_claude" "host_agents_path=${HOME}/.claude/CLAUDE.md"
assert_contains "$output_claude" "-v ${HOME}/.claude/CLAUDE.md:/home/opencode/.config/opencode/AGENTS.md:ro"

mkdir -p "${TMP_DIR}/custom"
printf '%s\n' "custom" >"${TMP_DIR}/custom/AGENTS.md"
output_cli="$("${ROOT_DIR}/.opencode_web_yolo.sh" --agents-file "${TMP_DIR}/custom/AGENTS.md" --dry-run 2>&1)"
assert_contains "$output_cli" "-v ${TMP_DIR}/custom/AGENTS.md:/home/opencode/.config/opencode/AGENTS.md:ro"
assert_not_contains "$output_cli" "/etc/opencode/AGENTS.md"
assert_not_contains "$output_cli" "OPENCODE_INSTRUCTION_PATH="
assert_contains "$output_cli" "Using host instruction file from flag: ${TMP_DIR}/custom/AGENTS.md"

mkdir -p "${TMP_DIR}/env"
printf '%s\n' "env" >"${TMP_DIR}/env/AGENTS.md"
output_env="$(OPENCODE_HOST_AGENTS="${TMP_DIR}/env/AGENTS.md" "${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_contains "$output_env" "-v ${TMP_DIR}/env/AGENTS.md:/home/opencode/.config/opencode/AGENTS.md:ro"
assert_not_contains "$output_env" "/etc/opencode/AGENTS.md"
assert_not_contains "$output_env" "OPENCODE_INSTRUCTION_PATH="
assert_contains "$output_env" "Using host instruction file from env: ${TMP_DIR}/env/AGENTS.md"

output_no_host="$("${ROOT_DIR}/.opencode_web_yolo.sh" --no-host-agents --dry-run 2>&1)"
assert_not_contains "$output_no_host" "/home/opencode/.config/opencode/AGENTS.md:ro"
assert_not_contains "$output_no_host" "OPENCODE_INSTRUCTION_PATH="
assert_contains "$output_no_host" "Host instruction file mount disabled by --no-host-agents."

set +e
output_invalid="$("${ROOT_DIR}/.opencode_web_yolo.sh" --agents-file "${TMP_DIR}/missing/AGENTS.md" --dry-run 2>&1)"
status=$?
set -e
if [ "$status" -eq 0 ]; then
  fail "expected failure for invalid host instruction file path"
fi
assert_contains "$output_invalid" "Host instruction file not found"

rm -f "${claude_dir}/CLAUDE.md"
output_missing_default="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_not_contains "$output_missing_default" "/home/opencode/.config/opencode/AGENTS.md:ro"
assert_not_contains "$output_missing_default" "OPENCODE_INSTRUCTION_PATH="
assert_contains "$output_missing_default" "host_agents_source=none"
assert_contains "$output_missing_default" "host_agents_path="

printf '%s\n' "PASS: wrapper host AGENTS dry-run"
