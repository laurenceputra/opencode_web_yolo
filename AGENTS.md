# opencode_web_yolo Agent Guide

This file defines how agents should execute work in this repository.

## Source of Truth

- Treat `TECHNICAL.md` as the primary implementation contract.
- `AGENTS.md` contains the agent workflow rules and spec structure.
- Skills live under `skills/`; each skill has `SKILL.md` and optional references.
- Follow the four project skills under `skills/` for task-specific workflow:
  - `opencode-web-runtime`
  - `opencode-web-release`
  - `opencode-web-quality-docs`
  - `spec-writer`

## Skill Routing

Use the minimal skill set needed for the task.

### Use `$opencode-web-runtime` for:
- `.opencode_web_yolo.sh`
- `.opencode_web_yolo.Dockerfile`
- `.opencode_web_yolo_entrypoint.sh`
- `.opencode_web_yolo_config.sh`
- wrapper flag parsing, auth gating, mount behavior, diagnostics, dry-run parity

Load references only as needed:
- `skills/opencode-web-runtime/references/runtime-checklist.md`
- `skills/opencode-web-runtime/references/flag-contracts.md`
- `skills/opencode-web-runtime/references/mounts-and-security.md`

### Use `$opencode-web-release` for:
- `VERSION`
- `install.sh`
- `.opencode_web_yolo_completion.bash`
- `.opencode_web_yolo_completion.zsh`
- wrapper update/re-exec and rebuild logic
- `CHANGELOG.md`

Load references only as needed:
- `skills/opencode-web-release/references/update-reexec-sequence.md`
- `skills/opencode-web-release/references/rebuild-decision-matrix.md`
- `skills/opencode-web-release/references/install-layout.md`

### Use `$opencode-web-quality-docs` for:
- `tests/`
- `.github/workflows/ci.yml`
- `README.md`
- `TECHNICAL.md`

### Use `$spec-writer` for:
- authoring or updating specs
- surfacing spec gaps and open decisions

Load references only as needed:
- `skills/opencode-web-quality-docs/references/test-acceptance-matrix.md`
- `skills/opencode-web-quality-docs/references/ci-job-outline.md`
- `skills/opencode-web-quality-docs/references/docs-coverage-checklist.md`

## Non-Negotiable Product Contracts

Do not merge changes that violate any of the following:

1. Authentication is always required.
   - `OPENCODE_SERVER_PASSWORD` must be set and non-empty.
   - No localhost bypass.
2. Default Docker publish is local-only.
   - `-p 127.0.0.1:${PORT}:${PORT}`.
3. Runtime image includes `gh`, `git`, and SSH client binaries.
4. `-gh` exists and validates host GitHub CLI/auth before mounting host gh config.
5. `--mount-ssh` is explicit, read-only, and warning-backed.
6. Wrapper launch path runs OpenCode Web with configured host/port contract.
7. OpenCode config and OpenCode data state persist to host across container restarts.
8. Entrypoint ownership setup must not fail when read-only sensitive mounts are enabled.

## Working Workflow

1. Read `TECHNICAL.md` and any related `docs/` contracts relevant to the task.
2. Load the matching skill `SKILL.md` and only required `references/` file(s).
3. Implement the smallest reliable change that satisfies the contract.
4. Validate locally with targeted checks.
5. Update docs/tests/version artifacts when behavior changes.

## Spec Authoring Rules

- Specs must live in tracked docs under `docs/`.
- `.spec/` is not tracked; do not reference it as a required contract.
- Every spec must include:
  - Objective
  - Non-negotiables
  - Scope of changes
  - Files to change/add
  - Test and validation plan
  - Acceptance criteria
  - Out of scope
  - Open decisions and spec gaps

## Decision Logging

- Record resolved decisions in the relevant spec or in `docs/decisions/`.
- When a decision impacts operators, update `README.md`.
- When a decision impacts implementation contracts, update `TECHNICAL.md`.

## Workflow Discipline

- Make the smallest reliable change that satisfies the contract.
- Do not weaken security or persistence guarantees.
- Update tests and docs in the same change when behavior changes.
- Avoid implicit secrets or credential mounts.

## File Touch Hygiene

- Prefer focused patches over broad refactors.
- Do not edit unrelated files.
- Keep shell scripts shellcheck-friendly.

## Minimum Validation Before Completion

- `bash -n` for shell scripts touched.
- `shellcheck` for shell scripts touched (when available).
- Docker build check when Dockerfile/entrypoint/runtime changes.
- Dry-run output verification for wrapper argument/mount/auth changes.
- Password-required failure-path check for startup gating changes.
- Tests/CI updates for new flags or behavior.

## Documentation and Release Discipline

- Keep `README.md` and `TECHNICAL.md` aligned with real behavior and defaults.
- Include Nginx and Apache reverse proxy examples in README when doc scope is touched.
- Ensure Apache examples include event-stream/SSE-safe directives (not only websocket headers).
- Keep `VERSION` and `CHANGELOG.md` synchronized for release-impacting changes.
- Keep update/rebuild rules deterministic and metadata-driven.

## Scope and Change Hygiene

- Prefer focused patches over broad refactors.
- Do not weaken security warnings or mount explicitness.
- Do not add implicit secret mounts.
- If behavior changes, update tests/docs in the same change.

## Regression Discipline

- For each production issue, add the fix plus:
  - a skill/reference contract update,
  - at least one deterministic test/CI assertion,
  - and matching README/TECHNICAL guidance where operator behavior changes.
- Do not close incident follow-up work until all three artifacts land in the same change.
- Treat persistence, proxy streaming, and read-only mount safety as first-class regression classes.
- For persistence incidents, require proof that runtime write-path equals mounted host path under effective runtime user/home/XDG settings.
