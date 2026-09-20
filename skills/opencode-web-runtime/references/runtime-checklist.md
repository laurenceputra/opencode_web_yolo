# Runtime Checklist

Use this checklist for runtime changes in `.opencode_web_yolo.sh`, `.opencode_web_yolo.Dockerfile`, and `.opencode_web_yolo_entrypoint.sh`.

## Wrapper Behavior

- Parse wrapper flags before pass-through args.
- Keep pass-through args unchanged after `--`.
- Gate container startup on required auth checks.
- Keep dry-run output faithful to the real docker invocation.
- Include effective retention days/dry-run state and marker path in dry-run and health output.
- Keep diagnostics callable without launching the app container.
- Ensure dry-run and diagnostics include both OpenCode config and OpenCode data mount contracts.

## Runtime Security Contracts

- Require non-empty `OPENCODE_SERVER_PASSWORD` on every run.
- Keep default port publish local-only (`127.0.0.1` binding).
- Keep auth mandatory even for localhost access.
- Do not add implicit secret mounts.
- Print warnings before enabling `-gh` or `--mount-ssh`.

## Container Runtime Contracts

- Install `gh`, `git`, `ssh` client binaries in image.
- Keep entrypoint UID/GID mapping aligned to host user.
- Ensure mapped user has writable home/config/data/workspace paths.
- If runtime process user differs from image default user, explicitly pin `HOME`, `XDG_CONFIG_HOME`, and `XDG_DATA_HOME` to mounted persistence paths.
- Avoid recursive ownership operations on paths that can contain read-only mounts.
- Use `gosu` handoff for final command execution.
- Run `opencode serve` with configured host and port.
- Provide `sqlite3` and Debian coreutils `timeout` in the image and, after mapped-user ownership plus HOME/XDG exports, best-effort VACUUM an existing `${XDG_DATA_HOME}/opencode/opencode.db` as the mapped user via `gosu` with a 5000 ms busy timeout. GNU `timeout` must send TERM after 300 seconds and KILL 5 seconds later if needed. Missing databases must not be created; failures or timeout expiry warn and do not block direct or retention-supervised launch.
- Preserve provider/auth state across restart by mounting host OpenCode data directory.
- Keep Playwright opt-in: `OPENCODE_WEB_BUILD_PLAYWRIGHT=1` in the persistent config is durable, while `--playwright` is one-shot.
- Retention is opt-in with non-negative `OPENCODE_WEB_RETENTION_DAYS`; its scheduler starts only after authenticated health, runs as the mapped user, and persists a success marker under `XDG_STATE_HOME`.
- Retention must use authenticated complete `/experimental/session` pagination, `/session/status` for every involved directory, direct `/session/:id` refresh/verification, and serial `DELETE /session/:id` calls; validate compatibility and fail closed without raw SQL/WAL/SHM mutation.
- Startup VACUUM is separate from retention: retention remains an API-only, no-raw-SQL worker and must not manually touch SQLite WAL/SHM/journal sidecars.
- Map every listed session to a root across directories; block a mapped root when status reports a busy/retrying descendant, fail closed on unmapped active IDs or malformed hierarchies, refresh/recheck immediately before each delete, verify direct 404 before marker advancement, and reject unsafe equal-timestamp page boundaries. The API has no atomic delete-if-idle guarantee.
- Validate positive worker fetch and scheduler poll timeouts; use `tini -s -g` for PID1 subreaping/group signal forwarding and preserve SIGINT semantics.
- When enabled, resolve the current global `@playwright/test` version unless checks are skipped (then use the release fallback), run its `playwright install --with-deps chromium`, and use `PLAYWRIGHT_BROWSERS_PATH=/ms-playwright`.
- Record installed/expected Playwright versions and rebuild when enabled-image metadata drifts.
- Build from fixed `node:22-slim`, assert Node major 22 during the image build, and record
  installed Node version/major metadata under `/opt` for compatibility rebuild decisions.
- Normalize accepted truthy build toggles to canonical `0`/`1` before Docker arguments and metadata comparisons; version-check skip suppresses lookup/drift comparison while retaining release-selected Playwright build behavior.

## Exit Criteria

- Wrapper, Dockerfile, and entrypoint behavior all match `TECHNICAL.md`.
- Security checks fail fast with clear, actionable messages.
- Dry-run and normal-run command assembly are equivalent.
