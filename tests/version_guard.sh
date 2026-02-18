#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' VERSION; then
  printf '%s\n' "VERSION must follow semver format X.Y.Z" >&2
  exit 1
fi

if ! git rev-parse --verify HEAD^ >/dev/null 2>&1; then
  printf '%s\n' "No parent commit found; skipping runtime-file/version drift check."
  exit 0
fi

changed_runtime="$(git diff --name-only HEAD^ HEAD -- \
  .opencode_web_yolo.sh \
  .opencode_web_yolo_config.sh \
  .opencode_web_yolo.Dockerfile \
  .opencode_web_yolo_entrypoint.sh \
  install.sh \
  .opencode_web_yolo_completion.bash \
  .opencode_web_yolo_completion.zsh || true)"

if [ -z "$changed_runtime" ]; then
  printf '%s\n' "No runtime/release files changed."
  exit 0
fi

if git diff --name-only HEAD^ HEAD -- VERSION | grep -q '^VERSION$'; then
  printf '%s\n' "Runtime/release files changed and VERSION was updated."
  exit 0
fi

printf '%s\n' "Runtime/release files changed but VERSION was not updated." >&2
printf '%s\n' "Changed files:" >&2
printf '%s\n' "$changed_runtime" >&2
exit 1

