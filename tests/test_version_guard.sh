#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

init_repo() {
  local repo_dir="$1"

  mkdir -p "${repo_dir}/tests"
  cp "${ROOT_DIR}/tests/version_guard.sh" "${repo_dir}/tests/version_guard.sh"
  chmod +x "${repo_dir}/tests/version_guard.sh"
  git -C "$repo_dir" init -q
  git -C "$repo_dir" config user.email test@example.invalid
  git -C "$repo_dir" config user.name "Version Guard Test"
}

commit_all() {
  local repo_dir="$1"
  local message="$2"

  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -q -m "$message"
}

normal_repo="${TMP_DIR}/normal"
init_repo "$normal_repo"
printf '%s\n' '0.2.1' >"${normal_repo}/VERSION"
printf '%s\n' 'runtime before' >"${normal_repo}/.opencode_web_yolo.sh"
commit_all "$normal_repo" "base"
printf '%s\n' 'runtime after' >"${normal_repo}/.opencode_web_yolo.sh"
commit_all "$normal_repo" "runtime change"

if normal_output="$(${normal_repo}/tests/version_guard.sh 2>&1)"; then
  fail "normal runtime change without VERSION bump must fail"
fi
assert_contains "$normal_output" "Runtime/release files changed but VERSION was not updated."

merge_repo="${TMP_DIR}/merge"
init_repo "$merge_repo"
printf '%s\n' '0.2.1' >"${merge_repo}/VERSION"
printf '%s\n' 'runtime before' >"${merge_repo}/.opencode_web_yolo.sh"
printf '%s\n' 'installer before' >"${merge_repo}/install.sh"
commit_all "$merge_repo" "base"
base_commit="$(git -C "$merge_repo" rev-parse HEAD)"

git -C "$merge_repo" checkout -q -b release
printf '%s\n' '0.3.0' >"${merge_repo}/VERSION"
commit_all "$merge_repo" "aggregate release version"

git -C "$merge_repo" checkout -q -b runtime "$base_commit"
printf '%s\n' '0.2.2' >"${merge_repo}/VERSION"
printf '%s\n' 'installer after' >"${merge_repo}/install.sh"
commit_all "$merge_repo" "runtime release changes"

git -C "$merge_repo" checkout -q release
if git -C "$merge_repo" merge --no-ff runtime -m "merge release changes" >/dev/null 2>&1; then
  fail "test topology must require VERSION conflict resolution"
fi
printf '%s\n' '0.3.0' >"${merge_repo}/VERSION"
git -C "$merge_repo" add VERSION
git -C "$merge_repo" commit -q -m "merge release changes"

merge_output="$(${merge_repo}/tests/version_guard.sh 2>&1)"
assert_contains "$merge_output" "Runtime/release files changed and VERSION was updated."

shallow_repo="${TMP_DIR}/shallow"
git clone -q --depth 1 --branch release "file://${merge_repo}" "$shallow_repo"
shallow_output="$(${shallow_repo}/tests/version_guard.sh 2>&1)"
assert_contains "$shallow_output" "Parent commit history unavailable; skipping runtime-file/version drift check."

printf '%s\n' "PASS: version guard handles normal and merge commits"
