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

output="$("${ROOT_DIR}/.opencode_web_yolo.sh" health 2>&1)"

assert_contains "$output" "opencode_web_yolo health report"
assert_contains "$output" "opencode_config_dir=${HOME}/.config/opencode"
assert_contains "$output" "opencode_data_dir=${HOME}/.local/share/opencode"
assert_contains "$output" "container_name=opencode_web_yolo"
assert_contains "$output" "restart_policy=unless-stopped"
assert_contains "$output" "run_detached=1"
assert_contains "$output" "auto_pull=1"
assert_contains "$output" "build_pull=0"
assert_contains "$output" "runtime_env_home=/home/opencode"
assert_contains "$output" "runtime_env_xdg_config_home=/home/opencode/.config"
assert_contains "$output" "runtime_env_xdg_data_home=/home/opencode/.local/share"
assert_contains "$output" "runtime_env_xdg_state_home=/home/opencode/.local/share/opencode/state"
assert_contains "$output" "container_env_home=missing"
assert_contains "$output" "container_env_xdg_config_home=missing"
assert_contains "$output" "container_env_xdg_data_home=missing"
assert_contains "$output" "container_env_xdg_state_home=missing"
assert_contains "$output" "docker_cli=ok"

printf '%s\n' "PASS: health output contract"
