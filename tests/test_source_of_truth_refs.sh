#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pattern="\\.spec/pla[n]\\.md"

if rg -n "$pattern" "${ROOT_DIR}" >/dev/null 2>&1; then
  printf '%s\n' "FAIL: found references to legacy .spec plan path" >&2
  rg -n "$pattern" "${ROOT_DIR}" || true
  exit 1
fi

printf '%s\n' "PASS: no legacy .spec plan path references"
