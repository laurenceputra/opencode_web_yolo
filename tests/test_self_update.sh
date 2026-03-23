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
CURL_LOG="${TMP_DIR}/curl.log"
LOCAL_VERSION="$(tr -d '[:space:]' <"${ROOT_DIR}/VERSION")"
REMOTE_VERSION="9.9.9"

mkdir -p "$FAKE_BIN" "$HOME_DIR"
setup_fake_docker "$FAKE_BIN" "$LOCAL_VERSION"
setup_fake_curl "$FAKE_BIN"

export PATH="${FAKE_BIN}:${PATH}"
export HOME="${HOME_DIR}"
export OPENCODE_SERVER_PASSWORD="secret"
export OPENCODE_WEB_SKIP_VERSION_CHECK=1
export OPENCODE_WEB_YOLO_REPO="example/repo"
export OPENCODE_WEB_YOLO_BRANCH="main"
export OPENCODE_WEB_TEST_REMOTE_DIR="${REMOTE_DIR}"
export OPENCODE_WEB_TEST_CURL_LOG="${CURL_LOG}"

reset_install_home() {
  rm -rf "${INSTALL_HOME}"
  create_managed_install_home "$ROOT_DIR" "$INSTALL_HOME"
}

prepare_remote_release() {
  local version="$1"
  local readme_marker="$2"
  local managed_file

  rm -rf "${REMOTE_DIR}"
  mkdir -p "${REMOTE_DIR}"
  while IFS= read -r managed_file; do
    cp "${ROOT_DIR}/${managed_file}" "${REMOTE_DIR}/${managed_file}"
  done < <(managed_wrapper_files)

  printf '%s\n' "${version}" >"${REMOTE_DIR}/VERSION"
  printf '%s\n' "remote-${readme_marker}" >"${REMOTE_DIR}/README.md"
}

reset_install_home
prepare_remote_release "${REMOTE_VERSION}" "skip"
rm -f "${CURL_LOG}"
export OPENCODE_WEB_INSTALL_HOME="${INSTALL_HOME}"
export OPENCODE_WEB_SKIP_UPDATE_CHECK=1
output_skip="$("${INSTALL_HOME}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_contains "$output_skip" "DRY RUN"
if [ -s "${CURL_LOG}" ]; then
  fail "expected skip-update path to avoid curl"
fi
assert_equals "${LOCAL_VERSION}" "$(tr -d '[:space:]' <"${INSTALL_HOME}/VERSION")"

prepare_remote_release "${REMOTE_VERSION}" "not-install-home"
rm -f "${CURL_LOG}"
export OPENCODE_WEB_SKIP_UPDATE_CHECK=0
output_not_managed="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_contains "$output_not_managed" "DRY RUN"
if [ -s "${CURL_LOG}" ]; then
  fail "expected repo-local wrapper run to skip managed-home update checks"
fi

reset_install_home
prepare_remote_release "${LOCAL_VERSION}" "same-version"
rm -f "${CURL_LOG}"
output_same="$("${INSTALL_HOME}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_contains "$output_same" "DRY RUN"
assert_not_contains "$output_same" "Updating wrapper from"
same_version_calls="$(cat "${CURL_LOG}")"
assert_contains "$same_version_calls" "/VERSION"
assert_not_contains "$same_version_calls" "/README.md"
if grep -F -- "remote-same-version" "${INSTALL_HOME}/README.md" >/dev/null 2>&1; then
  fail "expected same-version update check to leave managed files untouched"
fi

reset_install_home
prepare_remote_release "${REMOTE_VERSION}" "updated"
chmod -x "${REMOTE_DIR}/.opencode_web_yolo.sh"
chmod -x "${REMOTE_DIR}/.opencode_web_yolo_entrypoint.sh"
chmod -x "${REMOTE_DIR}/install.sh"
rm -f "${CURL_LOG}"
output_update="$("${INSTALL_HOME}/.opencode_web_yolo.sh" --dry-run --foreground -- --model local 2>&1)"
assert_contains "$output_update" "Updating wrapper from ${LOCAL_VERSION} to ${REMOTE_VERSION}."
assert_contains "$output_update" "Update complete, re-executing wrapper."
assert_contains "$output_update" "DRY RUN"
assert_contains "$output_update" "run_detached=0"
assert_contains "$output_update" "--model local"
assert_equals "${REMOTE_VERSION}" "$(tr -d '[:space:]' <"${INSTALL_HOME}/VERSION")"
if ! grep -F -- "remote-updated" "${INSTALL_HOME}/README.md" >/dev/null 2>&1; then
  fail "expected updated README to be installed from remote release"
fi
assert_file_executable "${INSTALL_HOME}/.opencode_web_yolo.sh"
assert_file_executable "${INSTALL_HOME}/.opencode_web_yolo_entrypoint.sh"
assert_file_executable "${INSTALL_HOME}/install.sh"
update_calls="$(cat "${CURL_LOG}")"
while IFS= read -r managed_file; do
  assert_contains "$update_calls" "/${managed_file}"
done < <(managed_wrapper_files)

reset_install_home
prepare_remote_release "${REMOTE_VERSION}" "failure"
rm -f "${CURL_LOG}"
export OPENCODE_WEB_TEST_CURL_FAIL_ON="install.sh"
set +e
output_failure="$("${INSTALL_HOME}/.opencode_web_yolo.sh" --dry-run 2>&1)"
status=$?
set -e
unset OPENCODE_WEB_TEST_CURL_FAIL_ON
if [ "$status" -eq 0 ]; then
  fail "expected self-update download failure to exit non-zero"
fi
assert_contains "$output_failure" "Failed downloading 'install.sh' during self-update."
assert_not_contains "$output_failure" "DRY RUN"
assert_equals "${LOCAL_VERSION}" "$(tr -d '[:space:]' <"${INSTALL_HOME}/VERSION")"
if grep -F -- "remote-failure" "${INSTALL_HOME}/README.md" >/dev/null 2>&1; then
  fail "expected failed self-update to avoid partial managed file replacement"
fi

printf '%s\n' "PASS: self-update coverage"
