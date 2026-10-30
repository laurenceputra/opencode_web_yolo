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
      exit "\${FAKE_IMAGE_MISSING:-0}"
    fi
    ;;
  run)
    if printf '%s ' "\$@" | grep -F "/opt/opencode-web-yolo-version" >/dev/null 2>&1; then
      printf '%s\n' "${WRAPPER_VERSION}"
      exit 0
    fi
    if printf '%s ' "\$@" | grep -F "/opt/opencode-version" >/dev/null 2>&1; then
      printf '%s\n' "\${FAKE_IMAGE_OPENCODE_VERSION:-1.2.11}"
      exit 0
    fi
    if printf '%s ' "\$@" | grep -F "/opt/opencode-web-yolo-node-version" >/dev/null 2>&1; then
      printf '%s\n' "\${FAKE_IMAGE_NODE_VERSION:-v22.14.0}"
      exit 0
    fi
    if printf '%s ' "\$@" | grep -F "/opt/opencode-web-yolo-node-major" >/dev/null 2>&1; then
      printf '%s\n' "\${FAKE_IMAGE_NODE_MAJOR:-22}"
      exit 0
    fi
    if printf '%s ' "\$@" | grep -F "/opt/opencode-web-yolo-playwright-version" >/dev/null 2>&1; then
      printf '%s\n' "\${FAKE_IMAGE_PLAYWRIGHT_VERSION:-1.62.0}"
      exit 0
    fi
    if printf '%s ' "\$@" | grep -F "/opt/opencode-web-yolo-playwright" >/dev/null 2>&1; then
      printf '%s\n' "\${FAKE_IMAGE_PLAYWRIGHT_BUILD:-0}"
      exit 0
    fi
    if printf '%s ' "\$@" | grep -F "/opt/opencode-web-yolo-wrangler" >/dev/null 2>&1; then
      printf '%s\n' "\${FAKE_IMAGE_WRANGLER_BUILD:-0}"
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
  if [ -n "${FAKE_NPM_LOG:-}" ]; then
    printf '%s\n' "${2:-}" >>"${FAKE_NPM_LOG}"
  fi
  case "${2:-}" in
    @opencode/cli) printf '%s\n' "${FAKE_REGISTRY_VERSION-2.2.1}"; exit "${FAKE_REGISTRY_STATUS:-0}" ;;
    @playwright/test) printf '%s\n' '"1.62.1"' ;;
    *) exit 1 ;;
  esac
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
export OPENCODE_WEB_BUILD_PLAYWRIGHT=true
export OPENCODE_WEB_BUILD_WRANGLER=yes
export OPENCODE_SERVER_PASSWORD="secret"
export FAKE_NPM_LOG="${TMP_DIR}/npm.log"

output="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"

assert_contains "$output" "OpenCode version mismatch (image='1.2.11', expected='2.2.1')"
assert_contains "$output" "Playwright build mismatch (image='0', expected='1')"
assert_contains "$output" "Playwright version mismatch (image='1.62.0', expected='1.62.1')"
assert_contains "$output" "Wrangler build mismatch (image='0', expected='1')"
assert_contains "$output" "Building runtime image"

build_invocation="$(tr -d '\n' <"${DOCKER_LOG}")"
assert_contains "$build_invocation" "--build-arg OPENCODE_VERSION=2.2.1"
assert_contains "$(cat "$FAKE_NPM_LOG")" "@opencode/cli"
assert_contains "$build_invocation" "--build-arg OPENCODE_WEB_BUILD_PLAYWRIGHT=1"
assert_contains "$build_invocation" "--build-arg PLAYWRIGHT_VERSION=1.62.1"
assert_contains "$build_invocation" "--build-arg OPENCODE_WEB_BUILD_WRANGLER=1"

: >"${DOCKER_LOG}"
export OPENCODE_WEB_EXPECTED_PLAYWRIGHT_VERSION=1.62.2
output_override="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_contains "$output_override" "Playwright version mismatch (image='1.62.0', expected='1.62.1')"
build_invocation_override="$(tr -d '\n' <"${DOCKER_LOG}")"
assert_contains "$build_invocation_override" "--build-arg PLAYWRIGHT_VERSION=1.62.1"

