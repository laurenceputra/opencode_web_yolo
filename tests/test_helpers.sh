#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf '%s\n' "FAIL: $*" >&2
  exit 1
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

