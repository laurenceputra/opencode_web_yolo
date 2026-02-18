#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! git -C "${ROOT_DIR}" check-ignore -q .spec/; then
  printf '%s\n' "FAIL: .spec/ is not ignored by git" >&2
  exit 1
fi

if git -C "${ROOT_DIR}" ls-files .spec 2>/dev/null | grep -q '.'; then
  printf '%s\n' "FAIL: .spec/ files are tracked" >&2
  exit 1
fi

printf '%s\n' "PASS: .spec/ ignored"
