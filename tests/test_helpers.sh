#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf '%s\n' "FAIL: $*" >&2
  exit 1
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  if [ "$actual" != "$expected" ]; then
    fail "expected '${expected}', got '${actual}'"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null 2>&1; then
    fail "expected output to contain: ${needle}"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null 2>&1; then
    fail "did not expect output to contain: ${needle}"
  fi
}

assert_file_executable() {
  local path="$1"
  if [ ! -x "$path" ]; then
    fail "expected file to be executable: ${path}"
  fi
}

managed_wrapper_files() {
  cat <<'EOF'
.opencode_web_yolo.sh
.opencode_web_yolo_config.sh
.opencode_web_yolo.Dockerfile
.opencode_web_yolo_entrypoint.sh
.opencode_web_yolo_completion.bash
.opencode_web_yolo_completion.zsh
install.sh
VERSION
CHANGELOG.md
README.md
TECHNICAL.md
EOF
}

create_managed_install_home() {
  local root_dir="$1"
  local install_home="$2"
  local managed_file

  mkdir -p "$install_home"
  while IFS= read -r managed_file; do
    mkdir -p "$(dirname "${install_home}/${managed_file}")"
    cp "${root_dir}/${managed_file}" "${install_home}/${managed_file}"
  done < <(managed_wrapper_files)

  chmod +x "${install_home}/.opencode_web_yolo.sh"
  chmod +x "${install_home}/.opencode_web_yolo_entrypoint.sh"
  chmod +x "${install_home}/install.sh"
}

setup_fake_docker() {
  local fake_bin_dir="$1"
  local wrapper_version="$2"
  mkdir -p "$fake_bin_dir"
  cat >"${fake_bin_dir}/docker" <<EOF
#!/usr/bin/env bash
set -euo pipefail
case "\$1" in
  info)
    exit 0
    ;;
  image)
    shift
    if [ "\${1:-}" = "inspect" ]; then
      exit 0
    fi
    ;;
  run)
    if printf '%s ' "\$@" | grep -F "/opt/opencode-web-yolo-version" >/dev/null 2>&1; then
      printf '%s\n' "${wrapper_version}"
      exit 0
    fi
    if printf '%s ' "\$@" | grep -F "/opt/opencode-version" >/dev/null 2>&1; then
      printf '%s\n' "1.2.6"
      exit 0
    fi
    exit 0
    ;;
  build)
    exit 0
    ;;
esac
exit 0
EOF
  chmod +x "${fake_bin_dir}/docker"
}

setup_fake_curl() {
  local fake_bin_dir="$1"
  mkdir -p "$fake_bin_dir"
  cat >"${fake_bin_dir}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ] || [ "$1" != "-fsSL" ]; then
  printf '%s\n' "unexpected curl args: $*" >&2
  exit 1
fi

url="$2"
file_name="${url##*/}"
remote_dir="${OPENCODE_WEB_TEST_REMOTE_DIR:-}"
log_file="${OPENCODE_WEB_TEST_CURL_LOG:-}"

if [ -n "$log_file" ]; then
  printf '%s\n' "$url" >>"$log_file"
fi

if [ -z "$remote_dir" ]; then
  printf '%s\n' "missing OPENCODE_WEB_TEST_REMOTE_DIR" >&2
  exit 1
fi

if [ "${OPENCODE_WEB_TEST_CURL_FAIL_ON:-}" = "$file_name" ]; then
  printf '%s\n' "simulated curl failure for ${file_name}" >&2
  exit 1
fi

if [ ! -f "${remote_dir}/${file_name}" ]; then
  printf '%s\n' "missing test remote file: ${file_name}" >&2
  exit 1
fi

if [ "$#" -eq 2 ]; then
  cat "${remote_dir}/${file_name}"
  exit 0
fi

if [ "$#" -eq 4 ] && [ "$3" = "-o" ]; then
  cp "${remote_dir}/${file_name}" "$4"
  exit 0
fi

printf '%s\n' "unexpected curl args: $*" >&2
exit 1
EOF
  chmod +x "${fake_bin_dir}/curl"
}
