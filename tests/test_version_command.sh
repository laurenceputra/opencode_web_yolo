#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_BIN="${TMP_DIR}/bin"
INSTALL_HOME="${TMP_DIR}/install-home"
REMOTE_DIR="${TMP_DIR}/remote"
HOME_DIR="${TMP_DIR}/home"
COMMAND_LOG="${TMP_DIR}/command.log"
WRAPPER_VERSION="$(tr -d '[:space:]' <"${ROOT_DIR}/VERSION")"

mkdir -p "$REMOTE_DIR" "$HOME_DIR" "$FAKE_BIN"
create_managed_install_home "$ROOT_DIR" "$INSTALL_HOME"
cp "${ROOT_DIR}/VERSION" "${REMOTE_DIR}/VERSION"
setup_fake_curl "$FAKE_BIN"

cat >"${FAKE_BIN}/docker" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "docker \$*" >>"${COMMAND_LOG}"
exit 99
EOF
chmod +x "${FAKE_BIN}/docker"

export PATH="${FAKE_BIN}:${PATH}"
export HOME="${HOME_DIR}"
export OPENCODE_WEB_INSTALL_HOME="${INSTALL_HOME}"
export OPENCODE_WEB_YOLO_REPO="example/repo"
export OPENCODE_WEB_YOLO_BRANCH="main"
export OPENCODE_WEB_TEST_REMOTE_DIR="${REMOTE_DIR}"
export OPENCODE_WEB_TEST_CURL_LOG="${TMP_DIR}/curl.log"
unset OPENCODE_SERVER_PASSWORD || true

output_flag="$("${INSTALL_HOME}/.opencode_web_yolo.sh" --version 2>&1)"
assert_equals "opencode_web_yolo ${WRAPPER_VERSION}" "$output_flag"

output_cmd="$("${INSTALL_HOME}/.opencode_web_yolo.sh" version 2>&1)"
assert_equals "opencode_web_yolo ${WRAPPER_VERSION}" "$output_cmd"

if [ -e "${COMMAND_LOG}" ]; then
  fail "expected version command to exit before invoking docker"
fi

if [ -e "${TMP_DIR}/curl.log" ]; then
  fail "expected version command to exit before invoking update checks"
fi

printf '%s\n' "PASS: version command"
