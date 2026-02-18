---
name: opencode-web-quality-docs
description: Own quality gates and operator documentation for opencode_web_yolo. Use when building or updating tests, CI checks, shell lint/syntax validation, dry-run verification, security-focused acceptance checks, README quickstart/proxy guidance, TECHNICAL architecture notes, or troubleshooting docs.
---

# Quality and Docs Scope

Implement quality and docs in:
- `tests/`
- `.github/workflows/ci.yml`
- `README.md`
- `TECHNICAL.md`

Follow acceptance criteria in `TECHNICAL.md`.

# References

Load only the file needed for the current task:
- Read `references/test-acceptance-matrix.md` when adding/updating tests tied to plan acceptance criteria.
- Read `references/ci-job-outline.md` when editing `.github/workflows/ci.yml`.
- Read `references/docs-coverage-checklist.md` when writing or reviewing README/TECHNICAL docs.

# Test and CI Baseline

Ensure CI validates at least:
- shell syntax checks (`bash -n`)
- shell linting (`shellcheck`)
- Docker build success
- dry-run output assertions
- required auth failure when password is missing
- package availability checks (`gh`, `git`, `ssh`) in image
- config/data mount contract checks for persistence behavior
- guard checks for version format and runtime-file/version drift

Prefer deterministic shell tests with clear failure messages.

# Documentation Baseline

Document these operator-critical topics:
- quickstart and install flow
- mandatory password requirement
- reverse proxy examples for Nginx and Apache
- event-stream/SSE-safe Apache guidance and websocket notes where relevant
- TLS termination guidance
- persistence model for OpenCode config and data directories
- explicit security notes for `-gh` and `--mount-ssh`
- troubleshooting and diagnostics usage

Keep docs implementation-accurate; update docs in the same change as behavior.

# Review Checklist

Before closing quality/docs work:
- verify every required CLI flag has test coverage or documented rationale
- verify examples reflect current defaults (port, bind address, auth vars)
- verify docs warn about sensitive mount choices
- verify CI fails fast on contract regressions
