#!/usr/bin/env bash
set -euo pipefail

LOCAL_UID="${LOCAL_UID:-1000}"
LOCAL_GID="${LOCAL_GID:-1000}"
LOCAL_USER="${LOCAL_USER:-opencode}"
OPENCODE_WEB_YOLO_HOME="${OPENCODE_WEB_YOLO_HOME:-/home/opencode}"
OPENCODE_WEB_YOLO_CLEANUP="${OPENCODE_WEB_YOLO_CLEANUP:-1}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${OPENCODE_WEB_YOLO_HOME}/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-${OPENCODE_WEB_YOLO_HOME}/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-${XDG_DATA_HOME}/opencode/state}"
INSTRUCTIONS="${OPENCODE_INSTRUCTION_PATH:-/app/AGENTS.md}"

if [ -z "${OPENCODE_SERVER_PASSWORD:-}" ]; then
  printf '%s\n' "[opencode_web_yolo] ERROR: OPENCODE_SERVER_PASSWORD must be set and non-empty." >&2
  exit 1
fi

runtime_user="${LOCAL_USER}"
group_name="${LOCAL_USER}"
if ! getent group "${LOCAL_GID}" >/dev/null 2>&1; then
  groupadd -g "${LOCAL_GID}" "${group_name}"
else
  group_name="$(getent group "${LOCAL_GID}" | cut -d: -f1)"
fi

if getent passwd "${LOCAL_UID}" >/dev/null 2>&1; then
  runtime_user="$(getent passwd "${LOCAL_UID}" | cut -d: -f1)"
elif id -u "${LOCAL_USER}" >/dev/null 2>&1; then
  usermod -u "${LOCAL_UID}" -g "${LOCAL_GID}" "${LOCAL_USER}" >/dev/null 2>&1 || true
  runtime_user="${LOCAL_USER}"
else
  useradd -m -d "${OPENCODE_WEB_YOLO_HOME}" -u "${LOCAL_UID}" -g "${LOCAL_GID}" -s /bin/bash "${LOCAL_USER}"
  runtime_user="${LOCAL_USER}"
fi

current_home="$(getent passwd "${runtime_user}" | cut -d: -f6)"
if [ "${current_home}" != "${OPENCODE_WEB_YOLO_HOME}" ]; then
  usermod -d "${OPENCODE_WEB_YOLO_HOME}" "${runtime_user}" >/dev/null 2>&1 || true
fi

mkdir -p "${XDG_CONFIG_HOME}/opencode"
mkdir -p "${XDG_DATA_HOME}/opencode"
mkdir -p "${XDG_STATE_HOME}"
mkdir -p /workspace

# Avoid recursive chown on HOME: read-only mounts (for example ~/.config/gh or ~/.ssh)
# can be attached there, and touching them aborts startup.
chown "${LOCAL_UID}:${LOCAL_GID}" "${OPENCODE_WEB_YOLO_HOME}" >/dev/null 2>&1 || true
chown "${LOCAL_UID}:${LOCAL_GID}" "${XDG_CONFIG_HOME}" >/dev/null 2>&1 || true
chown "${LOCAL_UID}:${LOCAL_GID}" "${XDG_DATA_HOME}" >/dev/null 2>&1 || true
chown "${LOCAL_UID}:${LOCAL_GID}" "${XDG_STATE_HOME}" >/dev/null 2>&1 || true
chown -R "${LOCAL_UID}:${LOCAL_GID}" "${XDG_CONFIG_HOME}/opencode" >/dev/null 2>&1 || true
chown -R "${LOCAL_UID}:${LOCAL_GID}" "${XDG_DATA_HOME}/opencode" >/dev/null 2>&1 || true
chown -R "${LOCAL_UID}:${LOCAL_GID}" /workspace

printf '%s\n' "${runtime_user} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/90-opencode-web-yolo
chmod 0440 /etc/sudoers.d/90-opencode-web-yolo

cleanup() {
  if [ "${OPENCODE_WEB_YOLO_CLEANUP}" = "1" ]; then
    chown -R "${LOCAL_UID}:${LOCAL_GID}" /workspace >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

export HOME="${OPENCODE_WEB_YOLO_HOME}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME}"
export XDG_DATA_HOME="${XDG_DATA_HOME}"
export XDG_STATE_HOME="${XDG_STATE_HOME}"

if [ -r "${INSTRUCTIONS}" ]; then
  printf '%s\n' "[opencode_web_yolo] Loading instruction set from ${INSTRUCTIONS}"
else
  if [ "${INSTRUCTIONS}" != "/app/AGENTS.md" ] && [ -r "/app/AGENTS.md" ]; then
    printf '%s\n' "[opencode_web_yolo] WARNING: Instruction file not readable at ${INSTRUCTIONS}; falling back to /app/AGENTS.md"
    INSTRUCTIONS="/app/AGENTS.md"
    printf '%s\n' "[opencode_web_yolo] Loading instruction set from ${INSTRUCTIONS}"
  else
    printf '%s\n' "[opencode_web_yolo] ERROR: No readable instruction file found at ${INSTRUCTIONS} or /app/AGENTS.md" >&2
    exit 1
  fi
fi

export OPENCODE_INSTRUCTION_PATH="${INSTRUCTIONS}"

exec env HOME="${HOME}" XDG_CONFIG_HOME="${XDG_CONFIG_HOME}" XDG_DATA_HOME="${XDG_DATA_HOME}" XDG_STATE_HOME="${XDG_STATE_HOME}" OPENCODE_INSTRUCTION_PATH="${OPENCODE_INSTRUCTION_PATH}" gosu "${runtime_user}" "$@"
