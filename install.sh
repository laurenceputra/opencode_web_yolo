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

fallback_required_files() {
  cat <<'EOF'
.opencode_web_yolo.manifest
.opencode_web_yolo.sh
.opencode_web_yolo_config.sh
.opencode_web_yolo.Dockerfile
.opencode_web_yolo_entrypoint.sh
.opencode_web_yolo_runtime.sh
.opencode_web_yolo_retention.js
.opencode_web_yolo_completion.bash
.opencode_web_yolo_completion.zsh
install.sh
VERSION
CHANGELOG.md
README.md
TECHNICAL.md
LICENSE
CODEOWNERS
EOF
}

manifest_has_canonical_files() {
  local manifest_file="$1" canonical_file manifest_entry
  local seen_manifest_file

  [ -f "$manifest_file" ] || return 1
  [ -s "$manifest_file" ] || return 1
  seen_manifest_file="$(mktemp "${TMPDIR:-/tmp}/opencode_web_yolo-manifest.XXXXXX")" || return 1
  while IFS= read -r manifest_entry || [ -n "$manifest_entry" ]; do
    [ -n "$manifest_entry" ] || continue
    case "$manifest_entry" in
      *[!A-Za-z0-9._-]*) rm -f "$seen_manifest_file"; return 1 ;;
    esac
    if grep -Fqx -- "$manifest_entry" "$seen_manifest_file"; then
      rm -f "$seen_manifest_file"
      return 1
    fi
    if ! printf '%s\n' "$manifest_entry" >>"$seen_manifest_file"; then
      rm -f "$seen_manifest_file"
      return 1
    fi
  done <"$manifest_file"
  while IFS= read -r canonical_file; do
    if ! grep -Fqx -- "$canonical_file" "$manifest_file"; then
      rm -f "$seen_manifest_file"
      return 1
    fi
  done < <(fallback_required_files)
  rm -f "$seen_manifest_file"
}

load_required_files() {
  local source_dir="$1" manifest_file

  manifest_file="${source_dir}/.opencode_web_yolo.manifest"

  REQUIRED_FILES=()
  if manifest_has_canonical_files "$manifest_file"; then
    while IFS= read -r required_file || [ -n "$required_file" ]; do
      [ -n "$required_file" ] || continue
      REQUIRED_FILES+=("$required_file")
    done <"$manifest_file"
  else
    while IFS= read -r required_file; do
      REQUIRED_FILES+=("$required_file")
    done < <(fallback_required_files)
  fi
}

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
  local source_dir="$1" required_file required_path version

  load_required_files "$source_dir"
  if [ -e "${source_dir}/.opencode_web_yolo.manifest" ] && ! manifest_has_canonical_files "${source_dir}/.opencode_web_yolo.manifest"; then
    return 1
  fi
  for required_file in "${REQUIRED_FILES[@]}"; do
    required_path="${source_dir}/${required_file}"
    if [ ! -f "$required_path" ] || [ -L "$required_path" ] || [ ! -s "$required_path" ]; then
      return 1
    fi
    case "$required_file" in
      *.sh|*.bash) bash -n "$required_path" >/dev/null 2>&1 || return 1 ;;
    esac
  done

  version="$(tr -d '[:space:]' <"${source_dir}/VERSION")"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1

  return 0
}

url_encode_branch() {
  local branch="$1" encoded="" character byte index

  for ((index = 0; index < ${#branch}; index++)); do
    character="${branch:index:1}"
    case "$character" in
      [A-Za-z0-9._~-]|/) encoded+="$character" ;;
      *)
        printf -v byte '%02X' "'${character}"
        encoded+="%${byte}"
        ;;
    esac
  done
  printf '%s\n' "$encoded"
}

validate_archive_path() {
  local path="$1" component remainder

  case "$path" in
    ""|/*|*//* ) return 1 ;;
  esac
  remainder="$path"
  while :; do
    if [[ "$remainder" == */* ]]; then
      component="${remainder%%/*}"
      remainder="${remainder#*/}"
    else
      component="$remainder"
      remainder=""
    fi
    case "$component" in
      ""|.|..) return 1 ;;
    esac
    [ -n "$remainder" ] || break
  done
}

