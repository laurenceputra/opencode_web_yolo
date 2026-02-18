#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_HOME="${OPENCODE_WEB_INSTALL_HOME:-${HOME}/.opencode_web_yolo}"
BIN_DIR="${OPENCODE_WEB_BIN_DIR:-${HOME}/.local/bin}"

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

for file in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "${SCRIPT_DIR}/${file}" ]; then
    printf '%s\n' "[install] ERROR: missing required file '${file}' in ${SCRIPT_DIR}" >&2
    exit 1
  fi
done

mkdir -p "${INSTALL_HOME}" "${BIN_DIR}"
mkdir -p "${HOME}/.local/share/bash-completion/completions"
mkdir -p "${HOME}/.zsh/completions"

for file in "${REQUIRED_FILES[@]}"; do
  cp "${SCRIPT_DIR}/${file}" "${INSTALL_HOME}/${file}"
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
