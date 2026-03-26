#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

FUZZ_SEED=17
LAUNCH_MODES=(detached foreground)
SENSITIVE_MODES=(none gh ssh both)
AGENT_PROFILES=(none opencode codex copilot claude env flag disabled)

TMP_DIR="$(create_test_tmpdir)"
trap 'rm -rf "$TMP_DIR"' EXIT
FAKE_BIN="${TMP_DIR}/bin"
WRAPPER_VERSION="$(tr -d '[:space:]' <"${ROOT_DIR}/VERSION")"

setup_fake_docker "$FAKE_BIN" "$WRAPPER_VERSION"
setup_fake_gh "$FAKE_BIN"

export PATH="${FAKE_BIN}:${PATH}"
export OPENCODE_WEB_SKIP_UPDATE_CHECK=1
export OPENCODE_WEB_SKIP_VERSION_CHECK=1

CASE_AGENT_ARGS=()
CASE_EXPECTED_AGENT_SOURCE=""
CASE_EXPECTED_AGENT_PATH=""
CASE_EXPECTED_AGENT_DISABLED=0
CASE_EXPECTED_AGENT_SELECTED=0
CASE_EXPECTED_AGENT_LOG=""

write_fixture_file() {
  local path="$1"
  local content="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" >"$path"
}

populate_all_default_host_agents() {
  write_fixture_file "${HOME}/.config/opencode/AGENTS.md" "opencode"
  write_fixture_file "${HOME}/.codex/AGENTS.md" "codex"
  write_fixture_file "${HOME}/.copilot/copilot-instructions.md" "copilot"
  write_fixture_file "${HOME}/.claude/CLAUDE.md" "claude"
}

prepare_case_environment() {
  local case_root="$1"

  export HOME="${case_root}/home"
  export XDG_CONFIG_HOME="${HOME}/.config"
  export OPENCODE_WEB_CONFIG_DIR="${case_root}/host-config"
  export OPENCODE_WEB_DATA_DIR="${case_root}/host-data"

  mkdir -p "${HOME}" "${HOME}/.config/gh" "${HOME}/.ssh"
  write_fixture_file "${HOME}/.gitconfig" "[user]"

  unset OPENCODE_HOST_AGENTS GH_AUTH_FAIL GIT_CONFIG_GLOBAL OPENCODE_WEB_DRY_RUN || true
}