validate_archive_contents() {
  local archive_file="$1" archive_root="" archive_entry relative_entry listing type_char
  local root_directory_seen=0

  if ! tar -tzf "$archive_file" >/dev/null 2>&1 || ! tar -tvzf "$archive_file" >/dev/null 2>&1; then
    return 1
  fi
  while IFS= read -r listing; do
    [ -n "$listing" ] || continue
    type_char="${listing:0:1}"
    case "$type_char" in
      -|d) ;;
      *) return 1 ;;
    esac
  done < <(tar -tvzf "$archive_file")

  while IFS= read -r archive_entry; do
    [ -n "$archive_entry" ] || continue
    case "$archive_entry" in
      */*)
        archive_root="${archive_entry%%/*}"
        break
        ;;
      *) return 1 ;;
    esac
  done < <(tar -tzf "$archive_file")
  validate_archive_path "$archive_root" || return 1
  while IFS= read -r archive_entry; do
    [ -n "$archive_entry" ] || continue
    case "$archive_entry" in
      "${archive_root}/"*)
        relative_entry="${archive_entry#"${archive_root}/"}"
        validate_archive_path "$archive_entry" || return 1
        [ -n "$relative_entry" ] || root_directory_seen=1
        ;;
      *) return 1 ;;
    esac
  done < <(tar -tzf "$archive_file")
  [ "$root_directory_seen" -eq 1 ] || return 1
}

download_release_snapshot() {
  local destination_dir="$1" repo="$2" branch="$3"
  local archive_file extract_dir archive_url

  if ! command -v curl >/dev/null 2>&1; then
    printf '%s\n' "[install] ERROR: curl is required to bootstrap install assets." >&2
    exit 1
  fi
  if ! command -v tar >/dev/null 2>&1; then
    printf '%s\n' "[install] ERROR: tar is required to extract bootstrap release assets." >&2
    exit 1
  fi

  printf '%s\n' "[install] Fetching install assets from ${repo}@${branch}" >&2
  branch="$(url_encode_branch "$branch")"
  archive_url="https://github.com/${repo}/archive/refs/heads/${branch}.tar.gz"
  archive_file="${destination_dir}/release.tar.gz"
  extract_dir="${destination_dir}/release"
  mkdir -p "$extract_dir"
  if ! curl -fsSL "$archive_url" -o "$archive_file"; then
    printf '%s\n' "[install] ERROR: failed downloading release archive from ${archive_url}" >&2
    exit 1
  fi
  if ! validate_archive_contents "$archive_file"; then
    printf '%s\n' "[install] ERROR: downloaded release archive is malformed or truncated" >&2
    exit 1
  fi

  if ! tar -xzf "$archive_file" -C "$extract_dir" --strip-components=1; then
    printf '%s\n' "[install] ERROR: failed extracting release archive" >&2
    exit 1
  fi
  printf '%s\n' "$extract_dir"
}

SOURCE_DIR="$SCRIPT_DIR"
BOOTSTRAP_DIR=""
PROMOTION_DIR=""
cleanup() {
  if [ -n "$BOOTSTRAP_DIR" ] && [ -d "$BOOTSTRAP_DIR" ]; then
    rm -rf "$BOOTSTRAP_DIR"
  fi
  if [ -n "$PROMOTION_DIR" ] && [ -d "$PROMOTION_DIR" ]; then
    rm -rf "$PROMOTION_DIR"
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

  mkdir -p "$(dirname "$INSTALL_HOME")"
  BOOTSTRAP_DIR="$(mktemp -d "${INSTALL_HOME}.bootstrap.XXXXXX")"
  SOURCE_DIR="$(download_release_snapshot "$BOOTSTRAP_DIR" "$repo" "$DEFAULT_BRANCH")"
fi

load_required_files "$SOURCE_DIR"
if ! has_required_files "$SOURCE_DIR"; then
  printf '%s\n' "[install] ERROR: release is incomplete, contains empty managed files, or has invalid shell syntax." >&2
  exit 1
fi

mkdir -p "${INSTALL_HOME}" "${BIN_DIR}"
mkdir -p "${HOME}/.local/share/bash-completion/completions"
mkdir -p "${HOME}/.zsh/completions"

PROMOTION_DIR="$(mktemp -d "${INSTALL_HOME}/.opencode_web_yolo-install.XXXXXX")"
for file in "${REQUIRED_FILES[@]}"; do
  mkdir -p "$(dirname "${PROMOTION_DIR}/${file}")"
  cp -p "${SOURCE_DIR}/${file}" "${PROMOTION_DIR}/${file}"
done

chmod +x "${PROMOTION_DIR}/.opencode_web_yolo.sh"
chmod +x "${PROMOTION_DIR}/.opencode_web_yolo_entrypoint.sh"
chmod +x "${PROMOTION_DIR}/install.sh"

if ! has_required_files "$PROMOTION_DIR"; then
  printf '%s\n' "[install] ERROR: staged release validation failed; existing install was not promoted." >&2
  exit 1
fi

for file in "${REQUIRED_FILES[@]}"; do
  case "$file" in
    .opencode_web_yolo.sh|VERSION) continue ;;
  esac
  mkdir -p "$(dirname "${INSTALL_HOME}/${file}")"
  mv -f "${PROMOTION_DIR}/${file}" "${INSTALL_HOME}/${file}"
done
mv -f "${PROMOTION_DIR}/.opencode_web_yolo.sh" "${INSTALL_HOME}/.opencode_web_yolo.sh"

completion_tmp="$(mktemp "${HOME}/.local/share/bash-completion/completions/.opencode_web_yolo.XXXXXX")"
cp -p "${INSTALL_HOME}/.opencode_web_yolo_completion.bash" "$completion_tmp"
mv -f "$completion_tmp" "${HOME}/.local/share/bash-completion/completions/opencode_web_yolo"
completion_tmp="$(mktemp "${HOME}/.zsh/completions/.opencode_web_yolo.XXXXXX")"
cp -p "${INSTALL_HOME}/.opencode_web_yolo_completion.zsh" "$completion_tmp"
mv -f "$completion_tmp" "${HOME}/.zsh/completions/_opencode_web_yolo"

ln -sfn "${INSTALL_HOME}/.opencode_web_yolo.sh" "${BIN_DIR}/opencode_web_yolo"

# VERSION is deliberately the final managed-file promotion. A retry after an
# interrupted install therefore remains visibly on the previous release.
mv -f "${PROMOTION_DIR}/VERSION" "${INSTALL_HOME}/VERSION"
rm -rf "$PROMOTION_DIR"
PROMOTION_DIR=""

printf '%s\n' "[install] Installed to ${INSTALL_HOME}"
printf '%s\n' "[install] Command symlink: ${BIN_DIR}/opencode_web_yolo"
printf '%s\n' "[install] Bash completion: ${HOME}/.local/share/bash-completion/completions/opencode_web_yolo"
printf '%s\n' "[install] Zsh completion: ${HOME}/.zsh/completions/_opencode_web_yolo"
printf '%s\n' "[install] If needed, add '${BIN_DIR}' to PATH."
