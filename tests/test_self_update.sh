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
REMOTE_VERSION="0.10.0"
CURRENT_RELEASE_VERSION="0.2.2"

mkdir -p "$FAKE_BIN" "$HOME_DIR"
setup_fake_docker "$FAKE_BIN" "$LOCAL_VERSION"
setup_fake_curl "$FAKE_BIN"

unset OPENCODE_WEB_UPDATE_REEXECED OPENCODE_WEB_RETENTION_DAYS OPENCODE_WEB_RETENTION_DRY_RUN \
  OPENCODE_WEB_RETENTION_POLL_SECONDS OPENCODE_WEB_RETENTION_FETCH_TIMEOUT_MS \
  OPENCODE_WEB_RETENTION_VERIFY_TIMEOUT_MS OPENCODE_WEB_CONFIG_FILE OPENCODE_WEB_CONFIG_DIR \
  OPENCODE_WEB_DATA_DIR OPENCODE_WEB_YOLO_CONFIG_FILE OPENCODE_WEB_YOLO_HOME \
  OPENCODE_WEB_YOLO_WORKDIR OPENCODE_WEB_PORT OPENCODE_WEB_HOSTNAME OPENCODE_WEB_YOLO_IMAGE \
  OPENCODE_WEB_BASE_IMAGE OPENCODE_WEB_CONTAINER_NAME OPENCODE_WEB_RESTART_POLICY \
  OPENCODE_WEB_AUTO_PULL OPENCODE_WEB_RUN_DETACHED OPENCODE_WEB_DRY_RUN OPENCODE_WEB_BUILD_PULL \
  OPENCODE_WEB_BUILD_NO_CACHE OPENCODE_WEB_BUILD_PLAYWRIGHT OPENCODE_WEB_BUILD_WRANGLER \
  OPENCODE_WEB_EXPECTED_OPENCODE_VERSION OPENCODE_WEB_EXPECTED_PLAYWRIGHT_VERSION \
  OPENCODE_WEB_NPM_PACKAGE OPENCODE_SERVER_USERNAME || true

if grep -F 'sort -V' "${ROOT_DIR}/.opencode_web_yolo.sh" >/dev/null 2>&1; then
  fail "version comparison must not depend on sort -V"
fi
for production_file in "${ROOT_DIR}/.opencode_web_yolo.sh" "${ROOT_DIR}/install.sh"; do
  if grep -Eq 'local -A|declare -A|mapfile|readarray' "$production_file"; then
    fail "${production_file} contains a Bash 4-only construct"
  fi
done

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