configure_agent_profile() {
  local case_root="$1"
  local profile="$2"

  CASE_AGENT_ARGS=()
  CASE_EXPECTED_AGENT_SOURCE=""
  CASE_EXPECTED_AGENT_PATH=""
  CASE_EXPECTED_AGENT_DISABLED=0
  CASE_EXPECTED_AGENT_SELECTED=0
  CASE_EXPECTED_AGENT_LOG=""

  case "$profile" in
    none)
      CASE_EXPECTED_AGENT_SOURCE="none"
      ;;
    opencode)
      populate_all_default_host_agents
      CASE_EXPECTED_AGENT_SOURCE="opencode"
      CASE_EXPECTED_AGENT_PATH="${HOME}/.config/opencode/AGENTS.md"
      CASE_EXPECTED_AGENT_SELECTED=1
      ;;
    codex)
      write_fixture_file "${HOME}/.codex/AGENTS.md" "codex"
      write_fixture_file "${HOME}/.copilot/copilot-instructions.md" "copilot"
      write_fixture_file "${HOME}/.claude/CLAUDE.md" "claude"
      CASE_EXPECTED_AGENT_SOURCE="codex"
      CASE_EXPECTED_AGENT_PATH="${HOME}/.codex/AGENTS.md"
      CASE_EXPECTED_AGENT_SELECTED=1
      ;;
    copilot)
      write_fixture_file "${HOME}/.copilot/copilot-instructions.md" "copilot"
      write_fixture_file "${HOME}/.claude/CLAUDE.md" "claude"
      CASE_EXPECTED_AGENT_SOURCE="copilot"
      CASE_EXPECTED_AGENT_PATH="${HOME}/.copilot/copilot-instructions.md"
      CASE_EXPECTED_AGENT_SELECTED=1
      ;;
    claude)
      write_fixture_file "${HOME}/.claude/CLAUDE.md" "claude"
      CASE_EXPECTED_AGENT_SOURCE="claude"
      CASE_EXPECTED_AGENT_PATH="${HOME}/.claude/CLAUDE.md"
      CASE_EXPECTED_AGENT_SELECTED=1
      ;;
    env)
      populate_all_default_host_agents
      CASE_EXPECTED_AGENT_SOURCE="env"
      CASE_EXPECTED_AGENT_PATH="${case_root}/env/AGENTS.md"
      write_fixture_file "${CASE_EXPECTED_AGENT_PATH}" "env"
      export OPENCODE_HOST_AGENTS="${CASE_EXPECTED_AGENT_PATH}"
      CASE_EXPECTED_AGENT_SELECTED=1
      ;;
    flag)
      populate_all_default_host_agents
      CASE_EXPECTED_AGENT_SOURCE="flag"
      CASE_EXPECTED_AGENT_PATH="${case_root}/flag/AGENTS.md"
      write_fixture_file "${CASE_EXPECTED_AGENT_PATH}" "flag"
      CASE_AGENT_ARGS=(--agents-file "${CASE_EXPECTED_AGENT_PATH}")
      CASE_EXPECTED_AGENT_SELECTED=1
      ;;
    disabled)
      populate_all_default_host_agents
      CASE_EXPECTED_AGENT_SOURCE="disabled"
      CASE_EXPECTED_AGENT_DISABLED=1
      CASE_EXPECTED_AGENT_LOG="Host instruction file mount disabled by --no-host-agents."
      CASE_AGENT_ARGS=(--no-host-agents)
      ;;
    *)
      fail "unknown agent profile: ${profile}"
      ;;
  esac

  if [ "$CASE_EXPECTED_AGENT_SELECTED" -eq 1 ]; then
    CASE_EXPECTED_AGENT_LOG="Using host instruction file from ${CASE_EXPECTED_AGENT_SOURCE}: ${CASE_EXPECTED_AGENT_PATH}"
  fi
}

assert_common_success_contracts() {
  local output="$1"
  local launch="$2"

  assert_contains "$output" "DRY RUN"
  assert_contains "$output" "wrapper_version=${WRAPPER_VERSION}"
  assert_contains "$output" "publish=127.0.0.1:4096:4096"
  assert_contains "$output" "hostname=0.0.0.0"
  assert_contains "$output" "command=opencode web --hostname 0.0.0.0 --port 4096"
  assert_contains "$output" "env.OPENCODE_SERVER_USERNAME=opencode"
  assert_contains "$output" "runtime_env_home=/home/opencode"
  assert_contains "$output" "runtime_env_xdg_config_home=/home/opencode/.config"
  assert_contains "$output" "runtime_env_xdg_data_home=/home/opencode/.local/share"
  assert_contains "$output" "runtime_env_xdg_state_home=/home/opencode/.local/share/opencode/state"
  assert_contains "$output" "docker_command:"
  assert_contains "$output" "-p 127.0.0.1:4096:4096"
  assert_contains "$output" "-e HOME=/home/opencode"
  assert_contains "$output" "-e XDG_CONFIG_HOME=/home/opencode/.config"
  assert_contains "$output" "-e XDG_DATA_HOME=/home/opencode/.local/share"
  assert_contains "$output" "-e XDG_STATE_HOME=/home/opencode/.local/share/opencode/state"
  assert_contains "$output" "--model local"

  if [ "$launch" = "foreground" ]; then
    assert_contains "$output" "run_detached=0"
  else
    assert_contains "$output" "run_detached=1"
    assert_contains "$output" "-d"
  fi
}

