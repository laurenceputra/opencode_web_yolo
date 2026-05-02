#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
FAKE_BIN="${TMP_DIR}/bin"
WRAPPER_VERSION="$(tr -d '[:space:]' <"${ROOT_DIR}/VERSION")"
DOCKER_LOG="${TMP_DIR}/docker.log"

mkdir -p "${FAKE_BIN}"

cat >"${FAKE_BIN}/docker" <<EOF
#!/usr/bin/env bash
set -euo pipefail
case "\$1" in
  info)
    exit 0
    ;;
  image)
    shift
    if [ "\${1:-}" = "inspect" ]; then
      exit 0
    fi
    ;;
  run)
    if printf '%s ' "\$@" | grep -F "/opt/opencode-web-yolo-version" >/dev/null 2>&1; then
      printf '%s\n' "${WRAPPER_VERSION}"
      exit 0
    fi
    if printf '%s ' "\$@" | grep -F "/opt/opencode-version" >/dev/null 2>&1; then
      printf '%s\n' "1.2.11"
      exit 0
    fi
    if printf '%s ' "\$@" | grep -F "/opt/opencode-web-yolo-playwright" >/dev/null 2>&1; then
      printf '%s\n' "0"
      exit 0
    fi
    exit 0
    ;;
  ps)
    exit 0
    ;;
  build)
    printf '%s\n' "\$*" >>"${DOCKER_LOG}"
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "${FAKE_BIN}/docker"

cat >"${FAKE_BIN}/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "view" ] && [ "${3:-}" = "version" ]; then
  printf '%s\n' '"1.2.15"'
  exit 0
fi
exit 1
EOF
chmod +x "${FAKE_BIN}/npm"

export PATH="${FAKE_BIN}:${PATH}"
export HOME="${TMP_DIR}/home"
mkdir -p "${HOME}"
export OPENCODE_WEB_SKIP_UPDATE_CHECK=1
export OPENCODE_WEB_BUILD_PULL=0
export OPENCODE_WEB_BUILD_PLAYWRIGHT=1
export OPENCODE_SERVER_PASSWORD="secret"

output="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"

assert_contains "$output" "OpenCode version mismatch (image='1.2.11', expected='1.2.15')"
assert_contains "$output" "Playwright build mismatch (image='0', expected='1')"
assert_contains "$output" "Building runtime image"

build_invocation="$(tr -d '\n' <"${DOCKER_LOG}")"
assert_contains "$build_invocation" "--build-arg OPENCODE_VERSION=1.2.15"
assert_contains "$build_invocation" "--build-arg OPENCODE_WEB_BUILD_PLAYWRIGHT=1"

printf '%s\n' "PASS: wrapper builds with resolved expected OpenCode version"