: >"${DOCKER_LOG}"
: >"${FAKE_NPM_LOG}"
export OPENCODE_WEB_SKIP_VERSION_CHECK=1
export OPENCODE_WEB_EXPECTED_PLAYWRIGHT_VERSION=1.62.3
output_skip="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_not_contains "$output_skip" "Playwright version mismatch"
build_invocation_skip="$(tr -d '\n' <"${DOCKER_LOG}")"
assert_contains "$build_invocation_skip" "--build-arg PLAYWRIGHT_VERSION=1.62.1"
assert_contains "$build_invocation_skip" "--build-arg OPENCODE_VERSION=2.2.1"
if [ -s "${FAKE_NPM_LOG}" ]; then
  fail "version checks must not query npm when OPENCODE_WEB_SKIP_VERSION_CHECK=1"
fi

: >"${DOCKER_LOG}"
unset OPENCODE_WEB_EXPECTED_PLAYWRIGHT_VERSION
output_skip_fallback="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_not_contains "$output_skip_fallback" "Playwright version mismatch"
build_invocation_skip_fallback="$(tr -d '\n' <"${DOCKER_LOG}")"
assert_contains "$build_invocation_skip_fallback" "--build-arg PLAYWRIGHT_VERSION=1.62.1"

: >"${DOCKER_LOG}"
unset OPENCODE_WEB_EXPECTED_PLAYWRIGHT_VERSION OPENCODE_WEB_SKIP_VERSION_CHECK
export OPENCODE_WEB_AUTO_PULL=0
export FAKE_IMAGE_OPENCODE_VERSION=2.2.1
export FAKE_IMAGE_PLAYWRIGHT_BUILD=1
export FAKE_IMAGE_PLAYWRIGHT_VERSION=1.62.1
export FAKE_IMAGE_WRANGLER_BUILD=1
output_match="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_not_contains "$output_match" "Building runtime image"
if [ -s "${DOCKER_LOG}" ]; then
  fail "matching image metadata must not trigger a rebuild"
fi

printf '%s\n' "PASS: wrapper builds with resolved expected OpenCode version"

# Each invocation selects one scoped registry target and uses it for comparison/build.
export FAKE_REGISTRY_VERSION=2.4.7
: >"$FAKE_NPM_LOG"
: >"$DOCKER_LOG"
output="$("${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_contains "$output" "expected='2.4.7'"
assert_contains "$(cat "$DOCKER_LOG")" "OPENCODE_VERSION=2.4.7"
assert_equals 1 "$(grep -c '^@opencode/cli$' "$FAKE_NPM_LOG")"

for invalid in 3.0.0 2.01.1 2.1.01 2.4.0-beta latest '"2.4.0"' '' '2.4.0 2.5.0'; do
  : >"$DOCKER_LOG"
  if output="$(FAKE_REGISTRY_VERSION="$invalid" "${ROOT_DIR}/.opencode_web_yolo.sh" 2>&1)"; then
    fail "accepted invalid registry version '$invalid'"
  fi
  assert_contains "$output" "unsupported or malformed"
  assert_equals '' "$(cat "$DOCKER_LOG")"
done

export FAKE_REGISTRY_STATUS=1
export FAKE_IMAGE_OPENCODE_VERSION=2.3.9
for skip in 0 1; do
  for rebuild in 0 1; do
    : >"$DOCKER_LOG"
    output="$(OPENCODE_WEB_SKIP_VERSION_CHECK="$skip" OPENCODE_WEB_BUILD_NO_CACHE="$rebuild" "${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
    if [ "$rebuild" = 1 ]; then
      assert_contains "$(cat "$DOCKER_LOG")" 'OPENCODE_VERSION=2.3.9'
    else
      assert_not_contains "$output" 'Building runtime image'
    fi
  done
done
for image in 1.19.5 malformed; do
  : >"$DOCKER_LOG"
  output="$(FAKE_IMAGE_OPENCODE_VERSION="$image" "${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
  assert_contains "$output" 'Unable to resolve'
  assert_contains "$(cat "$DOCKER_LOG")" 'OPENCODE_VERSION=2.2.1'
done
: >"$DOCKER_LOG"
output="$(FAKE_IMAGE_MISSING=1 "${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
assert_contains "$(cat "$DOCKER_LOG")" 'OPENCODE_VERSION=2.2.1'
for skip in 0 1; do
  : >"$DOCKER_LOG"
  : >"$FAKE_NPM_LOG"
  output="$(OPENCODE_WEB_SKIP_VERSION_CHECK="$skip" OPENCODE_WEB_EXPECTED_OPENCODE_VERSION=2.5.1 OPENCODE_WEB_BUILD_NO_CACHE=1 "${ROOT_DIR}/.opencode_web_yolo.sh" --dry-run 2>&1)"
  assert_contains "$(cat "$DOCKER_LOG")" 'OPENCODE_VERSION=2.5.1'
  assert_not_contains "$(cat "$FAKE_NPM_LOG")" '@opencode/cli'
done
