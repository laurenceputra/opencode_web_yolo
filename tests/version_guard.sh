#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' VERSION; then
  printf '%s\n' "VERSION must follow semver format X.Y.Z" >&2
  exit 1
fi

if ! parent_refs="$(git show -s --format=%P HEAD 2>/dev/null)"; then
  printf '%s\n' "Unable to inspect HEAD parents; cannot verify runtime-file/version drift." >&2
  exit 1
fi

first_parent="${parent_refs%% *}"
version_guard_base_ref="${VERSION_GUARD_BASE_REF:-}"

if [ -z "$first_parent" ]; then
  shallow_file="$(git rev-parse --git-path shallow 2>/dev/null || true)"
  head_commit="$(git rev-parse HEAD 2>/dev/null || true)"
  if [ -f "$shallow_file" ] && grep -Fqx "$head_commit" "$shallow_file"; then
    printf '%s\n' "Parent commit history unavailable; cannot verify runtime-file/version drift. Fetch complete history (for example, use checkout fetch-depth: 0)." >&2
    exit 1
  fi
  if [ -z "$version_guard_base_ref" ]; then
    printf '%s\n' "No parent commit found; skipping runtime-file/version drift check."
    exit 0
  fi
else
  if ! git cat-file -e "${first_parent}^{commit}" >/dev/null 2>&1; then
    printf '%s\n' "Parent commit history unavailable; cannot verify runtime-file/version drift. Fetch complete history (for example, use checkout fetch-depth: 0)." >&2
    exit 1
  fi
fi

if [ -n "$version_guard_base_ref" ]; then
  if ! git cat-file -e "${version_guard_base_ref}^{commit}" >/dev/null 2>&1; then
    printf '%s\n' "Requested VERSION_GUARD_BASE_REF '${version_guard_base_ref}' is unavailable; cannot verify runtime-file/version drift. Fetch complete history (for example, use checkout fetch-depth: 0)." >&2
    exit 1
  fi
  comparison_base="$version_guard_base_ref"
else
  # Without an explicit PR base, compare merge commits against their first parent.
  comparison_base="$first_parent"
fi

changed_runtime="$(git diff --name-only "$comparison_base" HEAD -- \
  .opencode_web_yolo.manifest \
  .opencode_web_yolo.sh \
  .opencode_web_yolo_config.sh \
  .opencode_web_yolo.Dockerfile \
  .opencode_web_yolo_entrypoint.sh \
  .opencode_web_yolo_runtime.sh \
  .opencode_web_yolo_retention.js \
  install.sh \
  .opencode_web_yolo_completion.bash \
  .opencode_web_yolo_completion.zsh)"

if [ -z "$changed_runtime" ]; then
  printf '%s\n' "No runtime/release files changed."
  exit 0
fi

if git diff --name-only "$comparison_base" HEAD -- VERSION | grep -q '^VERSION$'; then
  printf '%s\n' "Runtime/release files changed and VERSION was updated."
  exit 0
fi

printf '%s\n' "Runtime/release files changed but VERSION was not updated." >&2
printf '%s\n' "Changed files:" >&2
printf '%s\n' "$changed_runtime" >&2
exit 1
