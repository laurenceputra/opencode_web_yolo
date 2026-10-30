#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

home_dir="${work_dir}/home"
install_home="${work_dir}/install-home"
bin_dir="${work_dir}/bin"
fake_bin="${work_dir}/fake-bin"
remote_dir="${work_dir}/remote"
install_log="${work_dir}/install.log"

mkdir -p "$home_dir" "$fake_bin" "$remote_dir"

mapfile -t required_files <"${ROOT_DIR}/.opencode_web_yolo.manifest"

for required_file in "${required_files[@]}"; do
  cp "${ROOT_DIR}/${required_file}" "${remote_dir}/${required_file}"
done

cat >"${fake_bin}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 4 ] || [ "$1" != "-fsSL" ] || [ "$3" != "-o" ]; then
  printf '%s\n' "unexpected curl args: $*" >&2
  exit 1
fi

url="$2"
remote_dir="${OPENCODE_WEB_TEST_REMOTE_DIR:?}"

if [[ "$url" == https://github.com/*/archive/refs/heads/*.tar.gz ]]; then
  destination="$4"
  archive_dir="$(mktemp -d)"
  mkdir -p "${archive_dir}/release-root"
  while IFS= read -r archive_file; do
    mkdir -p "$(dirname "${archive_dir}/release-root/${archive_file}")"
    cp -p "${remote_dir}/${archive_file}" "${archive_dir}/release-root/${archive_file}"
  done <"${remote_dir}/.opencode_web_yolo.manifest"
  case "${OPENCODE_WEB_TEST_ARCHIVE_MODE:-}" in
    traversal)
      mkdir -p "${archive_dir}/outside"
      printf '%s\n' traversal >"${archive_dir}/outside/escape"
      tar -czf "$destination" -C "$archive_dir" --transform='s#^outside/escape#release-root/../escape#' release-root outside/escape
      ;;
    multi-root)
      mkdir -p "${archive_dir}/other-root"
      printf '%s\n' second-root >"${archive_dir}/other-root/extra"
      tar -czf "$destination" -C "$archive_dir" release-root other-root
      ;;
    symlink)
      ln -s VERSION "${archive_dir}/release-root/unsafe-link"
      tar -czf "$destination" -C "$archive_dir" release-root
      ;;
    hardlink)
      ln "${archive_dir}/release-root/VERSION" "${archive_dir}/release-root/unsafe-hardlink"
      tar -czf "$destination" -C "$archive_dir" release-root
      ;;
    duplicate-manifest)
      printf '%s\n' ".opencode_web_yolo_runtime.sh" >>"${archive_dir}/release-root/.opencode_web_yolo.manifest"
      tar -czf "$destination" -C "$archive_dir" release-root
      ;;
    *)
      tar -czf "$destination" -C "$archive_dir" release-root
      ;;
  esac
  rm -rf "$archive_dir"
  exit 0
fi

file_name="${url##*/}"

if [ ! -f "${remote_dir}/${file_name}" ]; then
  printf '%s\n' "missing test remote file: ${file_name}" >&2
  exit 1
fi

cp "${remote_dir}/${file_name}" "${destination}"
EOF
chmod +x "${fake_bin}/curl"

PATH="${fake_bin}:${PATH}" \
HOME="$home_dir" \
OPENCODE_WEB_INSTALL_HOME="$install_home" \
OPENCODE_WEB_BIN_DIR="$bin_dir" \
OPENCODE_WEB_YOLO_REPO="example/repo" \
OPENCODE_WEB_YOLO_BRANCH="main" \
OPENCODE_WEB_TEST_REMOTE_DIR="$remote_dir" \
bash <"${ROOT_DIR}/install.sh" >"$install_log" 2>&1

if [ ! -L "${bin_dir}/opencode_web_yolo" ]; then
  fail "expected opencode_web_yolo symlink to be installed"
fi

if [ "$(readlink "${bin_dir}/opencode_web_yolo")" != "${install_home}/.opencode_web_yolo.sh" ]; then
  fail "opencode_web_yolo symlink target mismatch"
fi

for required_file in "${required_files[@]}"; do
  if [ ! -f "${install_home}/${required_file}" ]; then
    fail "expected installed file missing: ${required_file}"
  fi
done

if ! grep -F "[install] Fetching install assets from example/repo@main" "$install_log" >/dev/null 2>&1; then
  fail "expected bootstrap fetch log line"
fi

mkdir -p "${home_dir}/.opencode_web_yolo"
printf '%s\n' 'export OPENCODE_WEB_BASE_IMAGE=node:20-slim' >"${home_dir}/.opencode_web_yolo/config"
chmod 600 "${home_dir}/.opencode_web_yolo/config"
PATH="${fake_bin}:${PATH}" \
  HOME="$home_dir" \
  OPENCODE_WEB_INSTALL_HOME="$install_home" \
  OPENCODE_WEB_BIN_DIR="$bin_dir" \
  OPENCODE_WEB_YOLO_REPO="example/repo" \
  OPENCODE_WEB_YOLO_BRANCH="main" \
  OPENCODE_WEB_TEST_REMOTE_DIR="$remote_dir" \
  bash <"${ROOT_DIR}/install.sh" >/dev/null 2>&1
assert_contains "$(cat "${home_dir}/.opencode_web_yolo/config")" "OPENCODE_WEB_BASE_IMAGE=node:20-slim"
assert_equals 600 "$(stat -c '%a' "${home_dir}/.opencode_web_yolo/config")"

for archive_mode in traversal symlink hardlink multi-root duplicate-manifest; do
  bad_install_home="${work_dir}/bad-${archive_mode}"
  rm -rf "$bad_install_home"
  set +e
  PATH="${fake_bin}:${PATH}" \
    HOME="$home_dir" \
    OPENCODE_WEB_INSTALL_HOME="$bad_install_home" \
    OPENCODE_WEB_BIN_DIR="${bin_dir}" \
    OPENCODE_WEB_YOLO_REPO="example/repo" \
    OPENCODE_WEB_YOLO_BRANCH="main" \
    OPENCODE_WEB_TEST_REMOTE_DIR="$remote_dir" \
    OPENCODE_WEB_TEST_ARCHIVE_MODE="$archive_mode" \
    bash <"${ROOT_DIR}/install.sh" >"${install_log}" 2>&1
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    fail "expected bootstrap ${archive_mode} archive rejection"
  fi
  if [ -e "${bad_install_home}/VERSION" ]; then
    fail "rejected bootstrap ${archive_mode} archive must not install VERSION"
  fi
done

printf '%s\n' "PASS: streamed install bootstrap"
