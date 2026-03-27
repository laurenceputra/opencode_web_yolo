#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export HOME="${TMP_DIR}/home"
mkdir -p "${HOME}"
export OPENCODE_WEB_SKIP_UPDATE_CHECK=1

copy_fixture_file() {
  local fixture_root="$1"
  local rel_path="$2"

  mkdir -p "$(dirname "${fixture_root}/${rel_path}")"
  cp "${ROOT_DIR}/${rel_path}" "${fixture_root}/${rel_path}"
}

create_roadmap_fixture() {
  local fixture_root="$1"
  local rel_path

  mkdir -p "${fixture_root}"

  for rel_path in \
    .opencode_web_yolo.sh \
    .opencode_web_yolo_config.sh \
    .opencode_web_yolo_completion.bash \
    .opencode_web_yolo_completion.zsh \
    VERSION \
    CHANGELOG.md \
    README.md \
    TECHNICAL.md \
    docs/roadmap-entropy-detector.md \
    tests/test_help.sh \
    tests/test_roadmap_entropy.sh \
    tests/run.sh \
    .github/workflows/ci.yml \
    skills/opencode-web-runtime/references/flag-contracts.md
  do
    copy_fixture_file "${fixture_root}" "${rel_path}"
  done

  chmod +x "${fixture_root}/.opencode_web_yolo.sh"
}

clean_fixture="${TMP_DIR}/clean-fixture"
create_roadmap_fixture "${clean_fixture}"

output="$(
  cd "${clean_fixture}/docs"
  "${clean_fixture}/.opencode_web_yolo.sh" check-roadmap 2>&1
)"
assert_contains "$output" "opencode_web_yolo roadmap entropy report"
assert_contains "$output" "spec=docs/roadmap-entropy-detector.md"
assert_contains "$output" "status=ok"
assert_contains "$output" "checks="
assert_contains "$output" "PASS: roadmap entropy contract is aligned"

alias_output="$(
  cd "${clean_fixture}"
  "${clean_fixture}/.opencode_web_yolo.sh" roadmap-entropy 2>&1
)"
assert_contains "$alias_output" "status=ok"
assert_contains "$alias_output" "PASS: roadmap entropy contract is aligned"

failing_fixture="${TMP_DIR}/failing-fixture"
cp -R "${clean_fixture}/." "${failing_fixture}"
cat >"${failing_fixture}/.opencode_web_yolo_completion.bash" <<'EOF'
_opencode_web_yolo_completion() {
  local cur
  cur="${COMP_WORDS[COMP_CWORD]}"

  local opts
  opts="--pull --no-pull --detach -d --foreground -f --mount-ssh -gh --gh --health diagnostics health config --version version --verbose -v --help -h help --"

  COMPREPLY=($(compgen -W "${opts}" -- "${cur}"))
}

complete -F _opencode_web_yolo_completion opencode_web_yolo
EOF

set +e
failure_output="$(
  cd "${failing_fixture}"
  "${failing_fixture}/.opencode_web_yolo.sh" check-roadmap 2>&1
)"
status=$?
set -e

assert_equals "1" "${status}"
assert_contains "$failure_output" "status=drift"
assert_contains "$failure_output" "expected '.opencode_web_yolo_completion.bash' to contain 'check-roadmap roadmap-entropy'"

printf '%s\n' "PASS: roadmap entropy detector"
