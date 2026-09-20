---
name: opencode-web-runtime
description: Build and maintain the runtime layer for opencode_web_yolo. Use when implementing or changing wrapper CLI behavior, Docker image/runtime entrypoint, mandatory authentication checks, workspace/config/data mounts, -gh integration, --mount-ssh behavior, dry-run output, or health/diagnostics commands.
---

# Runtime Scope

Implement runtime behavior in:
- `.opencode_web_yolo.sh`
- `.opencode_web_yolo.Dockerfile`
- `.opencode_web_yolo_entrypoint.sh`
- `.opencode_web_yolo_config.sh` (if used)

Follow `TECHNICAL.md` as the source of truth.

# References

Load only the file that matches the active task:
- Read `references/runtime-checklist.md` when implementing or reviewing end-to-end runtime behavior.
- Read `references/flag-contracts.md` when adding/changing CLI flags or pass-through parsing.
- Read `references/mounts-and-security.md` when touching mounts, auth checks, or warning text.

# Required Contracts

Enforce these contracts on every runtime change:
- Require `OPENCODE_SERVER_PASSWORD`; fail fast when empty or unset.
- Publish local-only by default: `-p 127.0.0.1:${OPENCODE_WEB_PORT}:${OPENCODE_WEB_PORT}`.
- Run `opencode serve` with host `0.0.0.0` and configured port unless explicitly overridden.
- Install and expose `gh`, `git`, SSH client binaries, and `sqlite3` inside the image.
- Persist both OpenCode config and state directories across restarts.
- Build the release-owned `node:22-slim` runtime, assert Node major 22, and record Node
  metadata for deterministic legacy-image rebuilds.
- Show explicit warnings before enabling sensitive mounts (`-gh`, `--mount-ssh`).
- Keep entrypoint ownership setup compatible with read-only sensitive mounts.

# Implementation Workflow

1. Parse wrapper flags first, then separate pass-through args cleanly.
2. Validate security prerequisites before composing docker run args.
3. Assemble mounts in explicit groups:
   - default workspace/config/data mounts
   - optional git config mount
   - optional `-gh` mounts
   - optional `--mount-ssh` mount
4. Emit identical run args for normal run and dry-run previews.
5. Keep diagnostics independent of container startup.
6. In entrypoint, map UID/GID, ensure writable runtime dirs, avoid recursive chown on read-only mounts, then exec via `gosu`.
7. After ownership and HOME/XDG exports, inspect `${XDG_DATA_HOME}/opencode/opencode.db`. If present, run startup `VACUUM;` via `sqlite3` and `gosu` as the mapped user with a 5000 ms busy timeout; GNU `timeout` sends TERM after 300 seconds and KILL 5 seconds later if needed. Skip missing databases without creating them and warn/continue on failures or timeout expiry. This is separate from retention's no-raw-SQL worker guarantee.

# Retention lifecycle

- For enabled retention, start the scheduler only after authenticated `/global/health` succeeds; forward TERM/INT, stop it with the app, and return the app status.
- Run retention as the mapped user and persist its success marker under `XDG_STATE_HOME`; do not use a restart-resetting sleep schedule.
- Use OpenCode's authenticated experimental global session listing and delete endpoint, serially, with strict response validation and fail-closed behavior. Never mutate SQLite directly.
- Install/use `tini` as PID 1 with subreaping and process-group signal forwarding; do not remap SIGINT to TERM in the supervisor.
- Bound every retention worker fetch, gate on a tested healthy OpenCode 1.18.x version, re-check active status before each deletion, and verify deletion disappearance before advancing state.

# Guardrails

- Do not relax auth requirements for localhost usage.
- Do not mount host credentials implicitly.
- Keep mount warnings concrete and actionable.
- Keep shell logic POSIX/Bash-safe and shellcheck-friendly.

# Done Criteria

Consider runtime work complete only when:
- Password checks, local-only port publishing, and `opencode serve` launch command match the plan.
- `-gh` verifies host `gh` presence and auth status before mounting.
- `--mount-ssh` mounts read-only and warns clearly.
- OpenCode state persists across restarts without re-authentication churn, and existing databases receive best-effort startup VACUUM maintenance with TERM/KILL timeout escalation.
- Dry-run and diagnostics reflect actual runtime behavior.
