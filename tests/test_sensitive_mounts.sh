#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
FAKE_BIN="${TMP_DIR}/bin"
WRAPPER_VERSION="$(tr -d '[:space:]' <"${ROOT_DIR}/VERSION")"

setup_fake_docker "$FAKE_BIN" "$WRAPPER_VERSION"

cat >"${FAKE_BIN}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "auth" ] && [ "${2:-}" = "status" ]; then
  if [ "${GH_AUTH_FAIL:-0}" = "1" ]; then
    exit 1
  fi
  exit 0
fi
exit 0
EOF
chmod +x "${FAKE_BIN}/gh"

export PATH="${FAKE_BIN}:${PATH}"
export HOME="${TMP_DIR}/home"
mkdir -p "${HOME}/.config/gh" "${HOME}/.ssh"
printf '%s\n' "[user]" >"${HOME}/.gitconfig"
export OPENCODE_WEB_DRY_RUN=1
export OPENCODE_WEB_SKIP_UPDATE_CHECK=1
export OPENCODE_WEB_SKIP_VERSION_CHECK=1
export OPENCODE_SERVER_PASSWORD="secret"

output_gh="$("${ROOT_DIR}/.opencode_web_yolo.sh" -gh 2>&1)"
assert_contains "$output_gh" "WARNING: Mounting host GitHub CLI auth/config into the container"
assert_contains "$output_gh" ".config/gh:ro"

set +e
output_gh_fail="$(GH_AUTH_FAIL=1 "${ROOT_DIR}/.opencode_web_yolo.sh" -gh 2>&1)"
status=$?
set -e
if [ "$status" -eq 0 ]; then
  fail "expected -gh to fail when gh auth is unavailable"
fi
assert_contains "$output_gh_fail" "requires authenticated GitHub CLI on host"

output_ssh="$("${ROOT_DIR}/.opencode_web_yolo.sh" --mount-ssh 2>&1)"
assert_contains "$output_ssh" "WARNING: Mounting host SSH keys into container as read-only"
assert_contains "$output_ssh" ".ssh:ro"
assert_contains "$output_ssh" ".gitconfig:/home/opencode/.gitconfig:ro"
assert_contains "$output_ssh" "-e GIT_CONFIG_GLOBAL=/home/opencode/.gitconfig"

output_default="$("${ROOT_DIR}/.opencode_web_yolo.sh" 2>&1)"
assert_not_contains "$output_default" ".gitconfig:/home/opencode/.gitconfig:ro"
assert_not_contains "$output_default" "-e GIT_CONFIG_GLOBAL=/home/opencode/.gitconfig"

printf '%s\n' "PASS: sensitive mount behavior"
