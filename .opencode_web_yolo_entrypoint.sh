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
OPENCODE_WEB_RETENTION_DAYS="${OPENCODE_WEB_RETENTION_DAYS-0}"
OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS="${OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS-300}"
STARTUP_VACUUM_BUSY_TIMEOUT_MS=5000
STARTUP_VACUUM_KILL_AFTER_SECONDS=5

case "$OPENCODE_WEB_RETENTION_DAYS" in
  ''|*[!0-9]*)
    printf '%s\n' "[opencode_web_yolo] ERROR: OPENCODE_WEB_RETENTION_DAYS must be a non-negative integer." >&2
    exit 1
    ;;
esac
while [ "${OPENCODE_WEB_RETENTION_DAYS#0}" != "$OPENCODE_WEB_RETENTION_DAYS" ]; do
  OPENCODE_WEB_RETENTION_DAYS="${OPENCODE_WEB_RETENTION_DAYS#0}"
done
OPENCODE_WEB_RETENTION_DAYS="${OPENCODE_WEB_RETENTION_DAYS:-0}"

case "$OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS" in
  ''|0*|*[!0-9]*)
    printf '%s\n' "[opencode_web_yolo] ERROR: OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS must be a positive integer." >&2
    exit 1
    ;;
esac
if [ "${#OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS}" -gt 10 ] || {
  [ "${#OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS}" -eq 10 ] &&
  (( OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS > 2147483647 ))
}; then
  printf '%s\n' "[opencode_web_yolo] ERROR: OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS is outside the supported positive integer range." >&2
  exit 1
fi

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

opencode_database="${XDG_DATA_HOME}/opencode/opencode.db"
if [ -f "${opencode_database}" ]; then
  printf '%s\n' "[opencode_web_yolo] VACUUM: compacting OpenCode database at ${opencode_database}."
  if gosu "${runtime_user}" timeout \
    --kill-after="${STARTUP_VACUUM_KILL_AFTER_SECONDS}" \
    "${OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS}" \
    sqlite3 \
    -cmd ".timeout ${STARTUP_VACUUM_BUSY_TIMEOUT_MS}" \
    "${opencode_database}" 'VACUUM;'; then
    :
  else
    vacuum_status=$?
    if [ "$vacuum_status" -eq 124 ] || [ "$vacuum_status" -eq 137 ]; then
      printf '%s\n' "[opencode_web_yolo] WARNING: startup VACUUM timed out after the ${OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS}-second TERM deadline (KILL escalation after ${STARTUP_VACUUM_KILL_AFTER_SECONDS} additional seconds); continuing startup." >&2
    else
      printf '%s\n' "[opencode_web_yolo] WARNING: startup VACUUM failed for ${opencode_database}; continuing startup." >&2
    fi
  fi
fi

if [ "$OPENCODE_WEB_RETENTION_DAYS" = "0" ]; then
  exec env HOME="${HOME}" XDG_CONFIG_HOME="${XDG_CONFIG_HOME}" XDG_DATA_HOME="${XDG_DATA_HOME}" XDG_STATE_HOME="${XDG_STATE_HOME}" gosu "${runtime_user}" "$@"
fi

exec env HOME="${HOME}" XDG_CONFIG_HOME="${XDG_CONFIG_HOME}" XDG_DATA_HOME="${XDG_DATA_HOME}" XDG_STATE_HOME="${XDG_STATE_HOME}" OPENCODE_WEB_RETENTION_DAYS="${OPENCODE_WEB_RETENTION_DAYS}" OPENCODE_WEB_RETENTION_DRY_RUN="${OPENCODE_WEB_RETENTION_DRY_RUN:-0}" gosu "${runtime_user}" /usr/local/bin/opencode_web_yolo_runtime.sh "$@"
