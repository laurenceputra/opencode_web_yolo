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

root_repo="${TMP_DIR}/root"
init_repo "$root_repo"
printf '%s\n' '0.2.1' >"${root_repo}/VERSION"
printf '%s\n' 'runtime' >"${root_repo}/.opencode_web_yolo.sh"
commit_all "$root_repo" "root"
root_output="$("${root_repo}/tests/version_guard.sh" 2>&1)"
assert_contains "$root_output" "No parent commit found; skipping runtime-file/version drift check."

normal_repo="${TMP_DIR}/normal"
init_repo "$normal_repo"
printf '%s\n' '0.2.1' >"${normal_repo}/VERSION"
printf '%s\n' 'runtime before' >"${normal_repo}/.opencode_web_yolo.sh"
commit_all "$normal_repo" "base"
printf '%s\n' 'runtime after' >"${normal_repo}/.opencode_web_yolo.sh"
git -C "$normal_repo" add .
git -C "$normal_repo" commit -q -m $'runtime change\n\nparent this-is-commit-message-content'

if normal_output="$("${normal_repo}/tests/version_guard.sh" 2>&1)"; then
  fail "normal runtime change without VERSION bump must fail"
fi
assert_contains "$normal_output" "Runtime/release files changed but VERSION was not updated."

positive_repo="${TMP_DIR}/positive-merge"
init_repo "$positive_repo"
printf '%s\n' '0.2.1' >"${positive_repo}/VERSION"
printf '%s\n' 'runtime before' >"${positive_repo}/.opencode_web_yolo.sh"
commit_all "$positive_repo" "base"
positive_base_ref="$(git -C "$positive_repo" rev-parse HEAD)"

git -C "$positive_repo" checkout -q -b pr "$positive_base_ref"
printf '%s\n' '0.3.0' >"${positive_repo}/VERSION"
printf '%s\n' 'runtime after' >"${positive_repo}/.opencode_web_yolo.sh"
commit_all "$positive_repo" "PR release changes"
git -C "$positive_repo" checkout -q -b base "$positive_base_ref"
git -C "$positive_repo" merge --no-ff pr -m "synthetic PR merge" >/dev/null 2>&1

positive_output="$(
  VERSION_GUARD_BASE_REF="$positive_base_ref" \
    "${positive_repo}/tests/version_guard.sh" 2>&1
)"
assert_contains "$positive_output" "Runtime/release files changed and VERSION was updated."

masked_repo="${TMP_DIR}/masked-merge"
init_repo "$masked_repo"
printf '%s\n' '0.2.1' >"${masked_repo}/VERSION"
printf '%s\n' 'runtime before' >"${masked_repo}/.opencode_web_yolo.sh"
commit_all "$masked_repo" "base"
masked_original_base_ref="$(git -C "$masked_repo" rev-parse HEAD)"

git -C "$masked_repo" checkout -q -b base "$masked_original_base_ref"
printf '%s\n' '0.3.0' >"${masked_repo}/VERSION"
commit_all "$masked_repo" "base branch version bump"
masked_current_base_ref="$(git -C "$masked_repo" rev-parse HEAD)"

git -C "$masked_repo" checkout -q -b pr "$masked_original_base_ref"
printf '%s\n' 'runtime after' >"${masked_repo}/.opencode_web_yolo.sh"
commit_all "$masked_repo" $'PR runtime change\n\nparent this-is-commit-message-content'
git -C "$masked_repo" checkout -q base
git -C "$masked_repo" merge --no-ff pr -m "synthetic masked PR merge" >/dev/null 2>&1
assert_equals "0.3.0" "$(git -C "$masked_repo" show HEAD:VERSION)"

set +e
masked_output="$(
  VERSION_GUARD_BASE_REF="$masked_current_base_ref" \
    "${masked_repo}/tests/version_guard.sh" 2>&1
)"
masked_status=$?
set -e
assert_equals "1" "$masked_status"
assert_contains "$masked_output" "Runtime/release files changed but VERSION was not updated."

missing_base_ref=0000000000000000000000000000000000000000
set +e
missing_base_output="$(
  VERSION_GUARD_BASE_REF="$missing_base_ref" \
    "${positive_repo}/tests/version_guard.sh" 2>&1
)"
missing_base_status=$?
set -e
assert_equals "1" "$missing_base_status"
assert_contains "$missing_base_output" "Requested VERSION_GUARD_BASE_REF '${missing_base_ref}' is unavailable;"

shallow_repo="${TMP_DIR}/shallow"
git clone -q --depth 2 --branch base "file://${masked_repo}" "$shallow_repo"
set +e
shallow_output="$(
  VERSION_GUARD_BASE_REF="$masked_original_base_ref" \
    "${shallow_repo}/tests/version_guard.sh" 2>&1
)"
shallow_status=$?
set -e
assert_equals "1" "$shallow_status"
assert_contains "$shallow_output" "Requested VERSION_GUARD_BASE_REF '${masked_original_base_ref}' is unavailable;"

printf '%s\n' "PASS: version guard handles normal, PR-base, root, and shallow commits"
