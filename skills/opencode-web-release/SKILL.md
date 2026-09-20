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

1. Read local `VERSION` and validate the complete managed install.
2. Skip remote checks only when explicit skip flags/env vars are set.
3. Fetch remote `VERSION` from configured repo/branch.
4. When remote is newer, or when required files are missing at an equal version, stage and validate one branch archive before atomically promoting distributed files.
5. Re-exec wrapper after successful update, with a guard against update loops.

# Image Rebuild Policy

Trigger rebuild when any of these are true:
- local image missing
- wrapper version metadata mismatch
- installed OpenCode version mismatch
- missing/malformed/non-22 Node metadata; compatibility/version-driven rebuilds force Docker `--pull`
- `--pull` or no-cache flags requested

Record version metadata in the image so checks are deterministic.

# Install and Completion

- Install to `~/.opencode_web_yolo` with predictable paths.
- Ensure installed command points to the managed wrapper copy.
- Ship every runtime helper used by the Dockerfile (including the retention supervisor and worker) through both bootstrap installation and self-update managed-file manifests/lists.
- Use the tracked `.opencode_web_yolo.manifest` for the complete release asset set. Bootstrap and self-update fetch one GitHub branch archive snapshot and validate every listed non-empty file before promotion, while retaining a compatibility fallback for historical wrappers that predate newly added assets.
- Install/refresh bash and zsh completion scripts idempotently.
- Fail with clear messages on partial installs.

# Done Criteria

Consider release work complete only when:
- update check, update apply, and re-exec flow work end-to-end
- rebuild decisions are reproducible from explicit metadata checks
- install/completion paths are consistent across reruns
- version bump and changelog discipline are enforced
