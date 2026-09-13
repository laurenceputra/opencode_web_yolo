#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' VERSION; then
  printf '%s\n' "VERSION must follow semver format X.Y.Z" >&2
  exit 1
fi

head_object="$(git cat-file -p HEAD 2>/dev/null || true)"
parent_refs=""
while IFS= read -r line; do
  case "$line" in
    parent\ *) parent_refs="${parent_refs}${line#parent } " ;;
  esac
done <<<"$head_object"
parent_refs="${parent_refs% }"
first_parent="${parent_refs%% *}"

if [ -z "$first_parent" ]; then
  printf '%s\n' "No parent commit found; skipping runtime-file/version drift check."
  exit 0
fi

if ! git cat-file -e "${first_parent}^{commit}" >/dev/null 2>&1; then
  printf '%s\n' "Parent commit history unavailable; skipping runtime-file/version drift check."
  exit 0
fi

comparison_base="$first_parent"
if [[ "$parent_refs" == *" "* ]]; then
  second_parent="${parent_refs#* }"
  second_parent="${second_parent%% *}"

  if ! git cat-file -e "${second_parent}^{commit}" >/dev/null 2>&1; then
    printf '%s\n' "Merge parent history unavailable; skipping runtime-file/version drift check."
    exit 0
  fi

  if ! comparison_base="$(git merge-base "$first_parent" "$second_parent" 2>/dev/null)" || [ -z "$comparison_base" ]; then
    printf '%s\n' "Merge base unavailable; skipping runtime-file/version drift check."
    exit 0
  fi
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
