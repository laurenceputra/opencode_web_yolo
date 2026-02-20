#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
. "${ROOT_DIR}/tests/test_helpers.sh"

readme="$(cat "${ROOT_DIR}/README.md")"
technical="$(cat "${ROOT_DIR}/TECHNICAL.md")"

assert_contains "$readme" "Install directly from GitHub (this already runs the installer):"
assert_contains "$readme" "curl -fsSL https://raw.githubusercontent.com/laurenceputra/opencode_web_yolo/main/install.sh | bash"
if [[ "$readme" == *$'Then run:\n\n```bash\n./install.sh'* ]]; then
  fail "curl quickstart must not require ./install.sh"
fi
assert_contains "$readme" "Install from a local clone instead:"

assert_contains "$technical" "## Installation Contract"
assert_contains "$technical" "repo-local install (\`./install.sh\`)"
assert_contains "$technical" "streamed/bootstrap install"

printf '%s\n' "PASS: docs install flow contract"
