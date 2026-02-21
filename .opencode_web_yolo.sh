#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]}"
while [ -h "$SOURCE_PATH" ]; do
  SOURCE_DIR="$(cd -P "$(dirname "$SOURCE_PATH")" && pwd)"
  SOURCE_PATH="$(readlink "$SOURCE_PATH")"
  case "$SOURCE_PATH" in
    /*) ;;
    *) SOURCE_PATH="${SOURCE_DIR}/${SOURCE_PATH}" ;;
  esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE_PATH")" && pwd)"
# shellcheck source=.opencode_web_yolo_config.sh
. "${SCRIPT_DIR}/.opencode_web_yolo_config.sh"

ORIGINAL_ARGS=("$@")
WRAPPER_VERSION_FILE="${SCRIPT_DIR}/VERSION"
WRAPPER_VERSION="0.0.0"
if [ -f "$WRAPPER_VERSION_FILE" ]; then
  WRAPPER_VERSION="$(tr -d '[:space:]' <"$WRAPPER_VERSION_FILE")"
fi

VERBOSE="${OPENCODE_WEB_VERBOSE}"

is_true() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

log() {
  printf '%s\n' "[opencode_web_yolo] $*"
}

warn() {
  printf '%s\n' "[opencode_web_yolo] WARNING: $*" >&2
}

die() {
  printf '%s\n' "[opencode_web_yolo] ERROR: $*" >&2
  exit 1
}

debug() {
  if is_true "$VERBOSE"; then
    printf '%s\n' "[opencode_web_yolo] DEBUG: $*" >&2
  fi
}

require_command() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Required command '$cmd' was not found in PATH."
}

version_gt() {
  local left="$1"
  local right="$2"
  [ "$left" != "$right" ] && [ "$(printf '%s\n%s\n' "$left" "$right" | sort -V | tail -n 1)" = "$left" ]
}

expand_tilde() {
  local path="$1"
  if [ "$path" = "~" ]; then
    printf '%s\n' "$HOME"
    return 0
  fi

  if [ "${path#\~/}" != "$path" ]; then
    printf '%s\n' "${HOME}/${path#\~/}"
    return 0
  fi

  printf '%s\n' "$path"
}

resolve_repo_from_origin() {
  local origin url
  if ! command -v git >/dev/null 2>&1; then
    return 0
  fi

  if ! origin="$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null)"; then
    return 0
  fi

  url="${origin%.git}"
  case "$url" in
    git@github.com:*)
      printf '%s\n' "${url#git@github.com:}"
      ;;
    https://github.com/*)
      printf '%s\n' "${url#https://github.com/}"
      ;;
    http://github.com/*)
      printf '%s\n' "${url#http://github.com/}"
      ;;
    *)
      ;;
  esac
}

managed_files() {
  cat <<'EOF'
.opencode_web_yolo.sh
.opencode_web_yolo_config.sh
.opencode_web_yolo.Dockerfile
.opencode_web_yolo_entrypoint.sh
.opencode_web_yolo_completion.bash
.opencode_web_yolo_completion.zsh
install.sh
VERSION
CHANGELOG.md
README.md
TECHNICAL.md
EOF
}

apply_self_update() {
  local install_home repo branch local_version remote_version remote_base tmpdir managed_file src_file dst_file

  if is_true "${OPENCODE_WEB_SKIP_UPDATE_CHECK}"; then
    debug "Skipping update check because OPENCODE_WEB_SKIP_UPDATE_CHECK is enabled."
    return 0
  fi

  install_home="${OPENCODE_WEB_INSTALL_HOME:-${HOME}/.opencode_web_yolo}"
  if [ "$SCRIPT_DIR" != "$install_home" ]; then
    debug "Skipping update check because wrapper is not running from managed install home (${install_home})."
    return 0
  fi

  repo="${OPENCODE_WEB_YOLO_REPO:-}"
  if [ -z "$repo" ]; then
    repo="$(resolve_repo_from_origin || true)"
  fi
  branch="${OPENCODE_WEB_YOLO_BRANCH}"

  if [ -z "$repo" ]; then
    debug "Skipping update check because OPENCODE_WEB_YOLO_REPO is not set and origin could not be resolved."
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    warn "Skipping update check because curl is not available."
    return 0
  fi

  local_version="$WRAPPER_VERSION"
  remote_base="https://raw.githubusercontent.com/${repo}/${branch}"
  if ! remote_version="$(curl -fsSL "${remote_base}/VERSION" | tr -d '[:space:]')"; then
    warn "Update check failed while reading remote VERSION from ${repo}@${branch}. Continuing with local files."
    return 0
  fi

  if ! version_gt "$remote_version" "$local_version"; then
    debug "Local version (${local_version}) is up to date."
    return 0
  fi

  log "Updating wrapper from ${local_version} to ${remote_version}."
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  while IFS= read -r managed_file; do
    src_file="${remote_base}/${managed_file}"
    dst_file="${tmpdir}/${managed_file}"
    mkdir -p "$(dirname "$dst_file")"
    if ! curl -fsSL "$src_file" -o "$dst_file"; then
      die "Failed downloading '${managed_file}' during self-update."
    fi
  done < <(managed_files)

  while IFS= read -r managed_file; do
    dst_file="${install_home}/${managed_file}"
    mkdir -p "$(dirname "$dst_file")"
    cp "${tmpdir}/${managed_file}" "$dst_file"
  done < <(managed_files)

  chmod +x "${install_home}/.opencode_web_yolo.sh"
  chmod +x "${install_home}/.opencode_web_yolo_entrypoint.sh"
  chmod +x "${install_home}/install.sh"

  rm -rf "$tmpdir"
  trap - EXIT

  log "Update complete, re-executing wrapper."
  exec "${install_home}/.opencode_web_yolo.sh" "${ORIGINAL_ARGS[@]}"
}

print_version() {
  printf '%s\n' "opencode_web_yolo ${WRAPPER_VERSION}"
}

print_help() {
  cat <<EOF
opencode_web_yolo ${WRAPPER_VERSION}

Usage:
  opencode_web_yolo [wrapper_flags] [-- opencode_web_args...]

Wrapper flags:
  --pull                 Force docker rebuild/pull behavior.
  --no-pull              Skip default pull-on-start behavior for this run.
  --agents-file PATH     Mount a host AGENTS.md file read-only.
  --no-host-agents       Skip mounting host AGENTS.md.
  --dry-run              Print docker command and exit.
  --detach, -d           Force background mode.
  --foreground, -f       Run attached in current terminal.
  --mount-ssh            Mount host ~/.ssh as read-only (explicit).
  -gh, --gh              Mount authenticated host gh config as read-only.
  health, --health       Show diagnostics (no server start).
  diagnostics            Alias for health.
  config                 Generate sample config file at:
                         ${OPENCODE_WEB_CONFIG_FILE}
  --version, version     Print wrapper version.
  --verbose, -v          Enable verbose wrapper logs.
  --help, -h, help       Show this help.

Required auth:
  OPENCODE_SERVER_PASSWORD must be set and non-empty on all runs.
  Optional: OPENCODE_SERVER_USERNAME (default: opencode)

Lifecycle defaults:
  Container name: ${OPENCODE_WEB_CONTAINER_NAME}
  Restart policy: ${OPENCODE_WEB_RESTART_POLICY}
  Background mode: ${OPENCODE_WEB_RUN_DETACHED}
  Pull-on-start: ${OPENCODE_WEB_AUTO_PULL}

First-time setup:
  1) Create config file:
     opencode_web_yolo config
  2) Edit config and set:
     export OPENCODE_SERVER_PASSWORD='change-me-now'
  3) Start:
     opencode_web_yolo

Preview without launching:
  OPENCODE_WEB_DRY_RUN=1 opencode_web_yolo --verbose
  opencode_web_yolo --dry-run --verbose

Host instruction file selection:
  --agents-file PATH            Explicit host instruction file override (read-only).
  OPENCODE_HOST_AGENTS=PATH     Host instruction file override when --agents-file is absent.
  Default host lookup order:
    1) ~/.config/opencode/AGENTS.md
    2) ~/.codex/AGENTS.md
    3) ~/.copilot/copilot-instructions.md
    4) ~/.claude/CLAUDE.md
  Selected file mounts to ${OPENCODE_WEB_YOLO_HOME}/.config/opencode/AGENTS.md.
  --no-host-agents              Disable host instruction file mount.
EOF
}

write_default_config() {
  local config_file config_dir
  config_file="${OPENCODE_WEB_CONFIG_FILE}"
  config_dir="$(dirname "$config_file")"
  mkdir -p "$config_dir"
  if [ -e "$config_file" ]; then
    die "Config file already exists at ${config_file}. Refusing to overwrite."
  fi

  cat >"$config_file" <<'EOF'
# opencode_web_yolo user config
export OPENCODE_WEB_PORT=4096
export OPENCODE_WEB_HOSTNAME=0.0.0.0
export OPENCODE_WEB_YOLO_IMAGE=opencode_web_yolo:latest
export OPENCODE_WEB_BASE_IMAGE=node:22-slim
export OPENCODE_WEB_NPM_PACKAGE=opencode-ai
export OPENCODE_WEB_CONTAINER_NAME=opencode_web_yolo
export OPENCODE_WEB_RESTART_POLICY=unless-stopped
export OPENCODE_WEB_RUN_DETACHED=1
export OPENCODE_WEB_AUTO_PULL=1
export OPENCODE_WEB_SKIP_UPDATE_CHECK=0
export OPENCODE_WEB_SKIP_VERSION_CHECK=0
# Required: set a non-empty password before running the server.
# export OPENCODE_SERVER_PASSWORD=change-me-now
# Optional:
# export OPENCODE_SERVER_USERNAME=opencode
# export OPENCODE_WEB_CONFIG_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/opencode
# export OPENCODE_WEB_DATA_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/opencode
# export OPENCODE_WEB_YOLO_REPO=owner/repo
# export OPENCODE_WEB_YOLO_BRANCH=main
EOF
  log "Wrote ${config_file}."
}

show_health() {
  local status=0
  local image_wrapper_version image_opencode_version
  local runtime_home runtime_xdg_config runtime_xdg_data runtime_xdg_state
  local container_home_env container_xdg_config_env container_xdg_data_env container_xdg_state_env

  runtime_home="${OPENCODE_WEB_YOLO_HOME}"
  runtime_xdg_config="${OPENCODE_WEB_YOLO_HOME}/.config"
  runtime_xdg_data="${OPENCODE_WEB_YOLO_HOME}/.local/share"
  runtime_xdg_state="${OPENCODE_WEB_YOLO_HOME}/.local/share/opencode/state"

  printf '%s\n' "opencode_web_yolo health report"
  printf '%s\n' "  wrapper_version=${WRAPPER_VERSION}"
  printf '%s\n' "  image=${OPENCODE_WEB_YOLO_IMAGE}"
  printf '%s\n' "  port_binding=127.0.0.1:${OPENCODE_WEB_PORT}:${OPENCODE_WEB_PORT}"
  printf '%s\n' "  hostname=${OPENCODE_WEB_HOSTNAME}"
  printf '%s\n' "  config_file=${OPENCODE_WEB_CONFIG_FILE}"
  printf '%s\n' "  opencode_config_dir=${OPENCODE_WEB_CONFIG_DIR}"
  printf '%s\n' "  opencode_data_dir=${OPENCODE_WEB_DATA_DIR}"
  printf '%s\n' "  container_name=${OPENCODE_WEB_CONTAINER_NAME}"
  printf '%s\n' "  restart_policy=${OPENCODE_WEB_RESTART_POLICY}"
  printf '%s\n' "  run_detached=${OPENCODE_WEB_RUN_DETACHED}"
  printf '%s\n' "  auto_pull=${OPENCODE_WEB_AUTO_PULL}"
  printf '%s\n' "  build_pull=${OPENCODE_WEB_BUILD_PULL}"
  printf '%s\n' "  runtime_env_home=${runtime_home}"
  printf '%s\n' "  runtime_env_xdg_config_home=${runtime_xdg_config}"
  printf '%s\n' "  runtime_env_xdg_data_home=${runtime_xdg_data}"
  printf '%s\n' "  runtime_env_xdg_state_home=${runtime_xdg_state}"
  printf '%s\n' "  workspace_ui_state_scope=browser-local-storage"

  if command -v docker >/dev/null 2>&1; then
    printf '%s\n' "  docker_cli=ok"
    if docker info >/dev/null 2>&1; then
      printf '%s\n' "  docker_daemon=ok"
    else
      printf '%s\n' "  docker_daemon=unavailable"
      status=1
    fi
  else
    printf '%s\n' "  docker_cli=missing"
    status=1
  fi

  if docker image inspect "${OPENCODE_WEB_YOLO_IMAGE}" >/dev/null 2>&1; then
    printf '%s\n' "  image_present=yes"
    image_wrapper_version="$(docker run --rm --entrypoint cat "${OPENCODE_WEB_YOLO_IMAGE}" /opt/opencode-web-yolo-version 2>/dev/null || true)"
    image_opencode_version="$(docker run --rm --entrypoint cat "${OPENCODE_WEB_YOLO_IMAGE}" /opt/opencode-version 2>/dev/null || true)"
    printf '%s\n' "  image_wrapper_version=${image_wrapper_version:-unknown}"
    printf '%s\n' "  image_opencode_version=${image_opencode_version:-unknown}"
  else
    printf '%s\n' "  image_present=no"
  fi

  if command -v docker >/dev/null 2>&1; then
    if [ -n "$(docker ps -a --filter "name=^/${OPENCODE_WEB_CONTAINER_NAME}$" --format '{{.Names}}' 2>/dev/null || true)" ]; then
      printf '%s\n' "  container_present=yes"
      if [ -n "$(docker ps --filter "name=^/${OPENCODE_WEB_CONTAINER_NAME}$" --filter "status=running" --format '{{.Names}}' 2>/dev/null || true)" ]; then
        printf '%s\n' "  container_running=yes"
      else
        printf '%s\n' "  container_running=no"
      fi

      container_home_env="$(docker inspect "${OPENCODE_WEB_CONTAINER_NAME}" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -E '^HOME=' | tail -n 1 || true)"
      container_xdg_config_env="$(docker inspect "${OPENCODE_WEB_CONTAINER_NAME}" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -E '^XDG_CONFIG_HOME=' | tail -n 1 || true)"
      container_xdg_data_env="$(docker inspect "${OPENCODE_WEB_CONTAINER_NAME}" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -E '^XDG_DATA_HOME=' | tail -n 1 || true)"
      container_xdg_state_env="$(docker inspect "${OPENCODE_WEB_CONTAINER_NAME}" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -E '^XDG_STATE_HOME=' | tail -n 1 || true)"
      printf '%s\n' "  container_env_home=${container_home_env:-missing}"
      printf '%s\n' "  container_env_xdg_config_home=${container_xdg_config_env:-missing}"
      printf '%s\n' "  container_env_xdg_data_home=${container_xdg_data_env:-missing}"
      printf '%s\n' "  container_env_xdg_state_home=${container_xdg_state_env:-missing}"
    else
      printf '%s\n' "  container_present=no"
      printf '%s\n' "  container_env_home=missing"
      printf '%s\n' "  container_env_xdg_config_home=missing"
      printf '%s\n' "  container_env_xdg_data_home=missing"
      printf '%s\n' "  container_env_xdg_state_home=missing"
    fi
  fi

  if command -v gh >/dev/null 2>&1; then
    printf '%s\n' "  gh_cli=ok"
    if gh auth status >/dev/null 2>&1; then
      printf '%s\n' "  gh_auth=ok"
    else
      printf '%s\n' "  gh_auth=not-authenticated"
    fi
  else
    printf '%s\n' "  gh_cli=missing"
  fi

  return "$status"
}

resolve_expected_opencode_version() {
  if is_true "${OPENCODE_WEB_SKIP_VERSION_CHECK}"; then
    debug "Skipping OpenCode npm version check."
    return 0
  fi

  if [ -n "${OPENCODE_WEB_EXPECTED_OPENCODE_VERSION:-}" ]; then
    printf '%s\n' "${OPENCODE_WEB_EXPECTED_OPENCODE_VERSION}"
    return 0
  fi

  if ! command -v npm >/dev/null 2>&1; then
    warn "npm is not available; cannot evaluate OpenCode version drift."
    return 0
  fi

  npm view "${OPENCODE_WEB_NPM_PACKAGE}" version --json 2>/dev/null | tr -d '"' | tr -d '[:space:]'
}

build_image() {
  local build_opencode_version
  local -a build_cmd

  build_opencode_version="latest"
  if [ -n "${OPENCODE_WEB_EXPECTED_OPENCODE_VERSION:-}" ]; then
    build_opencode_version="${OPENCODE_WEB_EXPECTED_OPENCODE_VERSION}"
  fi

  build_cmd=(docker build -f "${SCRIPT_DIR}/.opencode_web_yolo.Dockerfile")
  if is_true "${OPENCODE_WEB_BUILD_PULL}"; then
    build_cmd+=(--pull)
  fi
  if is_true "${OPENCODE_WEB_BUILD_NO_CACHE}"; then
    build_cmd+=(--no-cache)
  fi

  build_cmd+=(
    --build-arg "BASE_IMAGE=${OPENCODE_WEB_BASE_IMAGE}"
    --build-arg "WRAPPER_VERSION=${WRAPPER_VERSION}"
    --build-arg "OPENCODE_NPM_PACKAGE=${OPENCODE_WEB_NPM_PACKAGE}"
    --build-arg "OPENCODE_VERSION=${build_opencode_version}"
    -t "${OPENCODE_WEB_YOLO_IMAGE}"
    "${SCRIPT_DIR}"
  )

  log "Building runtime image ${OPENCODE_WEB_YOLO_IMAGE} (opencode=${build_opencode_version})."
  "${build_cmd[@]}"
}

ensure_image() {
  local expected_opencode_version image_wrapper_version image_opencode_version
  local -a reasons

  reasons=()
  expected_opencode_version="$(resolve_expected_opencode_version || true)"

  if ! docker image inspect "${OPENCODE_WEB_YOLO_IMAGE}" >/dev/null 2>&1; then
    reasons+=("image '${OPENCODE_WEB_YOLO_IMAGE}' is missing")
  fi

  if is_true "${OPENCODE_WEB_BUILD_PULL}"; then
    reasons+=("pull rebuild requested")
  fi

  if is_true "${OPENCODE_WEB_BUILD_NO_CACHE}"; then
    reasons+=("no-cache rebuild requested")
  fi

  if docker image inspect "${OPENCODE_WEB_YOLO_IMAGE}" >/dev/null 2>&1; then
    image_wrapper_version="$(docker run --rm --entrypoint cat "${OPENCODE_WEB_YOLO_IMAGE}" /opt/opencode-web-yolo-version 2>/dev/null || true)"
    if [ -z "$image_wrapper_version" ] || [ "$image_wrapper_version" != "$WRAPPER_VERSION" ]; then
      reasons+=("wrapper version metadata mismatch (image='${image_wrapper_version:-missing}', local='${WRAPPER_VERSION}')")
    fi

    image_opencode_version="$(docker run --rm --entrypoint cat "${OPENCODE_WEB_YOLO_IMAGE}" /opt/opencode-version 2>/dev/null || true)"
    if [ -n "$expected_opencode_version" ] && [ "$image_opencode_version" != "$expected_opencode_version" ]; then
      reasons+=("OpenCode version mismatch (image='${image_opencode_version:-missing}', expected='${expected_opencode_version}')")
    fi
  fi

  if [ "${#reasons[@]}" -eq 0 ]; then
    debug "Image checks passed; reusing ${OPENCODE_WEB_YOLO_IMAGE}."
    return 0
  fi

  log "Rebuild required:"
  for reason in "${reasons[@]}"; do
    log "  - ${reason}"
  done
  build_image
}

require_password() {
  local config_file_exists
  if [ -z "${OPENCODE_SERVER_PASSWORD:-}" ]; then
    config_file_exists="no"
    if [ -f "${OPENCODE_WEB_CONFIG_FILE}" ]; then
      config_file_exists="yes"
    fi

    cat >&2 <<EOF
[opencode_web_yolo] ERROR: OPENCODE_SERVER_PASSWORD must be set and non-empty.
[opencode_web_yolo] Authentication is mandatory for all access, including localhost.

Initial setup:
  1) Create a config file template:
     opencode_web_yolo config
  2) Edit:
     ${OPENCODE_WEB_CONFIG_FILE}
  3) Add:
     export OPENCODE_SERVER_PASSWORD='change-me-now'
  4) Run:
     opencode_web_yolo

Current config file present: ${config_file_exists}
Tip: You can also set it just for this shell:
  export OPENCODE_SERVER_PASSWORD='change-me-now'
EOF
    exit 1
  fi
}

prepare_runtime_container() {
  local existing_name running_name
  existing_name="$(docker ps -a --filter "name=^/${OPENCODE_WEB_CONTAINER_NAME}$" --format '{{.Names}}' 2>/dev/null || true)"
  if [ -z "$existing_name" ]; then
    return 0
  fi

  running_name="$(docker ps --filter "name=^/${OPENCODE_WEB_CONTAINER_NAME}$" --filter "status=running" --format '{{.Names}}' 2>/dev/null || true)"
  if is_true "${OPENCODE_WEB_DRY_RUN}"; then
    if [ -n "$running_name" ]; then
      debug "Dry run: would stop and remove existing running container '${OPENCODE_WEB_CONTAINER_NAME}' before launch."
    else
      debug "Dry run: would remove existing stopped container '${OPENCODE_WEB_CONTAINER_NAME}' before launch."
    fi
    return 0
  fi

  if [ -n "$running_name" ]; then
    log "Stopping existing running container '${OPENCODE_WEB_CONTAINER_NAME}' before launch."
    docker stop "${OPENCODE_WEB_CONTAINER_NAME}" >/dev/null 2>&1 || die "Failed to stop existing container '${OPENCODE_WEB_CONTAINER_NAME}'."
  fi

  log "Removing existing container '${OPENCODE_WEB_CONTAINER_NAME}' before launch."
  docker rm "${OPENCODE_WEB_CONTAINER_NAME}" >/dev/null 2>&1 || die "Failed to remove existing container '${OPENCODE_WEB_CONTAINER_NAME}'."
}

main() {
  local mode use_gh mount_ssh
  local host_agents_enabled host_agents_source host_agents_path
  local host_agents_container_path host_agents_opencode_path
  local host_agents_codex_path host_agents_copilot_path host_agents_claude_path
  local host_agents_log host_agents_disabled
  local gh_host_config_dir
  local runtime_home runtime_xdg_config runtime_xdg_data runtime_xdg_state
  local -a passthrough docker_args app_cmd docker_cmd

  mode="run"
  use_gh=0
  mount_ssh=0
  passthrough=()
  host_agents_enabled=1
  host_agents_source=""
  host_agents_path=""
  host_agents_container_path="${OPENCODE_WEB_YOLO_HOME}/.config/opencode/AGENTS.md"
  host_agents_opencode_path="$(expand_tilde "${HOME}/.config/opencode/AGENTS.md")"
  host_agents_codex_path="$(expand_tilde "${HOME}/.codex/AGENTS.md")"
  host_agents_copilot_path="$(expand_tilde "${HOME}/.copilot/copilot-instructions.md")"
  host_agents_claude_path="$(expand_tilde "${HOME}/.claude/CLAUDE.md")"
  host_agents_log=""
  host_agents_disabled=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --)
        shift
        passthrough+=("$@")
        break
        ;;
      --pull)
        OPENCODE_WEB_BUILD_PULL=1
        ;;
      --no-pull)
        OPENCODE_WEB_AUTO_PULL=0
        OPENCODE_WEB_BUILD_PULL=0
        ;;
      --agents-file=*)
        host_agents_enabled=1
        host_agents_source="flag"
        host_agents_path="${1#*=}"
        ;;
      --agents-file)
        shift
        [ "$#" -gt 0 ] || die "--agents-file requires a host path."
        host_agents_enabled=1
        host_agents_source="flag"
        host_agents_path="$1"
        ;;
      --no-host-agents)
        host_agents_enabled=0
        host_agents_source="disabled"
        host_agents_path=""
        host_agents_disabled=1
        ;;
      --dry-run)
        OPENCODE_WEB_DRY_RUN=1
        ;;
      --detach|-d)
        OPENCODE_WEB_RUN_DETACHED=1
        ;;
      --foreground|-f)
        OPENCODE_WEB_RUN_DETACHED=0
        ;;
      --mount-ssh)
        mount_ssh=1
        ;;
      -gh|--gh)
        use_gh=1
        ;;
      health|--health|diagnostics)
        mode="health"
        ;;
      config)
        mode="config"
        ;;
      --help|-h|help)
        mode="help"
        ;;
      --version|version)
        mode="version"
        ;;
      --verbose|-v)
        OPENCODE_WEB_VERBOSE=1
        VERBOSE=1
        ;;
      *)
        passthrough+=("$1")
        ;;
    esac
    shift
  done

  case "$mode" in
    version)
      print_version
      return 0
      ;;
    config)
      write_default_config
      return 0
      ;;
    help)
      print_help
      return 0
      ;;
    health)
      show_health
      return $?
      ;;
  esac

  apply_self_update

  if is_true "${OPENCODE_WEB_AUTO_PULL}"; then
    OPENCODE_WEB_BUILD_PULL=1
  fi

  require_password
  require_command docker
  docker info >/dev/null 2>&1 || die "Docker daemon is not available."
  [ -n "${OPENCODE_WEB_CONTAINER_NAME}" ] || die "OPENCODE_WEB_CONTAINER_NAME must be non-empty."
  [ -n "${OPENCODE_WEB_RESTART_POLICY}" ] || die "OPENCODE_WEB_RESTART_POLICY must be non-empty."

  runtime_home="${OPENCODE_WEB_YOLO_HOME}"
  runtime_xdg_config="${OPENCODE_WEB_YOLO_HOME}/.config"
  runtime_xdg_data="${OPENCODE_WEB_YOLO_HOME}/.local/share"
  runtime_xdg_state="${OPENCODE_WEB_YOLO_HOME}/.local/share/opencode/state"

  mkdir -p "${OPENCODE_WEB_CONFIG_DIR}" "${OPENCODE_WEB_DATA_DIR}"

  docker_args=(
    run
    --name "${OPENCODE_WEB_CONTAINER_NAME}"
    --restart "${OPENCODE_WEB_RESTART_POLICY}"
    -p "127.0.0.1:${OPENCODE_WEB_PORT}:${OPENCODE_WEB_PORT}"
    -w "${OPENCODE_WEB_YOLO_WORKDIR}"
    -e "LOCAL_UID=$(id -u)"
    -e "LOCAL_GID=$(id -g)"
    -e "LOCAL_USER=$(id -un)"
    -e "OPENCODE_WEB_YOLO_CLEANUP=${OPENCODE_WEB_YOLO_CLEANUP}"
    -e "OPENCODE_WEB_YOLO_HOME=${OPENCODE_WEB_YOLO_HOME}"
    -e "OPENCODE_SERVER_PASSWORD=${OPENCODE_SERVER_PASSWORD}"
    -e "OPENCODE_SERVER_USERNAME=${OPENCODE_SERVER_USERNAME}"
    -e "HOME=${runtime_home}"
    -e "XDG_CONFIG_HOME=${runtime_xdg_config}"
    -e "XDG_DATA_HOME=${runtime_xdg_data}"
    -e "XDG_STATE_HOME=${runtime_xdg_state}"
    -v "${PWD}:${OPENCODE_WEB_YOLO_WORKDIR}"
    -v "${OPENCODE_WEB_CONFIG_DIR}:${OPENCODE_WEB_YOLO_HOME}/.config/opencode"
    -v "${OPENCODE_WEB_DATA_DIR}:${OPENCODE_WEB_YOLO_HOME}/.local/share/opencode"
  )

  if is_true "${OPENCODE_WEB_RUN_DETACHED}"; then
    docker_args+=(-d)
  fi

  if [ "$use_gh" -eq 1 ]; then
    require_command gh
    if ! gh auth status >/dev/null 2>&1; then
      die "The '-gh' flag requires authenticated GitHub CLI on host. Run 'gh auth login' first."
    fi
    gh_host_config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/gh"
    [ -d "$gh_host_config_dir" ] || die "GitHub CLI config directory not found at ${gh_host_config_dir}."
    warn "Mounting host GitHub CLI auth/config into the container. Container processes can use your host GitHub credentials."
    docker_args+=(-v "${gh_host_config_dir}:${OPENCODE_WEB_YOLO_HOME}/.config/gh:ro")
  fi

  if [ "$mount_ssh" -eq 1 ]; then
    [ -d "${HOME}/.ssh" ] || die "--mount-ssh requested but ${HOME}/.ssh does not exist."
    warn "Mounting host SSH keys into container as read-only. Prefer least privilege keys and branch protection."
    docker_args+=(-v "${HOME}/.ssh:${OPENCODE_WEB_YOLO_HOME}/.ssh:ro")
    if [ -f "${HOME}/.gitconfig" ]; then
      docker_args+=(-v "${HOME}/.gitconfig:${OPENCODE_WEB_YOLO_HOME}/.gitconfig:ro")
      docker_args+=(-e "GIT_CONFIG_GLOBAL=${OPENCODE_WEB_YOLO_HOME}/.gitconfig")
    fi
  fi

  if [ "$host_agents_enabled" -eq 1 ]; then
    if [ -z "$host_agents_source" ]; then
      if [ -n "${OPENCODE_HOST_AGENTS:-}" ]; then
        host_agents_source="env"
        host_agents_path="${OPENCODE_HOST_AGENTS}"
      elif [ -f "$host_agents_opencode_path" ]; then
        host_agents_source="opencode"
        host_agents_path="${host_agents_opencode_path}"
      elif [ -f "$host_agents_codex_path" ]; then
        host_agents_source="codex"
        host_agents_path="${host_agents_codex_path}"
      elif [ -f "$host_agents_copilot_path" ]; then
        host_agents_source="copilot"
        host_agents_path="${host_agents_copilot_path}"
      elif [ -f "$host_agents_claude_path" ]; then
        host_agents_source="claude"
        host_agents_path="${host_agents_claude_path}"
      else
        host_agents_source="none"
      fi
    fi

    if [ "$host_agents_source" = "flag" ] && [ -z "$host_agents_path" ]; then
      die "--agents-file requires a non-empty host path."
    fi

    if [ "$host_agents_source" = "none" ]; then
      debug "No host instruction file found in default order; relying on project rules and OpenCode defaults."
    elif [ -n "$host_agents_path" ]; then
      host_agents_path="$(expand_tilde "$host_agents_path")"
      if [ -f "$host_agents_path" ]; then
        if [ ! -r "$host_agents_path" ]; then
          die "Host instruction file is not readable at ${host_agents_path}."
        fi
        host_agents_log="Using host instruction file from ${host_agents_source}: ${host_agents_path}"
        docker_args+=(-v "${host_agents_path}:${host_agents_container_path}:ro")
      else
        if [ "$host_agents_source" = "flag" ] || [ "$host_agents_source" = "env" ]; then
          die "Host instruction file not found at ${host_agents_path}."
        fi
        debug "Host instruction file disappeared before mount: ${host_agents_path}; continuing without host mount."
      fi
    fi
  else
    host_agents_log="Host instruction file mount disabled by --no-host-agents."
  fi

  app_cmd=(opencode web --hostname "${OPENCODE_WEB_HOSTNAME}" --port "${OPENCODE_WEB_PORT}")
  app_cmd+=("${passthrough[@]}")

  ensure_image
  prepare_runtime_container

  docker_cmd=(docker "${docker_args[@]}" "${OPENCODE_WEB_YOLO_IMAGE}" "${app_cmd[@]}")

  if is_true "${OPENCODE_WEB_DRY_RUN}"; then
    printf '%s\n' "DRY RUN"
    printf '%s\n' "wrapper_version=${WRAPPER_VERSION}"
    printf '%s\n' "publish=127.0.0.1:${OPENCODE_WEB_PORT}:${OPENCODE_WEB_PORT}"
    printf '%s\n' "hostname=${OPENCODE_WEB_HOSTNAME}"
    printf '%s\n' "container_name=${OPENCODE_WEB_CONTAINER_NAME}"
    printf '%s\n' "restart_policy=${OPENCODE_WEB_RESTART_POLICY}"
    printf '%s\n' "run_detached=${OPENCODE_WEB_RUN_DETACHED}"
    printf '%s\n' "auto_pull=${OPENCODE_WEB_AUTO_PULL}"
    printf '%s\n' "build_pull=${OPENCODE_WEB_BUILD_PULL}"
    printf '%s\n' "opencode_config_dir=${OPENCODE_WEB_CONFIG_DIR}"
    printf '%s\n' "opencode_data_dir=${OPENCODE_WEB_DATA_DIR}"
    printf '%s\n' "runtime_env_home=${runtime_home}"
    printf '%s\n' "runtime_env_xdg_config_home=${runtime_xdg_config}"
    printf '%s\n' "runtime_env_xdg_data_home=${runtime_xdg_data}"
    printf '%s\n' "runtime_env_xdg_state_home=${runtime_xdg_state}"
    printf '%s\n' "command=opencode web --hostname ${OPENCODE_WEB_HOSTNAME} --port ${OPENCODE_WEB_PORT}"
    printf '%s\n' "env.OPENCODE_SERVER_USERNAME=${OPENCODE_SERVER_USERNAME}"
    printf '%s\n' "host_agents_source=${host_agents_source}"
    printf '%s\n' "host_agents_path=${host_agents_path}"
    printf '%s\n' "host_agents_disabled=${host_agents_disabled}"
    printf '%s\n' "docker_command:"
    printf '  '
    printf '%q ' "${docker_cmd[@]}"
    printf '\n'
    if [ -n "$host_agents_log" ]; then
      printf '%s\n' "${host_agents_log}"
    fi
    return 0
  fi

  if [ -n "$host_agents_log" ]; then
    log "${host_agents_log}"
  fi

  "${docker_cmd[@]}"
}

main "$@"