assert_sensitive_mount_contracts() {
  local output="$1"
  local sensitive="$2"

  case "$sensitive" in
    none)
      assert_not_contains "$output" "WARNING: Mounting host GitHub CLI auth/config into the container"
      assert_not_contains "$output" "WARNING: Mounting host SSH keys into container as read-only"
      assert_not_contains "$output" ".config/gh:ro"
      assert_not_contains "$output" ".ssh:ro"
      assert_not_contains "$output" "-e GIT_CONFIG_GLOBAL=/home/opencode/.gitconfig"
      ;;
    gh)
      assert_contains "$output" "WARNING: Mounting host GitHub CLI auth/config into the container"
      assert_not_contains "$output" "WARNING: Mounting host SSH keys into container as read-only"
      assert_contains "$output" ".config/gh:ro"
      assert_not_contains "$output" ".ssh:ro"
      assert_not_contains "$output" "-e GIT_CONFIG_GLOBAL=/home/opencode/.gitconfig"
      ;;
    ssh)
      assert_not_contains "$output" "WARNING: Mounting host GitHub CLI auth/config into the container"
      assert_contains "$output" "WARNING: Mounting host SSH keys into container as read-only"
      assert_not_contains "$output" ".config/gh:ro"
      assert_contains "$output" ".ssh:ro"
      assert_contains "$output" ".gitconfig:/home/opencode/.gitconfig:ro"
      assert_contains "$output" "-e GIT_CONFIG_GLOBAL=/home/opencode/.gitconfig"
      ;;
    both)
      assert_contains "$output" "WARNING: Mounting host GitHub CLI auth/config into the container"
      assert_contains "$output" "WARNING: Mounting host SSH keys into container as read-only"
      assert_contains "$output" ".config/gh:ro"
      assert_contains "$output" ".ssh:ro"
      assert_contains "$output" ".gitconfig:/home/opencode/.gitconfig:ro"
      assert_contains "$output" "-e GIT_CONFIG_GLOBAL=/home/opencode/.gitconfig"
      ;;
    *)
      fail "unknown sensitive mode: ${sensitive}"
      ;;
  esac
}

assert_agent_contracts() {
  local output="$1"
  local mode="$2"

  assert_contains "$output" "host_agents_source=${CASE_EXPECTED_AGENT_SOURCE}"
  assert_contains "$output" "host_agents_path=${CASE_EXPECTED_AGENT_PATH}"
  assert_contains "$output" "host_agents_disabled=${CASE_EXPECTED_AGENT_DISABLED}"

  if [ "$CASE_EXPECTED_AGENT_SELECTED" -eq 1 ]; then
    if [ "$mode" = "rehearse" ]; then
      assert_contains "$output" "host_agents_delivery=scratch-copy"
      assert_contains "$output" "${CASE_EXPECTED_AGENT_LOG} (copied into rehearsal scratch config at "
      assert_not_contains "$output" "-v ${CASE_EXPECTED_AGENT_PATH}:/home/opencode/.config/opencode/AGENTS.md:ro"
    else
      assert_contains "$output" "${CASE_EXPECTED_AGENT_LOG}"
      assert_contains "$output" "-v ${CASE_EXPECTED_AGENT_PATH}:/home/opencode/.config/opencode/AGENTS.md:ro"
    fi
    return 0
  fi

  if [ "$CASE_EXPECTED_AGENT_DISABLED" -eq 1 ]; then
    assert_contains "$output" "Host instruction file mount disabled by --no-host-agents."
    if [ "$mode" = "rehearse" ]; then
      assert_contains "$output" "host_agents_delivery=disabled"
    fi
  else
    assert_not_contains "$output" "Using host instruction file from "
    if [ "$mode" = "rehearse" ]; then
      assert_contains "$output" "host_agents_delivery=none"
    fi
  fi

  assert_not_contains "$output" "/home/opencode/.config/opencode/AGENTS.md:ro"
}

