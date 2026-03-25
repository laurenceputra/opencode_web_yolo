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
mkdir -p "${HOME}/.config/opencode"
printf '%s\n' "host-agents" >"${HOME}/.config/opencode/AGENTS.md"
export OPENCODE_WEB_SKIP_UPDATE_CHECK=1
export OPENCODE_WEB_SKIP_VERSION_CHECK=1
export OPENCODE_SERVER_PASSWORD="secret"
export OPENCODE_WEB_CONFIG_DIR="${TMP_DIR}/host-config"
export OPENCODE_WEB_DATA_DIR="${TMP_DIR}/host-data"

output_dry_run="$("${ROOT_DIR}/.opencode_web_yolo.sh" rehearse-migrations --dry-run -- --model local 2>&1)"

assert_contains "$output_dry_run" "rehearsal_mode=1"
assert_contains "$output_dry_run" "rehearsal_source_config_dir=${OPENCODE_WEB_CONFIG_DIR}"
assert_contains "$output_dry_run" "rehearsal_source_data_dir=${OPENCODE_WEB_DATA_DIR}"
assert_contains "$output_dry_run" "host_agents_source=opencode"
assert_contains "$output_dry_run" "host_agents_path=${HOME}/.config/opencode/AGENTS.md"
assert_contains "$output_dry_run" "host_agents_delivery=scratch-copy"
assert_contains "$output_dry_run" "Using host instruction file from opencode: ${HOME}/.config/opencode/AGENTS.md (copied into rehearsal scratch config at "
assert_contains "$output_dry_run" "--model local"
assert_contains "$output_dry_run" "restart_policy=none"
assert_contains "$output_dry_run" "container_name=opencode_web_yolo-rehearsal-"
assert_contains "$output_dry_run" "rehearsal_cleanup=wrapper-exit"
assert_not_contains "$output_dry_run" "rehearsal_cleanup=after-container-exit"
assert_not_contains "$output_dry_run" "-v ${OPENCODE_WEB_CONFIG_DIR}:/home/opencode/.config/opencode"
assert_not_contains "$output_dry_run" "-v ${OPENCODE_WEB_DATA_DIR}:/home/opencode/.local/share/opencode"
assert_not_contains "$output_dry_run" ":/home/opencode/.config/opencode/AGENTS.md:ro"

rehearsal_mount_config_dir="$(printf '%s\n' "$output_dry_run" | sed -n 's/^rehearsal_mount_config_dir=//p')"
rehearsal_mount_data_dir="$(printf '%s\n' "$output_dry_run" | sed -n 's/^rehearsal_mount_data_dir=//p')"

[ -n "$rehearsal_mount_config_dir" ] || fail "expected rehearsal_mount_config_dir in dry-run output"
[ -n "$rehearsal_mount_data_dir" ] || fail "expected rehearsal_mount_data_dir in dry-run output"
[ "$rehearsal_mount_config_dir" != "$OPENCODE_WEB_CONFIG_DIR" ] || fail "expected scratch config mount to differ from host config dir"
[ "$rehearsal_mount_data_dir" != "$OPENCODE_WEB_DATA_DIR" ] || fail "expected scratch data mount to differ from host data dir"
assert_contains "$output_dry_run" "-v ${rehearsal_mount_config_dir}:/home/opencode/.config/opencode"
assert_contains "$output_dry_run" "-v ${rehearsal_mount_data_dir}:/home/opencode/.local/share/opencode"
assert_contains "$output_dry_run" "rehearsal_host_agents_path=${rehearsal_mount_config_dir}/AGENTS.md"

mkdir -p "${TMP_DIR}/custom"
printf '%s\n' "custom-agents" >"${TMP_DIR}/custom/AGENTS.md"
output_flag_override="$("${ROOT_DIR}/.opencode_web_yolo.sh" rehearse-migrations --dry-run --agents-file "${TMP_DIR}/custom/AGENTS.md" 2>&1)"
assert_contains "$output_flag_override" "host_agents_source=flag"
assert_contains "$output_flag_override" "host_agents_path=${TMP_DIR}/custom/AGENTS.md"
assert_contains "$output_flag_override" "host_agents_delivery=scratch-copy"
assert_contains "$output_flag_override" "rehearsal_host_agents_path="
assert_not_contains "$output_flag_override" "-v ${TMP_DIR}/custom/AGENTS.md:/home/opencode/.config/opencode/AGENTS.md:ro"

if [ -e "$OPENCODE_WEB_CONFIG_DIR" ]; then
  fail "expected rehearsal dry-run to avoid creating host config dir"
fi
if [ -e "$OPENCODE_WEB_DATA_DIR" ]; then
  fail "expected rehearsal dry-run to avoid creating host data dir"
fi

output_run="$("${ROOT_DIR}/.opencode_web_yolo.sh" rehearse-migrations --foreground --verbose 2>&1)"
scratch_root="$(printf '%s\n' "$output_run" | sed -n 's/^\[opencode_web_yolo\] DEBUG: Prepared rehearsal scratch root //p' | sed 's/\.$//' | tail -n 1)"

[ -n "$scratch_root" ] || fail "expected verbose rehearsal output to include scratch root"
if [ -e "$scratch_root" ]; then
  fail "expected rehearsal scratch root to be cleaned after foreground run"
fi
if [ -e "$OPENCODE_WEB_CONFIG_DIR" ]; then
  fail "expected rehearsal foreground run to avoid creating host config dir"
fi
if [ -e "$OPENCODE_WEB_DATA_DIR" ]; then
  fail "expected rehearsal foreground run to avoid creating host data dir"
fi
assert_contains "$output_run" "Migration rehearsal mode active"
assert_contains "$output_run" "cleanup=wrapper-exit"
assert_contains "$output_run" "container_name=opencode_web_yolo-rehearsal-"

printf '%s\n' "PASS: migration rehearsal behavior"
