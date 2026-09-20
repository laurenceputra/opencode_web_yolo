#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
FAKE_BIN="${TMP_DIR}/bin"
CONFIG_FILE="${TMP_DIR}/home/.opencode_web_yolo/config"
BUILD_LOG="${TMP_DIR}/docker-build.log"
WRAPPER_VERSION="$(tr -d '[:space:]' <"${ROOT_DIR}/VERSION")"

setup_fake_docker "$FAKE_BIN" "$WRAPPER_VERSION"
export PATH="${FAKE_BIN}:${PATH}"
export HOME="${TMP_DIR}/home"
export OPENCODE_WEB_SKIP_UPDATE_CHECK=1
export OPENCODE_WEB_SKIP_VERSION_CHECK=1
export OPENCODE_SERVER_PASSWORD=secret
export FAKE_DOCKER_BUILD_LOG="$BUILD_LOG"
mkdir -p "${HOME}"

"${ROOT_DIR}/.opencode_web_yolo.sh" config >/dev/null
assert_equals 600 "$(stat -c '%a' "${CONFIG_FILE}")"
if grep -Eq '^export ' "${CONFIG_FILE}"; then
  fail "generated config must contain only commented overrides"
fi
assert_not_contains "$(cat "${CONFIG_FILE}")" "OPENCODE_WEB_BASE_IMAGE"
assert_not_contains "$(cat "${CONFIG_FILE}")" "OPENCODE_WEB_EXPECTED_PLAYWRIGHT_VERSION"

set +e
overwrite_output="$(${ROOT_DIR}/.opencode_web_yolo.sh config 2>&1)"
overwrite_status=$?
set -e
assert_equals 1 "$overwrite_status"
assert_contains "$overwrite_output" "Refusing to overwrite"

rm -f "${CONFIG_FILE}"
ln -s "${TMP_DIR}/not-created" "${CONFIG_FILE}"
set +e
symlink_output="$(${ROOT_DIR}/.opencode_web_yolo.sh config 2>&1)"
symlink_status=$?
set -e
assert_equals 1 "$symlink_status"
assert_contains "$symlink_output" "Refusing to overwrite"
rm -f "${CONFIG_FILE}"

cat >"${CONFIG_FILE}" <<'EOF'
export OPENCODE_WEB_BASE_IMAGE=node:20-slim
export OPENCODE_WEB_NPM_PACKAGE=old-package
export OPENCODE_WEB_HOSTNAME=127.0.0.1
export OPENCODE_WEB_YOLO_HOME=/legacy-home
export OPENCODE_WEB_YOLO_WORKDIR=/legacy-workdir
export OPENCODE_WEB_YOLO_CLEANUP=0
export OPENCODE_WEB_EXPECTED_PLAYWRIGHT_VERSION=9.9.9
export OPENCODE_WEB_BUILD_PLAYWRIGHT=0
EOF
chmod 600 "${CONFIG_FILE}"

export FAKE_IMAGE_NODE_VERSION=v20.11.1
export FAKE_IMAGE_NODE_MAJOR=20
export OPENCODE_WEB_AUTO_PULL=0
: >"${BUILD_LOG}"
legacy_output="$(${ROOT_DIR}/.opencode_web_yolo.sh --no-pull --dry-run 2>&1)"
assert_contains "$legacy_output" "hostname=0.0.0.0"
assert_contains "$legacy_output" "command=opencode serve --hostname 0.0.0.0"
assert_contains "$legacy_output" "runtime_env_home=/home/opencode"
assert_contains "$legacy_output" "-w /workspace"
assert_contains "$legacy_output" "Node runtime metadata mismatch"
assert_contains "$(cat "${BUILD_LOG}")" "--pull"
assert_not_contains "$(cat "${BUILD_LOG}")" "BASE_IMAGE"
assert_not_contains "$(cat "${BUILD_LOG}")" "OPENCODE_NPM_PACKAGE"
assert_not_contains "$(cat "${BUILD_LOG}")" "PLAYWRIGHT_VERSION=9.9.9"

for metadata_case in missing non22 major-mismatch; do
  : >"${BUILD_LOG}"
  case "$metadata_case" in
    missing)
      export FAKE_IMAGE_NODE_VERSION=__missing__ FAKE_IMAGE_NODE_MAJOR=__missing__
      ;;
    non22)
      export FAKE_IMAGE_NODE_VERSION=v20.11.1 FAKE_IMAGE_NODE_MAJOR=20
      ;;
    major-mismatch)
      export FAKE_IMAGE_NODE_VERSION=v22.14.0 FAKE_IMAGE_NODE_MAJOR=20
      ;;
  esac
  output="$(${ROOT_DIR}/.opencode_web_yolo.sh --no-pull --dry-run 2>&1)"
  assert_contains "$output" "Node runtime metadata mismatch"
  assert_contains "$(cat "${BUILD_LOG}")" "--pull"
done

for malformed_version in v22 v22.14 v22.x.0 22.14.0 v22.01.0 v22.14.0-extra; do
  : >"${BUILD_LOG}"
  export FAKE_IMAGE_NODE_VERSION="$malformed_version" FAKE_IMAGE_NODE_MAJOR=22
  output="$(${ROOT_DIR}/.opencode_web_yolo.sh --no-pull --dry-run 2>&1)"
  assert_contains "$output" "Node runtime metadata mismatch"
  assert_contains "$(cat "${BUILD_LOG}")" "--pull"
done

