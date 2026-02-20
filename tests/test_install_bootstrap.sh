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

required_files=(
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
destination="$4"
file_name="${url##*/}"
remote_dir="${OPENCODE_WEB_TEST_REMOTE_DIR:?}"

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
bash <"${ROOT_DIR}/install.sh" >"$install_log"

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

printf '%s\n' "PASS: streamed install bootstrap"
