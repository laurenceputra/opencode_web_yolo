---
name: opencode-web-release
description: Manage release mechanics for opencode_web_yolo. Use when implementing or updating VERSION semantics, auto-update/re-exec logic, image rebuild triggers, install.sh distribution flow, shell completion installation, or changelog/version lifecycle behavior.
---

# Release Scope

Implement release behavior in:
- `VERSION`
- `install.sh`
- `.opencode_web_yolo.sh` (update/version checks)
- `.opencode_web_yolo_completion.bash`
- `.opencode_web_yolo_completion.zsh`
- `CHANGELOG.md`

Use `TECHNICAL.md` for version and update requirements.

# References

Load only the file that matches the current release task:
- Read `references/update-reexec-sequence.md` when changing remote version checks or self-update flow.
- Read `references/rebuild-decision-matrix.md` when changing image rebuild triggers or metadata checks.
- Read `references/install-layout.md` when changing installer paths, managed files, or completions.

# Versioning Rules

- Treat `VERSION` as the single source of wrapper semver.
- Keep release notes aligned with version bumps.
- Keep distributed runtime files version-synchronized.

# Update Workflow

1. Read local `VERSION`.
2. Skip remote checks only when explicit skip flags/env vars are set.
3. Fetch remote `VERSION` from configured repo/branch.
4. When remote is newer, update distributed files atomically.
5. Re-exec wrapper after successful update.

# Image Rebuild Policy

Trigger rebuild when any of these are true:
- local image missing
- wrapper version metadata mismatch
- installed OpenCode version mismatch
- `--pull` or no-cache flags requested

Record version metadata in the image so checks are deterministic.

# Install and Completion

- Install to `~/.opencode_web_yolo` with predictable paths.
- Ensure installed command points to the managed wrapper copy.
- Install/refresh bash and zsh completion scripts idempotently.
- Fail with clear messages on partial installs.

# Done Criteria

Consider release work complete only when:
- update check, update apply, and re-exec flow work end-to-end
- rebuild decisions are reproducible from explicit metadata checks
- install/completion paths are consistent across reruns
- version bump and changelog discipline are enforced