unset FAKE_IMAGE_NODE_VERSION FAKE_IMAGE_NODE_MAJOR
export FAKE_IMAGE_MISSING=1
: >"${BUILD_LOG}"
missing_image_output="$(${ROOT_DIR}/.opencode_web_yolo.sh --no-pull --dry-run 2>&1)"
assert_contains "$missing_image_output" "image 'opencode_web_yolo:latest' is missing"
assert_contains "$(cat "${BUILD_LOG}")" "--pull"
unset FAKE_IMAGE_MISSING

export FAKE_IMAGE_WRAPPER_VERSION=0.3.0
: >"${BUILD_LOG}"
version_drift_output="$(${ROOT_DIR}/.opencode_web_yolo.sh --no-pull --dry-run 2>&1)"
assert_contains "$version_drift_output" "wrapper version metadata mismatch"
assert_contains "$(cat "${BUILD_LOG}")" "--pull"
unset FAKE_IMAGE_WRAPPER_VERSION
: >"${BUILD_LOG}"
matching_output="$(${ROOT_DIR}/.opencode_web_yolo.sh --no-pull --dry-run 2>&1)"
assert_not_contains "$matching_output" "Node runtime metadata mismatch"
if [ -s "${BUILD_LOG}" ]; then
  fail "matching Node 22 metadata must allow image reuse"
fi

cat >"${CONFIG_FILE}" <<'EOF'
export OPENCODE_WEB_BUILD_NO_CACHE=0
export OPENCODE_WEB_BUILD_PULL=0
export OPENCODE_WEB_AUTO_PULL=1
export OPENCODE_WEB_DRY_RUN=0
export OPENCODE_WEB_RETENTION_DRY_RUN=0
EOF
: >"${BUILD_LOG}"
marker_cli_output="$(OPENCODE_WEB_UPDATE_REEXECED=1 OPENCODE_WEB_DRY_RUN=1 OPENCODE_WEB_RETENTION_DRY_RUN=1 OPENCODE_WEB_BUILD_PULL=1 OPENCODE_WEB_BUILD_NO_CACHE=1 OPENCODE_WEB_AUTO_PULL=1 OPENCODE_WEB_EXPECTED_OPENCODE_VERSION=1.2.7 "${ROOT_DIR}/.opencode_web_yolo.sh" --no-pull 2>&1)"
assert_contains "$marker_cli_output" "DRY RUN"
assert_contains "$marker_cli_output" "retention_dry_run=1"
assert_contains "$marker_cli_output" "auto_pull=0"
assert_contains "$marker_cli_output" "build_pull=0"
assert_not_contains "$marker_cli_output" "OpenCode version mismatch"
assert_contains "$(cat "${BUILD_LOG}")" "--no-cache"
assert_not_contains "$(cat "${BUILD_LOG}")" "--pull"

export FAKE_IMAGE_NODE_VERSION=v20.11.1
export FAKE_IMAGE_NODE_MAJOR=20
: >"${BUILD_LOG}"
marker_compatibility_output="$(OPENCODE_WEB_UPDATE_REEXECED=1 OPENCODE_WEB_DRY_RUN=1 OPENCODE_WEB_RETENTION_DRY_RUN=1 OPENCODE_WEB_BUILD_PULL=0 OPENCODE_WEB_BUILD_NO_CACHE=1 OPENCODE_WEB_AUTO_PULL=0 "${ROOT_DIR}/.opencode_web_yolo.sh" --no-pull 2>&1)"
assert_contains "$marker_compatibility_output" "DRY RUN"
assert_contains "$marker_compatibility_output" "retention_dry_run=1"
assert_contains "$marker_compatibility_output" "auto_pull=0"
assert_contains "$marker_compatibility_output" "build_pull=1"
assert_contains "$(cat "${BUILD_LOG}")" "--pull"
assert_contains "$(cat "${BUILD_LOG}")" "--no-cache"
unset FAKE_IMAGE_NODE_VERSION FAKE_IMAGE_NODE_MAJOR

cat >"${CONFIG_FILE}" <<'EOF'
export OPENCODE_WEB_BUILD_PLAYWRIGHT=0
export OPENCODE_WEB_BUILD_WRANGLER=0
EOF
export OPENCODE_WEB_EXPECTED_OPENCODE_VERSION=1.2.7
export OPENCODE_WEB_SKIP_VERSION_CHECK=0
: >"${BUILD_LOG}"
opencode_drift_output="$(${ROOT_DIR}/.opencode_web_yolo.sh --no-pull --dry-run 2>&1)"
assert_contains "$opencode_drift_output" "OpenCode version mismatch"
assert_not_contains "$(cat "${BUILD_LOG}")" "--pull"

cat >"${CONFIG_FILE}" <<'EOF'
export OPENCODE_WEB_BUILD_PLAYWRIGHT=1
export OPENCODE_WEB_BUILD_WRANGLER=1
EOF
unset OPENCODE_WEB_EXPECTED_OPENCODE_VERSION
export OPENCODE_WEB_SKIP_VERSION_CHECK=1
: >"${BUILD_LOG}"
feature_drift_output="$(${ROOT_DIR}/.opencode_web_yolo.sh --no-pull --dry-run 2>&1)"
assert_contains "$feature_drift_output" "Playwright build mismatch"
assert_contains "$feature_drift_output" "Wrangler build mismatch"
assert_not_contains "$(cat "${BUILD_LOG}")" "--pull"

printf '%s\n' "PASS: runtime-owned defaults and Node compatibility rebuilds"
