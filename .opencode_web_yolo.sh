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
PLAYWRIGHT_DEFAULT_VERSION="1.62.1"
OPENCODE_PACKAGE="opencode-ai"

is_true() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

normalize_bool() {
  if is_true "${1:-0}"; then
    printf '%s\n' 1
  else
    printf '%s\n' 0
  fi
}

node_version_is_22() {
  [[ "${1:-}" =~ ^v22\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

validate_retention_days() {
  local value
  case "${OPENCODE_WEB_RETENTION_DAYS}" in
    ''|*[!0-9]*)
      die "OPENCODE_WEB_RETENTION_DAYS must be a non-negative integer (received '${OPENCODE_WEB_RETENTION_DAYS:-unset}')."
      ;;
  esac
  value="${OPENCODE_WEB_RETENTION_DAYS}"
  while [ "${value#0}" != "$value" ]; do value="${value#0}"; done
  OPENCODE_WEB_RETENTION_DAYS="${value:-0}"
}

validate_positive_integer() {
  local name="$1" value="$2"
  if ! [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
    die "${name} must be a positive integer (received '${value:-unset}')."
  fi
  if [ "${#value}" -gt 10 ] || { [ "${#value}" -eq 10 ] && (( value > 2147483647 )); }; then
    die "${name} is outside the supported positive integer range (received '${value}')."
  fi
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
  local left="$1" right="$2"
  local left_major left_minor left_patch right_major right_minor right_patch

  [[ "$left" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
  left_major="${BASH_REMATCH[1]}"
  left_minor="${BASH_REMATCH[2]}"
  left_patch="${BASH_REMATCH[3]}"
  [[ "$right" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
  right_major="${BASH_REMATCH[1]}"
  right_minor="${BASH_REMATCH[2]}"
  right_patch="${BASH_REMATCH[3]}"

  while [ "${left_major#0}" != "$left_major" ]; do left_major="${left_major#0}"; done
  while [ "${left_minor#0}" != "$left_minor" ]; do left_minor="${left_minor#0}"; done
  while [ "${left_patch#0}" != "$left_patch" ]; do left_patch="${left_patch#0}"; done
  while [ "${right_major#0}" != "$right_major" ]; do right_major="${right_major#0}"; done
  while [ "${right_minor#0}" != "$right_minor" ]; do right_minor="${right_minor#0}"; done
  while [ "${right_patch#0}" != "$right_patch" ]; do right_patch="${right_patch#0}"; done
  left_major="${left_major:-0}"
  left_minor="${left_minor:-0}"
  left_patch="${left_patch:-0}"
  right_major="${right_major:-0}"
  right_minor="${right_minor:-0}"
  right_patch="${right_patch:-0}"

  if ((left_major != right_major)); then
    ((left_major > right_major))
  elif ((left_minor != right_minor)); then
    ((left_minor > right_minor))
  elif ((left_patch != right_patch)); then
    ((left_patch > right_patch))
  else
    return 1
  fi
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

fallback_managed_files() {
  cat <<'EOF'
.opencode_web_yolo.manifest
.opencode_web_yolo.sh
.opencode_web_yolo_config.sh
.opencode_web_yolo.Dockerfile
.opencode_web_yolo_entrypoint.sh
.opencode_web_yolo_runtime.sh
.opencode_web_yolo_retention.js
.opencode_web_yolo_completion.bash
.opencode_web_yolo_completion.zsh
install.sh
VERSION
CHANGELOG.md
README.md
TECHNICAL.md
LICENSE
CODEOWNERS
EOF
}

manifest_has_canonical_files() {
  local manifest_file="$1" canonical_file manifest_entry
  local seen_manifest_file

  [ -f "$manifest_file" ] || return 1
  [ -s "$manifest_file" ] || return 1
  seen_manifest_file="$(mktemp "${TMPDIR:-/tmp}/opencode_web_yolo-manifest.XXXXXX")" || return 1

  while IFS= read -r manifest_entry || [ -n "$manifest_entry" ]; do
    [ -n "$manifest_entry" ] || continue
    case "$manifest_entry" in
      *[!A-Za-z0-9._-]*) rm -f "$seen_manifest_file"; return 1 ;;
    esac
    if grep -Fqx -- "$manifest_entry" "$seen_manifest_file"; then
      rm -f "$seen_manifest_file"
      return 1
    fi
    if ! printf '%s\n' "$manifest_entry" >>"$seen_manifest_file"; then
      rm -f "$seen_manifest_file"
      return 1
    fi
  done <"$manifest_file"

  while IFS= read -r canonical_file; do
    if ! grep -Fqx -- "$canonical_file" "$manifest_file"; then
      rm -f "$seen_manifest_file"
      return 1
    fi
  done < <(fallback_managed_files)
  rm -f "$seen_manifest_file"
}

managed_files_for_dir() {
  local source_dir="$1"
  local manifest_file="${source_dir}/.opencode_web_yolo.manifest"

  if manifest_has_canonical_files "$manifest_file"; then
    cat "$manifest_file"
  else
    fallback_managed_files
  fi
}

validate_managed_tree() {
  local source_dir="$1" manifest_file required_file required_path version

  manifest_file="${source_dir}/.opencode_web_yolo.manifest"
  if [ -e "$manifest_file" ] && ! manifest_has_canonical_files "$manifest_file"; then
    return 1
  fi

  while IFS= read -r required_file || [ -n "$required_file" ]; do
    [ -n "$required_file" ] || continue
    required_path="${source_dir}/${required_file}"
    [ -f "$required_path" ] || return 1
    [ ! -L "$required_path" ] || return 1
    [ -s "$required_path" ] || return 1
    case "$required_file" in
      *.sh|*.bash)
        bash -n "$required_path" >/dev/null 2>&1 || return 1
        ;;
    esac
  done < <(managed_files_for_dir "$source_dir")

  version="$(tr -d '[:space:]' <"${source_dir}/VERSION")"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
}

url_encode_branch() {
  local branch="$1" encoded="" character byte index

  for ((index = 0; index < ${#branch}; index++)); do
    character="${branch:index:1}"
    case "$character" in
      [A-Za-z0-9._~-]|/) encoded+="$character" ;;
      *)
        printf -v byte '%02X' "'${character}"
        encoded+="%${byte}"
        ;;
    esac
  done
  printf '%s\n' "$encoded"
}

validate_archive_path() {
  local path="$1" component remainder

  case "$path" in
    ""|/*|*//* ) return 1 ;;
  esac
  remainder="$path"
  while :; do
    if [[ "$remainder" == */* ]]; then
      component="${remainder%%/*}"
      remainder="${remainder#*/}"
    else
      component="$remainder"
      remainder=""
    fi
    case "$component" in
      ""|.|..) return 1 ;;
    esac
    [ -n "$remainder" ] || break
  done
}

validate_archive_contents() {
  local archive_file="$1" archive_root="" archive_entry relative_entry listing type_char
  local root_directory_seen=0

  if ! tar -tzf "$archive_file" >/dev/null 2>&1 || ! tar -tvzf "$archive_file" >/dev/null 2>&1; then
    return 1
  fi
  while IFS= read -r listing; do
    [ -n "$listing" ] || continue
    type_char="${listing:0:1}"
    case "$type_char" in
      -|d) ;;
      *) return 1 ;;
    esac
  done < <(tar -tvzf "$archive_file")

  while IFS= read -r archive_entry; do
    [ -n "$archive_entry" ] || continue
    case "$archive_entry" in
      */*)
        archive_root="${archive_entry%%/*}"
        break
        ;;
      *) return 1 ;;
    esac
  done < <(tar -tzf "$archive_file")
  validate_archive_path "$archive_root" || return 1
  while IFS= read -r archive_entry; do
    [ -n "$archive_entry" ] || continue
    case "$archive_entry" in
      "${archive_root}/"*)
        relative_entry="${archive_entry#"${archive_root}/"}"
        validate_archive_path "$archive_entry" || return 1
        [ -n "$relative_entry" ] || root_directory_seen=1
        ;;
      *) return 1 ;;
    esac
  done < <(tar -tzf "$archive_file")
  [ "$root_directory_seen" -eq 1 ] || return 1
}

download_release_snapshot() {
  local destination_dir="$1" repo="$2" branch="$3"
  local archive_file extract_dir archive_url

  require_command tar
  branch="$(url_encode_branch "$branch")"
  archive_url="https://github.com/${repo}/archive/refs/heads/${branch}.tar.gz"
  archive_file="${destination_dir}/release.tar.gz"
  extract_dir="${destination_dir}/release"
  mkdir -p "$extract_dir"

  if ! curl -fsSL "$archive_url" -o "$archive_file"; then
    die "Failed downloading release archive from ${archive_url}."
  fi
  if ! validate_archive_contents "$archive_file"; then
    die "Downloaded release archive from ${repo}@${branch} is malformed or truncated."
  fi

  if ! tar -xzf "$archive_file" -C "$extract_dir" --strip-components=1; then
    die "Failed extracting release archive from ${repo}@${branch}."
  fi
  printf '%s\n' "$extract_dir"
}

promote_release() {
  local source_dir="$1" install_home="$2" managed_file source_file destination_file

  mkdir -p "$install_home"
  chmod +x "${source_dir}/.opencode_web_yolo.sh" "${source_dir}/.opencode_web_yolo_entrypoint.sh" "${source_dir}/install.sh"
  while IFS= read -r managed_file || [ -n "$managed_file" ]; do
    [ -n "$managed_file" ] || continue
    case "$managed_file" in
      .opencode_web_yolo.sh|VERSION) continue ;;
    esac
    source_file="${source_dir}/${managed_file}"
    destination_file="${install_home}/${managed_file}"
    mkdir -p "$(dirname "$destination_file")"
    # Test-only interruption hook; normal installs never set this variable.
    if [ "${OPENCODE_WEB_YOLO_TEST_FAIL_PROMOTION_ON:-}" = "$managed_file" ]; then
      die "Test promotion interruption requested for '${managed_file}'."
    fi
    mv -f "$source_file" "$destination_file"
  done < <(managed_files_for_dir "$source_dir")

  mv -f "${source_dir}/.opencode_web_yolo.sh" "${install_home}/.opencode_web_yolo.sh"
  if [ "${OPENCODE_WEB_YOLO_TEST_FAIL_PROMOTION_ON:-}" = "after-wrapper" ]; then
    die "Test promotion interruption requested after wrapper promotion."
  fi
  mv -f "${source_dir}/VERSION" "${install_home}/VERSION"
}

apply_self_update() {
  local install_home repo branch branch_url local_version remote_version remote_base tmpdir staged_dir
  local local_complete=1 staged_version

  if ! validate_managed_tree "$SCRIPT_DIR"; then
    local_complete=0
  fi

  if is_true "${OPENCODE_WEB_UPDATE_REEXECED:-0}"; then
    if [ "$local_complete" -ne 1 ]; then
      die "Managed install is incomplete after self-update; refusing to build or re-exec."
    fi
    debug "Self-update re-exec already completed; skipping another update check."
    return 0
  fi

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
  branch_url="$(url_encode_branch "$branch")"
  remote_base="https://raw.githubusercontent.com/${repo}/${branch_url}"
  if ! remote_version="$(curl -fsSL "${remote_base}/VERSION" | tr -d '[:space:]')"; then
    warn "Update check failed while reading remote VERSION from ${repo}@${branch}. Continuing with local files."
    return 0
  fi
  if [[ ! "$remote_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    warn "Ignoring invalid remote VERSION '${remote_version}' from ${repo}@${branch}."
    return 0
  fi

  if [ "$local_complete" -eq 1 ] && ! version_gt "$remote_version" "$local_version"; then
    debug "Local version (${local_version}) is up to date."
    return 0
  fi

  if version_gt "$remote_version" "$local_version"; then
    log "Updating wrapper from ${local_version} to ${remote_version}."
  else
    log "Repairing incomplete managed install at version ${local_version}."
  fi

  mkdir -p "$(dirname "$install_home")" "$install_home"
  tmpdir="$(mktemp -d "${install_home}/.opencode_web_yolo-update.XXXXXX")"
  trap 'rm -rf "${tmpdir:-}"' EXIT
  staged_dir="$(download_release_snapshot "$tmpdir" "$repo" "$branch")"
  if ! validate_managed_tree "$staged_dir"; then
    die "Downloaded release archive from ${repo}@${branch} is missing, empty, or contains invalid managed files."
  fi
  staged_version="$(tr -d '[:space:]' <"${staged_dir}/VERSION")"
  if [ "$staged_version" != "$remote_version" ]; then
    die "Remote VERSION changed during self-update (checked ${remote_version}, archive contains ${staged_version}); refusing promotion."
  fi
  if ! version_gt "$staged_version" "$local_version" && [ "$local_complete" -eq 1 ]; then
    die "Release archive version ${staged_version} cannot update local version ${local_version}."
  fi
  if [ "$local_complete" -eq 0 ] && version_gt "$local_version" "$staged_version"; then
    die "Cannot repair incomplete version ${local_version} from older release ${staged_version}."
  fi

  promote_release "$staged_dir" "$install_home"
  rm -rf "$tmpdir"
  trap - EXIT

  log "Update complete, re-executing wrapper."
  export OPENCODE_WEB_UPDATE_REEXECED=1
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
  --playwright           Build runtime image with Playwright Chromium.
  --wrangler             Build Wrangler and mount host Wrangler config read-write.
  --retention-days N     Delete inactive root sessions older than N days (0 disables).
  --retention-days=N     Same as above, using an equals-form value.
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
  Session retention: ${OPENCODE_WEB_RETENTION_DAYS} days (0 disables)

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
  ( umask 077; mkdir -p "$config_dir" )
  if [ -e "$config_file" ] || [ -L "$config_file" ]; then
    die "Config file already exists at ${config_file}. Refusing to overwrite."
  fi

  (
    umask 077
    set -C
    cat >"$config_file" <<'EOF'
# opencode_web_yolo user config
# Required: set a non-empty password before running the server.
# export OPENCODE_SERVER_PASSWORD='change-me-now'
# export OPENCODE_SERVER_USERNAME=opencode
# export OPENCODE_WEB_PORT=4096
# export OPENCODE_WEB_CONTAINER_NAME=opencode_web_yolo
# export OPENCODE_WEB_RESTART_POLICY=unless-stopped
# export OPENCODE_WEB_RUN_DETACHED=1
# export OPENCODE_WEB_YOLO_IMAGE=opencode_web_yolo:latest
# export OPENCODE_WEB_CONFIG_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/opencode
# export OPENCODE_WEB_DATA_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/opencode
# export OPENCODE_WEB_BUILD_PLAYWRIGHT=1
# export OPENCODE_WEB_BUILD_WRANGLER=1
# export OPENCODE_WEB_RETENTION_DAYS=30
# Advanced persistent overrides:
# export OPENCODE_WEB_SKIP_UPDATE_CHECK=1
# export OPENCODE_WEB_YOLO_REPO=laurenceputra/opencode_web_yolo
# export OPENCODE_WEB_YOLO_BRANCH=main
# export OPENCODE_WEB_RETENTION_POLL_SECONDS=3600
# export OPENCODE_WEB_RETENTION_FETCH_TIMEOUT_MS=10000
# export OPENCODE_WEB_RETENTION_VERIFY_TIMEOUT_MS=10000
# One-shot/troubleshooting controls are intentionally not generated here:
# --pull, --no-pull, OPENCODE_WEB_BUILD_PULL, OPENCODE_WEB_BUILD_NO_CACHE,
# --dry-run, OPENCODE_WEB_DRY_RUN, --verbose, OPENCODE_WEB_RETENTION_DRY_RUN,
# and version-check overrides.
EOF
  )
  log "Wrote ${config_file}."
}

show_health() {
  local status=0
  local image_wrapper_version image_opencode_version image_node_version image_node_major image_playwright image_playwright_version image_playwright_expected_version image_wrangler
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
  printf '%s\n' "  build_playwright=${OPENCODE_WEB_BUILD_PLAYWRIGHT}"
  printf '%s\n' "  build_wrangler=${OPENCODE_WEB_BUILD_WRANGLER}"
  printf '%s\n' "  retention_days=${OPENCODE_WEB_RETENTION_DAYS}"
  printf '%s\n' "  retention_dry_run=${OPENCODE_WEB_RETENTION_DRY_RUN}"
  printf '%s\n' "  retention_poll_seconds=${OPENCODE_WEB_RETENTION_POLL_SECONDS}"
  printf '%s\n' "  retention_fetch_timeout_ms=${OPENCODE_WEB_RETENTION_FETCH_TIMEOUT_MS}"
  printf '%s\n' "  retention_verify_timeout_ms=${OPENCODE_WEB_RETENTION_VERIFY_TIMEOUT_MS}"
  printf '%s\n' "  retention_schedule=after-health-at-most-weekly"
  printf '%s\n' "  retention_marker=${runtime_xdg_state}/session-retention.last-success"
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
    image_node_version="$(docker run --rm --entrypoint cat "${OPENCODE_WEB_YOLO_IMAGE}" /opt/opencode-web-yolo-node-version 2>/dev/null || true)"
    image_node_major="$(docker run --rm --entrypoint cat "${OPENCODE_WEB_YOLO_IMAGE}" /opt/opencode-web-yolo-node-major 2>/dev/null || true)"
    image_playwright="$(docker run --rm --entrypoint cat "${OPENCODE_WEB_YOLO_IMAGE}" /opt/opencode-web-yolo-playwright 2>/dev/null || true)"
    image_playwright_version="$(docker run --rm --entrypoint cat "${OPENCODE_WEB_YOLO_IMAGE}" /opt/opencode-web-yolo-playwright-version 2>/dev/null || true)"
    image_playwright_expected_version="$(docker run --rm --entrypoint cat "${OPENCODE_WEB_YOLO_IMAGE}" /opt/opencode-web-yolo-playwright-expected-version 2>/dev/null || true)"
    image_wrangler="$(docker run --rm --entrypoint cat "${OPENCODE_WEB_YOLO_IMAGE}" /opt/opencode-web-yolo-wrangler 2>/dev/null || true)"
    printf '%s\n' "  image_wrapper_version=${image_wrapper_version:-unknown}"
    printf '%s\n' "  image_opencode_version=${image_opencode_version:-unknown}"
    printf '%s\n' "  image_node_version=${image_node_version:-unknown}"
    printf '%s\n' "  image_node_major=${image_node_major:-unknown}"
    printf '%s\n' "  image_build_playwright=${image_playwright:-unknown}"
    printf '%s\n' "  image_playwright_version=${image_playwright_version:-unknown}"
    printf '%s\n' "  image_playwright_expected_version=${image_playwright_expected_version:-unknown}"
    printf '%s\n' "  image_build_wrangler=${image_wrangler:-unknown}"
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

  npm view "${OPENCODE_PACKAGE}" version --json 2>/dev/null | tr -d '"' | tr -d '[:space:]'
}

resolve_expected_playwright_version() {
  local resolved_version

  if ! is_true "${OPENCODE_WEB_BUILD_PLAYWRIGHT}"; then
    return 0
  fi

  if is_true "${OPENCODE_WEB_SKIP_VERSION_CHECK}"; then
    debug "Skipping Playwright npm version check."
    return 0
  fi

  if command -v npm >/dev/null 2>&1; then
    if resolved_version="$(npm view @playwright/test version --json 2>/dev/null | tr -d '"' | tr -d '[:space:]')" && [ -n "$resolved_version" ]; then
      printf '%s\n' "$resolved_version"
      return 0
    fi
    warn "npm could not resolve the latest @playwright/test version; using pinned fallback ${PLAYWRIGHT_DEFAULT_VERSION}."
  else
    warn "npm is not available; using pinned fallback ${PLAYWRIGHT_DEFAULT_VERSION} for Playwright version checks."
  fi

  printf '%s\n' "${PLAYWRIGHT_DEFAULT_VERSION}"
}

build_image() {
  local requested_opencode_version requested_playwright_version build_opencode_version build_playwright_version
  local -a build_cmd

  requested_opencode_version="${1:-}"
  build_opencode_version="latest"
  if [ -n "$requested_opencode_version" ]; then
    build_opencode_version="$requested_opencode_version"
  elif [ -n "${OPENCODE_WEB_EXPECTED_OPENCODE_VERSION:-}" ]; then
    build_opencode_version="${OPENCODE_WEB_EXPECTED_OPENCODE_VERSION}"
  fi

  requested_playwright_version="${2:-}"
  build_playwright_version="${requested_playwright_version:-${PLAYWRIGHT_DEFAULT_VERSION}}"

  build_cmd=(docker build -f "${SCRIPT_DIR}/.opencode_web_yolo.Dockerfile")
  if is_true "${OPENCODE_WEB_BUILD_PULL}"; then
    build_cmd+=(--pull)
  fi
  if is_true "${OPENCODE_WEB_BUILD_NO_CACHE}"; then
    build_cmd+=(--no-cache)
  fi

  build_cmd+=(
    --build-arg "WRAPPER_VERSION=${WRAPPER_VERSION}"
    --build-arg "OPENCODE_VERSION=${build_opencode_version}"
    --build-arg "OPENCODE_WEB_BUILD_PLAYWRIGHT=${OPENCODE_WEB_BUILD_PLAYWRIGHT}"
    --build-arg "PLAYWRIGHT_VERSION=${build_playwright_version}"
    --build-arg "OPENCODE_WEB_BUILD_WRANGLER=${OPENCODE_WEB_BUILD_WRANGLER}"
    -t "${OPENCODE_WEB_YOLO_IMAGE}"
    "${SCRIPT_DIR}"
  )

  log "Building runtime image ${OPENCODE_WEB_YOLO_IMAGE} (opencode=${build_opencode_version}, playwright=${build_playwright_version})."
  "${build_cmd[@]}"
}

ensure_image() {
  local expected_opencode_version expected_playwright_version image_wrapper_version image_opencode_version image_node_version image_node_major image_playwright image_playwright_version image_wrangler
  local compatibility_rebuild_requires_pull
  local -a reasons

  reasons=()
  compatibility_rebuild_requires_pull=0
  expected_opencode_version="$(resolve_expected_opencode_version || true)"
  expected_playwright_version="$(resolve_expected_playwright_version || true)"

  if ! docker image inspect "${OPENCODE_WEB_YOLO_IMAGE}" >/dev/null 2>&1; then
    reasons+=("image '${OPENCODE_WEB_YOLO_IMAGE}' is missing")
    compatibility_rebuild_requires_pull=1
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
      compatibility_rebuild_requires_pull=1
    fi

    image_opencode_version="$(docker run --rm --entrypoint cat "${OPENCODE_WEB_YOLO_IMAGE}" /opt/opencode-version 2>/dev/null || true)"
    if [ -n "$expected_opencode_version" ] && [ "$image_opencode_version" != "$expected_opencode_version" ]; then
      reasons+=("OpenCode version mismatch (image='${image_opencode_version:-missing}', expected='${expected_opencode_version}')")
    fi

    image_node_version="$(docker run --rm --entrypoint cat "${OPENCODE_WEB_YOLO_IMAGE}" /opt/opencode-web-yolo-node-version 2>/dev/null || true)"
    image_node_major="$(docker run --rm --entrypoint cat "${OPENCODE_WEB_YOLO_IMAGE}" /opt/opencode-web-yolo-node-major 2>/dev/null || true)"
    if [ "${image_node_major}" != "22" ] || ! node_version_is_22 "${image_node_version}"; then
      reasons+=("Node runtime metadata mismatch (image_version='${image_node_version:-missing}', image_major='${image_node_major:-missing}', expected_major='22')")
      compatibility_rebuild_requires_pull=1
    fi

    image_playwright="$(docker run --rm --entrypoint cat "${OPENCODE_WEB_YOLO_IMAGE}" /opt/opencode-web-yolo-playwright 2>/dev/null || true)"
    if [ "$image_playwright" != "${OPENCODE_WEB_BUILD_PLAYWRIGHT}" ]; then
      reasons+=("Playwright build mismatch (image='${image_playwright:-missing}', expected='${OPENCODE_WEB_BUILD_PLAYWRIGHT}')")
    fi

    if ! is_true "${OPENCODE_WEB_SKIP_VERSION_CHECK}" && is_true "${OPENCODE_WEB_BUILD_PLAYWRIGHT}" && [ -n "$expected_playwright_version" ]; then
      image_playwright_version="$(docker run --rm --entrypoint cat "${OPENCODE_WEB_YOLO_IMAGE}" /opt/opencode-web-yolo-playwright-version 2>/dev/null || true)"
      if [ "$image_playwright_version" != "$expected_playwright_version" ]; then
        reasons+=("Playwright version mismatch (image='${image_playwright_version:-missing}', expected='${expected_playwright_version}')")
      fi
    fi

    image_wrangler="$(docker run --rm --entrypoint cat "${OPENCODE_WEB_YOLO_IMAGE}" /opt/opencode-web-yolo-wrangler 2>/dev/null || true)"
    if [ "$image_wrangler" != "${OPENCODE_WEB_BUILD_WRANGLER}" ]; then
      reasons+=("Wrangler build mismatch (image='${image_wrangler:-missing}', expected='${OPENCODE_WEB_BUILD_WRANGLER}')")
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
  if [ "$compatibility_rebuild_requires_pull" -eq 1 ]; then
    # A compatibility/version-driven rebuild may have been selected with
    # --no-pull or stale OPENCODE_WEB_AUTO_PULL=0. Refreshing the release-owned
    # runtime base is mandatory, so do not let those one-shot controls suppress
    # Docker's --pull.
    OPENCODE_WEB_BUILD_PULL=1
    log "Compatibility/version rebuild requires Docker --pull."
  fi
  build_image "$expected_opencode_version" "$expected_playwright_version"
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
  local mode use_gh mount_ssh use_wrangler
  local host_agents_enabled host_agents_source host_agents_path
  local host_agents_container_path host_agents_opencode_path
  local host_agents_codex_path host_agents_copilot_path host_agents_claude_path
  local host_agents_log host_agents_disabled
  local gh_host_config_dir
  local wrangler_host_config_dir
  local runtime_home runtime_xdg_config runtime_xdg_data runtime_xdg_state
  local -a passthrough docker_args app_cmd docker_cmd

  mode="run"
  use_gh=0
  mount_ssh=0
  use_wrangler=0
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
      --playwright)
        OPENCODE_WEB_BUILD_PLAYWRIGHT=1
        ;;
      --wrangler)
        OPENCODE_WEB_BUILD_WRANGLER=1
        use_wrangler=1
        ;;
      --retention-days=*)
        OPENCODE_WEB_RETENTION_DAYS="${1#*=}"
        ;;
      --retention-days)
        shift
        [ "$#" -gt 0 ] || die "--retention-days requires a non-negative integer value."
        OPENCODE_WEB_RETENTION_DAYS="$1"
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

  OPENCODE_WEB_BUILD_PULL="$(normalize_bool "${OPENCODE_WEB_BUILD_PULL}")"
  OPENCODE_WEB_BUILD_NO_CACHE="$(normalize_bool "${OPENCODE_WEB_BUILD_NO_CACHE}")"
  OPENCODE_WEB_BUILD_PLAYWRIGHT="$(normalize_bool "${OPENCODE_WEB_BUILD_PLAYWRIGHT}")"
  OPENCODE_WEB_BUILD_WRANGLER="$(normalize_bool "${OPENCODE_WEB_BUILD_WRANGLER}")"
  OPENCODE_WEB_AUTO_PULL="$(normalize_bool "${OPENCODE_WEB_AUTO_PULL}")"
  OPENCODE_WEB_RUN_DETACHED="$(normalize_bool "${OPENCODE_WEB_RUN_DETACHED}")"
  OPENCODE_WEB_SKIP_UPDATE_CHECK="$(normalize_bool "${OPENCODE_WEB_SKIP_UPDATE_CHECK}")"
  OPENCODE_WEB_SKIP_VERSION_CHECK="$(normalize_bool "${OPENCODE_WEB_SKIP_VERSION_CHECK}")"
  OPENCODE_WEB_RETENTION_DRY_RUN="$(normalize_bool "${OPENCODE_WEB_RETENTION_DRY_RUN}")"
  validate_retention_days
  if [ "$OPENCODE_WEB_RETENTION_DAYS" != "0" ]; then
    validate_positive_integer OPENCODE_WEB_RETENTION_POLL_SECONDS "${OPENCODE_WEB_RETENTION_POLL_SECONDS}"
    validate_positive_integer OPENCODE_WEB_RETENTION_FETCH_TIMEOUT_MS "${OPENCODE_WEB_RETENTION_FETCH_TIMEOUT_MS}"
    validate_positive_integer OPENCODE_WEB_RETENTION_VERIFY_TIMEOUT_MS "${OPENCODE_WEB_RETENTION_VERIFY_TIMEOUT_MS}"
  fi

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

  if ! validate_managed_tree "$SCRIPT_DIR"; then
    die "Managed install is incomplete or invalid; refusing to build or launch Docker. Re-run install.sh to repair it."
  fi

  if is_true "${OPENCODE_WEB_AUTO_PULL}"; then
    OPENCODE_WEB_BUILD_PULL=1
  fi

  require_password
  export OPENCODE_SERVER_PASSWORD
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
    -e OPENCODE_SERVER_PASSWORD
    -e "OPENCODE_SERVER_USERNAME=${OPENCODE_SERVER_USERNAME}"
    -e "OPENCODE_WEB_PORT=${OPENCODE_WEB_PORT}"
    -e "OPENCODE_WEB_RETENTION_DAYS=${OPENCODE_WEB_RETENTION_DAYS}"
    -e "OPENCODE_WEB_RETENTION_DRY_RUN=${OPENCODE_WEB_RETENTION_DRY_RUN}"
    -e "OPENCODE_WEB_RETENTION_POLL_SECONDS=${OPENCODE_WEB_RETENTION_POLL_SECONDS}"
    -e "OPENCODE_WEB_RETENTION_FETCH_TIMEOUT_MS=${OPENCODE_WEB_RETENTION_FETCH_TIMEOUT_MS}"
    -e "OPENCODE_WEB_RETENTION_VERIFY_TIMEOUT_MS=${OPENCODE_WEB_RETENTION_VERIFY_TIMEOUT_MS}"
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

  if [ "$use_wrangler" -eq 1 ]; then
    wrangler_host_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/.wrangler"
    [ -d "$wrangler_host_config_dir" ] || die "--wrangler requested but host Wrangler config directory does not exist at ${wrangler_host_config_dir}."
    warn "Mounting host Wrangler config read-write. Container processes can read, modify, and rotate your Cloudflare credentials; only use --wrangler with trusted code."
    docker_args+=(-v "${wrangler_host_config_dir}:${OPENCODE_WEB_YOLO_HOME}/.config/.wrangler:rw")
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

  app_cmd=(opencode serve --hostname "${OPENCODE_WEB_HOSTNAME}" --port "${OPENCODE_WEB_PORT}")
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
    printf '%s\n' "build_playwright=${OPENCODE_WEB_BUILD_PLAYWRIGHT}"
    printf '%s\n' "build_wrangler=${OPENCODE_WEB_BUILD_WRANGLER}"
    printf '%s\n' "retention_days=${OPENCODE_WEB_RETENTION_DAYS}"
    printf '%s\n' "retention_dry_run=${OPENCODE_WEB_RETENTION_DRY_RUN}"
    printf '%s\n' "retention_poll_seconds=${OPENCODE_WEB_RETENTION_POLL_SECONDS}"
    printf '%s\n' "retention_fetch_timeout_ms=${OPENCODE_WEB_RETENTION_FETCH_TIMEOUT_MS}"
    printf '%s\n' "retention_verify_timeout_ms=${OPENCODE_WEB_RETENTION_VERIFY_TIMEOUT_MS}"
    printf '%s\n' "retention_schedule=after-health-at-most-weekly"
    printf '%s\n' "retention_marker=${runtime_xdg_state}/session-retention.last-success"
    printf '%s\n' "opencode_config_dir=${OPENCODE_WEB_CONFIG_DIR}"
    printf '%s\n' "opencode_data_dir=${OPENCODE_WEB_DATA_DIR}"
    printf '%s\n' "runtime_env_home=${runtime_home}"
    printf '%s\n' "runtime_env_xdg_config_home=${runtime_xdg_config}"
    printf '%s\n' "runtime_env_xdg_data_home=${runtime_xdg_data}"
    printf '%s\n' "runtime_env_xdg_state_home=${runtime_xdg_state}"
    printf '%s\n' "command=opencode serve --hostname ${OPENCODE_WEB_HOSTNAME} --port ${OPENCODE_WEB_PORT}"
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
