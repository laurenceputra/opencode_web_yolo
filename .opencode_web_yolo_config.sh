#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC2034
OPENCODE_WEB_YOLO_CONFIG_FILE_DEFAULT="${HOME}/.opencode_web_yolo/config"
OPENCODE_WEB_CONFIG_FILE="${OPENCODE_WEB_YOLO_CONFIG_FILE:-$OPENCODE_WEB_YOLO_CONFIG_FILE_DEFAULT}"

# These controls remain environment-compatible, but are intentionally not
# persistent config settings. Capture the caller's environment before loading
# the user file so old generated configs cannot turn troubleshooting switches
# into durable defaults.
_opencode_web_build_no_cache_env_set="${OPENCODE_WEB_BUILD_NO_CACHE+x}"
_opencode_web_build_no_cache_env="${OPENCODE_WEB_BUILD_NO_CACHE-}"
_opencode_web_build_pull_env_set="${OPENCODE_WEB_BUILD_PULL+x}"
_opencode_web_build_pull_env="${OPENCODE_WEB_BUILD_PULL-}"
_opencode_web_dry_run_env_set="${OPENCODE_WEB_DRY_RUN+x}"
_opencode_web_dry_run_env="${OPENCODE_WEB_DRY_RUN-}"
_opencode_web_verbose_env_set="${OPENCODE_WEB_VERBOSE+x}"
_opencode_web_verbose_env="${OPENCODE_WEB_VERBOSE-}"
_opencode_web_skip_version_check_env_set="${OPENCODE_WEB_SKIP_VERSION_CHECK+x}"
_opencode_web_skip_version_check_env="${OPENCODE_WEB_SKIP_VERSION_CHECK-}"
_opencode_web_retention_dry_run_env_set="${OPENCODE_WEB_RETENTION_DRY_RUN+x}"
_opencode_web_retention_dry_run_env="${OPENCODE_WEB_RETENTION_DRY_RUN-}"

# Runtime defaults
: "${OPENCODE_WEB_YOLO_IMAGE:=opencode_web_yolo:latest}"
: "${OPENCODE_WEB_PORT:=4096}"
: "${OPENCODE_WEB_HOSTNAME:=0.0.0.0}"
: "${OPENCODE_WEB_YOLO_HOME:=/home/opencode}"
: "${OPENCODE_WEB_YOLO_WORKDIR:=/workspace}"
: "${OPENCODE_WEB_YOLO_CLEANUP:=1}"
: "${OPENCODE_WEB_CONTAINER_NAME:=opencode_web_yolo}"
: "${OPENCODE_WEB_RESTART_POLICY:=unless-stopped}"
: "${OPENCODE_WEB_SKIP_UPDATE_CHECK:=0}"
: "${OPENCODE_WEB_SKIP_VERSION_CHECK:=0}"
: "${OPENCODE_WEB_BUILD_NO_CACHE:=0}"
: "${OPENCODE_WEB_BUILD_PULL:=0}"
: "${OPENCODE_WEB_BUILD_PLAYWRIGHT:=0}"
: "${OPENCODE_WEB_BUILD_WRANGLER:=0}"
: "${OPENCODE_WEB_AUTO_PULL:=1}"
: "${OPENCODE_WEB_RUN_DETACHED:=1}"
: "${OPENCODE_WEB_DRY_RUN:=0}"
: "${OPENCODE_WEB_VERBOSE:=0}"
if [ "${OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS+x}" != x ]; then
  OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS=300
fi
: "${OPENCODE_WEB_YOLO_REPO:=laurenceputra/opencode_web_yolo}"
: "${OPENCODE_WEB_YOLO_BRANCH:=main}"
: "${OPENCODE_SERVER_USERNAME:=opencode}"
if [ "${OPENCODE_WEB_RETENTION_DAYS+x}" != x ]; then
  OPENCODE_WEB_RETENTION_DAYS=0
fi
: "${OPENCODE_WEB_RETENTION_DRY_RUN:=0}"
if [ "${OPENCODE_WEB_RETENTION_POLL_SECONDS+x}" != x ]; then
  OPENCODE_WEB_RETENTION_POLL_SECONDS=3600
fi
if [ "${OPENCODE_WEB_RETENTION_FETCH_TIMEOUT_MS+x}" != x ]; then
  OPENCODE_WEB_RETENTION_FETCH_TIMEOUT_MS=10000
fi
if [ "${OPENCODE_WEB_RETENTION_VERIFY_TIMEOUT_MS+x}" != x ]; then
  OPENCODE_WEB_RETENTION_VERIFY_TIMEOUT_MS=10000
fi

if [ -f "$OPENCODE_WEB_CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  . "$OPENCODE_WEB_CONFIG_FILE"
fi

# Release-owned runtime settings are fixed here, after the user file is
# sourced. This keeps existing configs usable while making stale assignments
# harmless without rewriting them.
OPENCODE_WEB_HOSTNAME=0.0.0.0
OPENCODE_WEB_YOLO_HOME=/home/opencode
OPENCODE_WEB_YOLO_WORKDIR=/workspace
OPENCODE_WEB_YOLO_CLEANUP=1

if [ "${_opencode_web_build_no_cache_env_set}" = x ]; then
  OPENCODE_WEB_BUILD_NO_CACHE="${_opencode_web_build_no_cache_env}"
else
  OPENCODE_WEB_BUILD_NO_CACHE=0
fi
if [ "${_opencode_web_build_pull_env_set}" = x ]; then
  OPENCODE_WEB_BUILD_PULL="${_opencode_web_build_pull_env}"
else
  OPENCODE_WEB_BUILD_PULL=0
fi
if [ "${_opencode_web_dry_run_env_set}" = x ]; then
  OPENCODE_WEB_DRY_RUN="${_opencode_web_dry_run_env}"
else
  OPENCODE_WEB_DRY_RUN=0
fi
if [ "${_opencode_web_verbose_env_set}" = x ]; then
  OPENCODE_WEB_VERBOSE="${_opencode_web_verbose_env}"
else
  OPENCODE_WEB_VERBOSE=0
fi
if [ "${_opencode_web_skip_version_check_env_set}" = x ]; then
  OPENCODE_WEB_SKIP_VERSION_CHECK="${_opencode_web_skip_version_check_env}"
else
  OPENCODE_WEB_SKIP_VERSION_CHECK=0
fi
if [ "${_opencode_web_retention_dry_run_env_set}" = x ]; then
  OPENCODE_WEB_RETENTION_DRY_RUN="${_opencode_web_retention_dry_run_env}"
else
  OPENCODE_WEB_RETENTION_DRY_RUN=0
fi

: "${OPENCODE_WEB_CONFIG_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
: "${OPENCODE_WEB_DATA_DIR:=${XDG_DATA_HOME:-$HOME/.local/share}/opencode}"
