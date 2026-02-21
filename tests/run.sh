#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${ROOT_DIR}/tests/test_dry_run.sh"
"${ROOT_DIR}/tests/wrapper-dryrun.sh"
"${ROOT_DIR}/tests/test_launch_mode_flags.sh"
"${ROOT_DIR}/tests/test_health.sh"
"${ROOT_DIR}/tests/test_entrypoint_auth_guard.sh"
"${ROOT_DIR}/tests/test_entrypoint_home_pin.sh"
"${ROOT_DIR}/tests/test_docs_apache_endpoints.sh"
"${ROOT_DIR}/tests/test_help.sh"
"${ROOT_DIR}/tests/test_auth_required.sh"
"${ROOT_DIR}/tests/test_sensitive_mounts.sh"
"${ROOT_DIR}/tests/test_spec_ignore.sh"
"${ROOT_DIR}/tests/test_source_of_truth_refs.sh"
"${ROOT_DIR}/tests/test_install_bootstrap.sh"
"${ROOT_DIR}/tests/test_docs_install_flow.sh"
"${ROOT_DIR}/tests/test_docs_required_sections.sh"
"${ROOT_DIR}/tests/test_technical_required_sections.sh"

printf '%s\n' "All tests passed."