assert_run_mode_contracts() {
  local output="$1"

  assert_contains "$output" "container_name=opencode_web_yolo"
  assert_contains "$output" "restart_policy=unless-stopped"
  assert_contains "$output" "opencode_config_dir=${OPENCODE_WEB_CONFIG_DIR}"
  assert_contains "$output" "opencode_data_dir=${OPENCODE_WEB_DATA_DIR}"
  assert_contains "$output" "-v ${OPENCODE_WEB_CONFIG_DIR}:/home/opencode/.config/opencode"
  assert_contains "$output" "-v ${OPENCODE_WEB_DATA_DIR}:/home/opencode/.local/share/opencode"
  assert_not_contains "$output" "rehearsal_mode=1"

  [ -d "${OPENCODE_WEB_CONFIG_DIR}" ] || fail "expected runtime mode to create host config dir"
  [ -d "${OPENCODE_WEB_DATA_DIR}" ] || fail "expected runtime mode to create host data dir"
}

assert_rehearsal_mode_contracts() {
  local output="$1"
  local mount_config_dir
  local mount_data_dir

  assert_contains "$output" "container_name=opencode_web_yolo-rehearsal-"
  assert_contains "$output" "restart_policy=none"
  assert_contains "$output" "rehearsal_mode=1"
  assert_contains "$output" "rehearsal_source_config_dir=${OPENCODE_WEB_CONFIG_DIR}"
  assert_contains "$output" "rehearsal_source_data_dir=${OPENCODE_WEB_DATA_DIR}"
  assert_contains "$output" "rehearsal_cleanup=wrapper-exit"

  mount_config_dir="$(extract_output_value "$output" "rehearsal_mount_config_dir")"
  mount_data_dir="$(extract_output_value "$output" "rehearsal_mount_data_dir")"
  assert_nonempty "$mount_config_dir" "rehearsal_mount_config_dir"
  assert_nonempty "$mount_data_dir" "rehearsal_mount_data_dir"

  [ "$mount_config_dir" != "${OPENCODE_WEB_CONFIG_DIR}" ] || fail "expected rehearsal config mount to differ from host config dir"
  [ "$mount_data_dir" != "${OPENCODE_WEB_DATA_DIR}" ] || fail "expected rehearsal data mount to differ from host data dir"

  assert_contains "$output" "-v ${mount_config_dir}:/home/opencode/.config/opencode"
  assert_contains "$output" "-v ${mount_data_dir}:/home/opencode/.local/share/opencode"
  assert_not_contains "$output" "-v ${OPENCODE_WEB_CONFIG_DIR}:/home/opencode/.config/opencode"
  assert_not_contains "$output" "-v ${OPENCODE_WEB_DATA_DIR}:/home/opencode/.local/share/opencode"

  if [ "$CASE_EXPECTED_AGENT_SELECTED" -eq 1 ]; then
    assert_contains "$output" "rehearsal_host_agents_path=${mount_config_dir}/AGENTS.md"
  else
    assert_not_contains "$output" "rehearsal_host_agents_path="
  fi

  assert_path_absent "${OPENCODE_WEB_CONFIG_DIR}"
  assert_path_absent "${OPENCODE_WEB_DATA_DIR}"
}

run_success_case() {
  local case_id="$1"
  local mode="$2"
  local launch="$3"
  local sensitive="$4"
  local agent_profile="$5"
  local case_root="$6"
  local label="$7"
  local -a cmd
  local output

  set_test_case_context "$label"
  prepare_case_environment "$case_root"
  configure_agent_profile "$case_root" "$agent_profile"
  export OPENCODE_SERVER_PASSWORD="secret"

  cmd=("${ROOT_DIR}/.opencode_web_yolo.sh")
  if [ "$mode" = "rehearse" ]; then
    cmd+=(rehearse-migrations)
  fi
  if [ "$launch" = "foreground" ]; then
    cmd+=(--foreground)
  fi
  cmd+=("${CASE_AGENT_ARGS[@]}")
  case "$sensitive" in
    gh)
      cmd+=(-gh)
      ;;
    ssh)
      cmd+=(--mount-ssh)
      ;;
    both)
      cmd+=(-gh --mount-ssh)
      ;;
  esac
  cmd+=(--dry-run -- --model local)

  output="$("${cmd[@]}" 2>&1)"

  assert_common_success_contracts "$output" "$launch"
  assert_sensitive_mount_contracts "$output" "$sensitive"
  assert_agent_contracts "$output" "$mode"

  if [ "$mode" = "rehearse" ]; then
    assert_rehearsal_mode_contracts "$output"
  else
    assert_run_mode_contracts "$output"
  fi

  clear_test_case_context
}

