# Test Acceptance Matrix

Use this matrix when authoring tests under `tests/`.

## Required Acceptance Coverage

- Shell syntax validation (`bash -n`) for wrapper scripts.
- Dry-run output includes:
  - local-only port mapping
  - `opencode serve` command
  - expected env variables
  - OpenCode config mount
  - OpenCode data mount
  - explicit `HOME`, `XDG_CONFIG_HOME`, and `XDG_DATA_HOME` env contract when user mapping is enabled
- Password enforcement fails when `OPENCODE_SERVER_PASSWORD` is missing/empty.
- Image contains `gh`, `git`, `ssh`, `sqlite3`, and `timeout` binaries; `opencode serve --help` succeeds.
- Docker build asserts Node major 22 and records version metadata; missing, legacy, mismatched,
  malformed, and non-22 metadata force a `--pull` rebuild even with `--no-pull`, while matching metadata reuses the image.
- A missing image and wrapper release drift force `--pull`; OpenCode, Playwright, and Wrangler
  drift do not override an explicit `--no-pull`.
- Generated config is a mode-0600 override-only commented template and stale release-owned settings are ignored.
- `-gh` validates host `gh` install/auth and applies gh mount behavior.
- `--mount-ssh` warns and mounts only on explicit request.
- `--wrangler` requires an existing host `.wrangler` directory, warns about read-write Cloudflare credential exposure, mounts the exact `:rw` path only when requested, and remains absent by default.
- Startup path remains functional when `-gh` and/or `--mount-ssh` are enabled (no read-only mount ownership failures).
- Provider state persists across restart when config/data mount contracts are present.
- Persistence assertions verify state files are written to mounted host path, not only any in-container path.
- Docs contract check ensures Apache stream endpoints include `/event` and `/global/event`, and excludes stale `/session/event`.
- Health/diagnostics command reports key prerequisites and failures clearly.
- Startup VACUUM tests cover existing and missing databases, custom XDG data paths, mapped-user execution, the 5000 ms SQLite busy timeout, TERM at 300 seconds with KILL escalation 5 seconds later, warning-and-continue failures, and no manual WAL/SHM/journal sidecar mutation.
- Retention accepts both flag forms, honors config/flag precedence, rejects invalid values, and propagates dry-run state.
- Retention tests cover cutoff/pagination/root filtering, active-session skips, serial deletion, API incompatibility/failure, marker success/failure/retry, and scheduler signal/exit behavior.
- Retention tests cover complete cross-directory hierarchy mapping, active descendants/unknown IDs, stale root refreshes, status changes before deletion, DELETE-true-but-still-present direct-GET verification, request timeout, supported-version gating, future markers, invalid poll intervals, exact query/cursor use, and malformed responses.

## Test Design Rules

- Prefer deterministic shell tests over timing-sensitive integration flows.
- Assert exact contract strings for security-critical behavior.
- Keep fixtures minimal and avoid network reliance unless unavoidable.
