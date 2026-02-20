#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]:-}"
SCRIPT_DIR="$PWD"
if [ -n "$SOURCE_PATH" ] && [ -e "$SOURCE_PATH" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$SOURCE_PATH")" && pwd)"
fi

INSTALL_HOME="${OPENCODE_WEB_INSTALL_HOME:-${HOME}/.opencode_web_yolo}"
BIN_DIR="${OPENCODE_WEB_BIN_DIR:-${HOME}/.local/bin}"
DEFAULT_REPO="laurenceputra/opencode_web_yolo"
DEFAULT_BRANCH="${OPENCODE_WEB_YOLO_BRANCH:-main}"

REQUIRED_FILES=(
  ".opencode_web_yolo.sh"
  ".opencode_web_yolo_config.sh"
  ".opencode_web_yolo.Dockerfile"
  ".opencode_web_yolo_entrypoint.sh"
  ".opencode_web_yolo_completion.bash"
  ".opencode_web_yolo_completion.zsh"
  "install.sh"
  "VERSION"
  "CHANGELOG.md"
  "README.md"
  "TECHNICAL.md"
  "LICENSE"
  "CODEOWNERS"
)

is_stream_input() {
  case "$SOURCE_PATH" in
    ""|"-"|"bash"|"stdin"|/dev/fd/*|/proc/self/fd/*) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_repo_from_origin() {
  local search_dir="$1" origin url

  if ! command -v git >/dev/null 2>&1; then
    return 1
  fi

  if ! origin="$(git -C "$search_dir" remote get-url origin 2>/dev/null)"; then
    return 1
  fi

  url="${origin%.git}"
  case "$url" in
    git@github.com:*)
      printf '%s\n' "${url#git@github.com:}"
      ;;
    https://github.com/*)
      printf '%s\n' "${url#https://github.com/}"
      ;;
    http://github.com/*)
      printf '%s\n' "${url#http://github.com/}"
      ;;
    *)
      return 1
      ;;
  esac
}

has_required_files() {
  local source_dir="$1" required_file

  for required_file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "${source_dir}/${required_file}" ]; then
      return 1
    fi
  done

  return 0
}

download_required_files() {
  local destination_dir="$1" repo="$2" branch="$3" remote_base required_file target_file

  if ! command -v curl >/dev/null 2>&1; then
    printf '%s\n' "[install] ERROR: curl is required to bootstrap install assets." >&2
    exit 1
  fi

  remote_base="https://raw.githubusercontent.com/${repo}/${branch}"
  printf '%s\n' "[install] Fetching install assets from ${repo}@${branch}"

  for required_file in "${REQUIRED_FILES[@]}"; do
    target_file="${destination_dir}/${required_file}"
    mkdir -p "$(dirname "$target_file")"
    if ! curl -fsSL "${remote_base}/${required_file}" -o "$target_file"; then
      printf '%s\n' "[install] ERROR: failed downloading '${required_file}' from ${remote_base}" >&2
      exit 1
    fi
  done
}

SOURCE_DIR="$SCRIPT_DIR"
BOOTSTRAP_DIR=""
cleanup() {
  if [ -n "$BOOTSTRAP_DIR" ] && [ -d "$BOOTSTRAP_DIR" ]; then
    rm -rf "$BOOTSTRAP_DIR"
  fi
}
trap cleanup EXIT

if is_stream_input || ! has_required_files "$SOURCE_DIR"; then
  repo="${OPENCODE_WEB_YOLO_REPO:-}"
  if [ -z "$repo" ]; then
    repo="$(resolve_repo_from_origin "$PWD" || true)"
  fi
  if [ -z "$repo" ]; then
    repo="$DEFAULT_REPO"
  fi

  BOOTSTRAP_DIR="$(mktemp -d)"
  download_required_files "$BOOTSTRAP_DIR" "$repo" "$DEFAULT_BRANCH"
  SOURCE_DIR="$BOOTSTRAP_DIR"
fi

mkdir -p "${INSTALL_HOME}" "${BIN_DIR}"
mkdir -p "${HOME}/.local/share/bash-completion/completions"
mkdir -p "${HOME}/.zsh/completions"

for file in "${REQUIRED_FILES[@]}"; do
  cp "${SOURCE_DIR}/${file}" "${INSTALL_HOME}/${file}"
done

chmod +x "${INSTALL_HOME}/.opencode_web_yolo.sh"
chmod +x "${INSTALL_HOME}/.opencode_web_yolo_entrypoint.sh"
chmod +x "${INSTALL_HOME}/install.sh" || true

ln -sfn "${INSTALL_HOME}/.opencode_web_yolo.sh" "${BIN_DIR}/opencode_web_yolo"

cp "${INSTALL_HOME}/.opencode_web_yolo_completion.bash" \
  "${HOME}/.local/share/bash-completion/completions/opencode_web_yolo"
cp "${INSTALL_HOME}/.opencode_web_yolo_completion.zsh" \
  "${HOME}/.zsh/completions/_opencode_web_yolo"

printf '%s\n' "[install] Installed to ${INSTALL_HOME}"
printf '%s\n' "[install] Command symlink: ${BIN_DIR}/opencode_web_yolo"
printf '%s\n' "[install] Bash completion: ${HOME}/.local/share/bash-completion/completions/opencode_web_yolo"
printf '%s\n' "[install] Zsh completion: ${HOME}/.zsh/completions/_opencode_web_yolo"
printf '%s\n' "[install] If needed, add '${BIN_DIR}' to PATH."
