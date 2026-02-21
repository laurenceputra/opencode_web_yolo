#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash "${ROOT_DIR}/tests/test_dry_run.sh"
bash "${ROOT_DIR}/tests/wrapper-dryrun.sh"
bash "${ROOT_DIR}/tests/test_launch_mode_flags.sh"
bash "${ROOT_DIR}/tests/test_container_replace.sh"
bash "${ROOT_DIR}/tests/test_health.sh"
bash "${ROOT_DIR}/tests/test_entrypoint_auth_guard.sh"
bash "${ROOT_DIR}/tests/test_entrypoint_home_pin.sh"
bash "${ROOT_DIR}/tests/test_entrypoint_instruction_flag.sh"
bash "${ROOT_DIR}/tests/test_docs_apache_endpoints.sh"
bash "${ROOT_DIR}/tests/test_help.sh"
bash "${ROOT_DIR}/tests/test_auth_required.sh"
bash "${ROOT_DIR}/tests/test_sensitive_mounts.sh"
bash "${ROOT_DIR}/tests/test_spec_ignore.sh"
bash "${ROOT_DIR}/tests/test_source_of_truth_refs.sh"
bash "${ROOT_DIR}/tests/test_install_bootstrap.sh"
bash "${ROOT_DIR}/tests/test_docs_install_flow.sh"
bash "${ROOT_DIR}/tests/test_docs_required_sections.sh"
bash "${ROOT_DIR}/tests/test_technical_required_sections.sh"

printf '%s\n' "All tests passed."