create_old_install_home() {
  local old_file
  rm -rf "${INSTALL_HOME}"
  mkdir -p "${INSTALL_HOME}"
  while IFS= read -r old_file; do
    mkdir -p "$(dirname "${INSTALL_HOME}/${old_file}")"
    cp "${ROOT_DIR}/${old_file}" "${INSTALL_HOME}/${old_file}"
  done <<'EOF'
.opencode_web_yolo_config.sh
.opencode_web_yolo.Dockerfile
.opencode_web_yolo_entrypoint.sh
CHANGELOG.md
README.md
TECHNICAL.md
EOF
  cp "${ROOT_DIR}/tests/fixtures/old-0.1.10/.opencode_web_yolo.sh" "${INSTALL_HOME}/.opencode_web_yolo.sh"
  cp "${ROOT_DIR}/install.sh" "${INSTALL_HOME}/install.sh"
  printf '%s\n' '0.1.10' >"${INSTALL_HOME}/VERSION"
  assert_equals "3340ea78cbadfbcc3f436a0ba5822765813ff401" \
    "$(git hash-object "${ROOT_DIR}/tests/fixtures/old-0.1.10/.opencode_web_yolo.sh")"
  chmod +x "${INSTALL_HOME}/.opencode_web_yolo.sh"
  chmod +x "${INSTALL_HOME}/.opencode_web_yolo_entrypoint.sh"
  chmod +x "${INSTALL_HOME}/install.sh"
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

assert_malicious_archive_rejected() {
  local archive_mode="$1"
  local output status

  reset_install_home
  prepare_remote_release "${LOCAL_VERSION}" "malicious-${archive_mode}"
  rm -f "${INSTALL_HOME}/.opencode_web_yolo_runtime.sh" "${CURL_LOG}"
  export OPENCODE_WEB_TEST_ARCHIVE_MODE="$archive_mode"
  set +e
  output="$("${INSTALL_HOME}/.opencode_web_yolo.sh" --dry-run 2>&1)"
  status=$?
  set -e
  unset OPENCODE_WEB_TEST_ARCHIVE_MODE
  if [ "$status" -eq 0 ]; then
    fail "expected ${archive_mode} archive rejection"
  fi
  assert_contains "$output" "malformed or truncated"
  assert_equals "${LOCAL_VERSION}" "$(tr -d '[:space:]' <"${INSTALL_HOME}/VERSION")"
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
assert_not_contains "$same_version_calls" "/archive/refs/heads/"
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
assert_contains "$update_calls" "/VERSION"
assert_contains "$update_calls" "/archive/refs/heads/main.tar.gz"

reset_install_home
prepare_remote_release "${LOCAL_VERSION}" "repair"
rm -f "${INSTALL_HOME}/.opencode_web_yolo_runtime.sh" "${CURL_LOG}"
output_repair="$("${INSTALL_HOME}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_contains "$output_repair" "Repairing incomplete managed install at version ${LOCAL_VERSION}."
assert_contains "$output_repair" "DRY RUN"
if [ ! -s "${INSTALL_HOME}/.opencode_web_yolo_runtime.sh" ] || [ ! -s "${INSTALL_HOME}/.opencode_web_yolo_retention.js" ]; then
  fail "expected equal-version repair to restore runtime helpers"
fi
assert_equals "${LOCAL_VERSION}" "$(tr -d '[:space:]' <"${INSTALL_HOME}/VERSION")"
assert_contains "$(cat "${CURL_LOG}")" "/archive/refs/heads/main.tar.gz"

reset_install_home
prepare_remote_release "${LOCAL_VERSION}" "encoded-branch"
rm -f "${INSTALL_HOME}/.opencode_web_yolo_runtime.sh" "${CURL_LOG}"
export OPENCODE_WEB_YOLO_BRANCH="feature/release candidate"
output_encoded_branch="$("${INSTALL_HOME}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_contains "$output_encoded_branch" "DRY RUN"
assert_contains "$(cat "${CURL_LOG}")" "/archive/refs/heads/feature/release%20candidate.tar.gz"
export OPENCODE_WEB_YOLO_BRANCH="main"

assert_malicious_archive_rejected traversal
assert_malicious_archive_rejected symlink
assert_malicious_archive_rejected hardlink
assert_malicious_archive_rejected multi-root

reset_install_home
prepare_remote_release "${LOCAL_VERSION}" "malformed"
rm -f "${INSTALL_HOME}/.opencode_web_yolo_runtime.sh" "${CURL_LOG}"
export OPENCODE_WEB_TEST_ARCHIVE_MODE=malformed
set +e
output_malformed="$("${INSTALL_HOME}/.opencode_web_yolo.sh" --dry-run 2>&1)"
status=$?
set -e
unset OPENCODE_WEB_TEST_ARCHIVE_MODE
if [ "$status" -eq 0 ]; then
  fail "expected malformed archive rejection"
fi
assert_contains "$output_malformed" "malformed or truncated"
assert_equals "${LOCAL_VERSION}" "$(tr -d '[:space:]' <"${INSTALL_HOME}/VERSION")"
if [ -s "${INSTALL_HOME}/README.md" ] && grep -F -- "remote-malformed" "${INSTALL_HOME}/README.md" >/dev/null 2>&1; then
  fail "malformed archive must not advance or partially promote the install"
fi

reset_install_home
prepare_remote_release "${LOCAL_VERSION}" "missing-runtime"
rm -f "${INSTALL_HOME}/.opencode_web_yolo_runtime.sh" "${CURL_LOG}"
export OPENCODE_WEB_TEST_ARCHIVE_MISSING=.opencode_web_yolo_runtime.sh
set +e
output_missing="$("${INSTALL_HOME}/.opencode_web_yolo.sh" --dry-run 2>&1)"
status=$?
set -e
unset OPENCODE_WEB_TEST_ARCHIVE_MISSING
if [ "$status" -eq 0 ]; then
  fail "expected archive missing-file rejection"
fi
assert_contains "$output_missing" "missing, empty, or contains invalid managed files"
assert_equals "${LOCAL_VERSION}" "$(tr -d '[:space:]' <"${INSTALL_HOME}/VERSION")"

reset_install_home
prepare_remote_release "${REMOTE_VERSION}" "promotion-interruption"
rm -f "${CURL_LOG}"
export OPENCODE_WEB_YOLO_TEST_FAIL_PROMOTION_ON=.opencode_web_yolo_runtime.sh
set +e
output_interrupted="$("${INSTALL_HOME}/.opencode_web_yolo.sh" --dry-run 2>&1)"
status=$?
set -e
unset OPENCODE_WEB_YOLO_TEST_FAIL_PROMOTION_ON
if [ "$status" -eq 0 ]; then
  fail "expected simulated promotion interruption"
fi
assert_contains "$output_interrupted" "Test promotion interruption requested"
assert_equals "${LOCAL_VERSION}" "$(tr -d '[:space:]' <"${INSTALL_HOME}/VERSION")"
if grep -F -- "remote-promotion-interruption" "${INSTALL_HOME}/README.md" >/dev/null 2>&1; then
  fail "interrupted promotion must not advance the managed release"
fi
output_retry="$("${INSTALL_HOME}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_contains "$output_retry" "Update complete, re-executing wrapper."
assert_equals "${REMOTE_VERSION}" "$(tr -d '[:space:]' <"${INSTALL_HOME}/VERSION")"

reset_install_home
prepare_remote_release "${REMOTE_VERSION}" "wrapper-before-version"
printf '%s\n' '# test-after-wrapper-promotion' >>"${REMOTE_DIR}/.opencode_web_yolo.sh"
rm -f "${CURL_LOG}"
export OPENCODE_WEB_YOLO_TEST_FAIL_PROMOTION_ON=after-wrapper
set +e
output_after_wrapper="$("${INSTALL_HOME}/.opencode_web_yolo.sh" --dry-run 2>&1)"
status=$?
set -e
unset OPENCODE_WEB_YOLO_TEST_FAIL_PROMOTION_ON
if [ "$status" -eq 0 ]; then
  fail "expected simulated post-wrapper promotion interruption"
fi
assert_contains "$output_after_wrapper" "after wrapper promotion"
assert_equals "${LOCAL_VERSION}" "$(tr -d '[:space:]' <"${INSTALL_HOME}/VERSION")"
assert_contains "$(cat "${INSTALL_HOME}/.opencode_web_yolo.sh")" "test-after-wrapper-promotion"
output_after_wrapper_retry="$("${INSTALL_HOME}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_contains "$output_after_wrapper_retry" "Update complete, re-executing wrapper."
assert_equals "${REMOTE_VERSION}" "$(tr -d '[:space:]' <"${INSTALL_HOME}/VERSION")"

reset_install_home
prepare_remote_release "${LOCAL_VERSION}" "duplicate-manifest"
printf '%s\n' ".opencode_web_yolo_runtime.sh" >>"${REMOTE_DIR}/.opencode_web_yolo.manifest"
rm -f "${INSTALL_HOME}/.opencode_web_yolo_runtime.sh" "${CURL_LOG}"
set +e
output_duplicate="$("${INSTALL_HOME}/.opencode_web_yolo.sh" --dry-run 2>&1)"
status=$?
set -e
if [ "$status" -eq 0 ]; then
  fail "expected duplicate manifest rejection"
fi
assert_contains "$output_duplicate" "missing, empty, or contains invalid managed files"
assert_equals "${LOCAL_VERSION}" "$(tr -d '[:space:]' <"${INSTALL_HOME}/VERSION")"

create_old_install_home
prepare_remote_release "${CURRENT_RELEASE_VERSION}" "old-wrapper-repair"
rm -f "${CURL_LOG}"
assert_equals "0.1.10" "$(tr -d '[:space:]' <"${INSTALL_HOME}/VERSION")"
output_old="$("${INSTALL_HOME}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_contains "$output_old" "DRY RUN"
if [ ! -s "${INSTALL_HOME}/.opencode_web_yolo_runtime.sh" ] || [ ! -s "${INSTALL_HOME}/.opencode_web_yolo_retention.js" ]; then
  fail "historical wrapper update did not repair newly added runtime helpers"
fi
if [ ! -s "${INSTALL_HOME}/.opencode_web_yolo.manifest" ]; then
  fail "historical wrapper update did not install the managed-file manifest"
fi
assert_equals "${CURRENT_RELEASE_VERSION}" "$(tr -d '[:space:]' <"${INSTALL_HOME}/VERSION")"
assert_contains "$(cat "${CURL_LOG}")" "/archive/refs/heads/main.tar.gz"

reset_install_home
prepare_remote_release "${REMOTE_VERSION}" "failure"
rm -f "${CURL_LOG}"
export OPENCODE_WEB_TEST_CURL_FAIL_ON="archive"
set +e
output_failure="$("${INSTALL_HOME}/.opencode_web_yolo.sh" --dry-run 2>&1)"
status=$?
set -e
unset OPENCODE_WEB_TEST_CURL_FAIL_ON
if [ "$status" -eq 0 ]; then
  fail "expected self-update download failure to exit non-zero"
fi
assert_contains "$output_failure" "Failed downloading release archive"
assert_not_contains "$output_failure" "DRY RUN"
assert_equals "${LOCAL_VERSION}" "$(tr -d '[:space:]' <"${INSTALL_HOME}/VERSION")"
if grep -F -- "remote-failure" "${INSTALL_HOME}/README.md" >/dev/null 2>&1; then
  fail "expected failed self-update to avoid partial managed file replacement"
fi

printf '%s\n' "PASS: self-update coverage"