run_missing_password_case() {
  local case_id="$1"
  local mode="$2"
  local case_root="$3"
  local label="$4"
  local -a cmd
  local output
  local status

  set_test_case_context "$label"
  prepare_case_environment "$case_root"
  unset OPENCODE_SERVER_PASSWORD || true

  cmd=("${ROOT_DIR}/.opencode_web_yolo.sh")
  if [ "$mode" = "rehearse" ]; then
    cmd+=(rehearse-migrations)
  fi
  cmd+=(--dry-run)

  set +e
  output="$("${cmd[@]}" 2>&1)"
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    fail "expected missing password case to fail"
  fi
  assert_contains "$output" "OPENCODE_SERVER_PASSWORD must be set and non-empty"
  assert_contains "$output" "Authentication is mandatory for all access, including localhost."

  clear_test_case_context
}

run_gh_auth_failure_case() {
  local case_root="$1"
  local label="$2"
  local output
  local status

  set_test_case_context "$label"
  prepare_case_environment "$case_root"
  export OPENCODE_SERVER_PASSWORD="secret"
  export GH_AUTH_FAIL=1

  set +e
  output="$("${ROOT_DIR}/.opencode_web_yolo.sh" -gh --dry-run 2>&1)"
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    fail "expected -gh auth validation failure"
  fi
  assert_contains "$output" "requires authenticated GitHub CLI on host"

  clear_test_case_context
}

success_cases=0
case_id=0
for mode in run rehearse; do
  mode_offset=0
  if [ "$mode" = "rehearse" ]; then
    mode_offset=11
  fi

  for agent_profile in "${AGENT_PROFILES[@]}"; do
    case_id=$((case_id + 1))
    launch_index="$(seeded_cycle_index "$FUZZ_SEED" "$((case_id + mode_offset))" "${#LAUNCH_MODES[@]}")"
    sensitive_index="$(seeded_cycle_index "$FUZZ_SEED" "$((case_id * 3 + mode_offset))" "${#SENSITIVE_MODES[@]}")"
    launch="${LAUNCH_MODES[$launch_index]}"
    sensitive="${SENSITIVE_MODES[$sensitive_index]}"
    label="$(format_seeded_case_label "$FUZZ_SEED" "$case_id" "${mode}/${agent_profile}/${launch}/${sensitive}")"

    run_success_case \
      "$case_id" \
      "$mode" \
      "$launch" \
      "$sensitive" \
      "$agent_profile" \
      "${TMP_DIR}/case-${case_id}" \
      "$label"
    success_cases=$((success_cases + 1))
  done
done

negative_cases=0
case_id=$((case_id + 1))
run_missing_password_case "$case_id" "run" "${TMP_DIR}/case-${case_id}" "$(format_seeded_case_label "$FUZZ_SEED" "$case_id" "run/password-missing")"
negative_cases=$((negative_cases + 1))

case_id=$((case_id + 1))
run_missing_password_case "$case_id" "rehearse" "${TMP_DIR}/case-${case_id}" "$(format_seeded_case_label "$FUZZ_SEED" "$case_id" "rehearse/password-missing")"
negative_cases=$((negative_cases + 1))

case_id=$((case_id + 1))
run_gh_auth_failure_case "${TMP_DIR}/case-${case_id}" "$(format_seeded_case_label "$FUZZ_SEED" "$case_id" "run/gh-auth-failure")"
negative_cases=$((negative_cases + 1))

printf '%s\n' "PASS: integration contract fuzzer (seed=${FUZZ_SEED}, success_cases=${success_cases}, negative_cases=${negative_cases})"
