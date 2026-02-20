# Changelog

All notable changes to this project are documented here.

## [0.1.1] - 2026-02-20

- Fixed install flow so `curl -fsSL .../install.sh | bash` bootstraps required runtime files instead of expecting a local checkout.
- Updated Quickstart docs to separate curl-based install from local-clone install and removed redundant `./install.sh` from curl path.
- Added deterministic tests for streamed install bootstrap behavior and docs install contract consistency.

## [0.1.0] - 2026-02-18

- Initial implementation of `opencode_web_yolo` runtime wrapper.
- Added mandatory `OPENCODE_SERVER_PASSWORD` auth gate and local-only Docker publish default.
- Added `-gh` and `--mount-ssh` sensitive mount flows with explicit warnings.
- Added Docker runtime image and entrypoint with `gh`, `git`, and SSH client binaries.
- Added installer, completions, docs, tests, and CI workflow.
