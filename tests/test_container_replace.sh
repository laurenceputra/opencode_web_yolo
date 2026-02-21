#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
FAKE_BIN="${TMP_DIR}/bin"
DOCKER_LOG="${TMP_DIR}/docker.log"
WRAPPER_VERSION="$(tr -d '[:space:]' <"${ROOT_DIR}/VERSION")"

mkdir -p "$FAKE_BIN"
cat >"${FAKE_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

LOG_PATH="${FAKE_DOCKER_LOG:?missing FAKE_DOCKER_LOG}"
WRAPPER_VERSION="${FAKE_WRAPPER_VERSION:?missing FAKE_WRAPPER_VERSION}"

case "$1" in
  info)
    exit 0
    ;;
  image)
    shift
    if [ "${1:-}" = "inspect" ]; then
      exit 0
    fi
    ;;
  ps)
    if printf '%s ' "$@" | grep -F -- "status=running" >/dev/null 2>&1; then
      printf '%s\n' "opencode_web_yolo"
      exit 0
    fi
    if printf '%s ' "$@" | grep -F -- "-a" >/dev/null 2>&1; then
      printf '%s\n' "opencode_web_yolo"
      exit 0
    fi
    exit 0
    ;;
  stop)
    printf 'stop %s\n' "$2" >>"${LOG_PATH}"
    exit 0
    ;;
  rm)
    printf 'rm %s\n' "$2" >>"${LOG_PATH}"
    exit 0
    ;;
  run)
    if printf '%s ' "$@" | grep -F "/opt/opencode-web-yolo-version" >/dev/null 2>&1; then
      printf '%s\n' "${WRAPPER_VERSION}"
      exit 0
    fi
    if printf '%s ' "$@" | grep -F "/opt/opencode-version" >/dev/null 2>&1; then
      printf '%s\n' "1.2.10"
      exit 0
    fi
    printf 'run\n' >>"${LOG_PATH}"
    exit 0
    ;;
  build)
    exit 0
    ;;
esac

exit 0
EOF
chmod +x "${FAKE_BIN}/docker"

export PATH="${FAKE_BIN}:${PATH}"
export HOME="${TMP_DIR}/home"
export FAKE_DOCKER_LOG="${DOCKER_LOG}"
export FAKE_WRAPPER_VERSION="${WRAPPER_VERSION}"
mkdir -p "${HOME}"
export OPENCODE_WEB_SKIP_UPDATE_CHECK=1
export OPENCODE_WEB_SKIP_VERSION_CHECK=1
export OPENCODE_SERVER_PASSWORD="secret"

output="$("${ROOT_DIR}/.opencode_web_yolo.sh" --foreground --no-pull 2>&1)"
docker_log="$(cat "${DOCKER_LOG}")"

assert_contains "$output" "Stopping existing running container 'opencode_web_yolo' before launch."
assert_contains "$output" "Removing existing container 'opencode_web_yolo' before launch."
assert_contains "$docker_log" $'stop opencode_web_yolo\nrm opencode_web_yolo'

printf '%s\n' "PASS: running container is replaced on launch"
