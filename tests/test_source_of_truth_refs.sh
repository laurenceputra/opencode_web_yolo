#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if rg -n "\\.spec/plan\\.md" "${ROOT_DIR}" >/dev/null 2>&1; then
  printf '%s\n' "FAIL: found references to .spec/plan.md" >&2
  rg -n "\\.spec/plan\\.md" "${ROOT_DIR}" || true
  exit 1
fi

printf '%s\n' "PASS: no .spec/plan.md references"
