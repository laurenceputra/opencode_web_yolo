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
- Generated config is a mode-0600 override-only commented template; persistent `OPENCODE_WEB_AUTO_PULL=0`
  is honored for compatible image reuse while missing/legacy/malformed/non-22 Node metadata still
  forces Docker `--pull`.
- `-gh` validates host `gh` install/auth and applies gh mount behavior.
- `--mount-ssh` warns and mounts only on explicit request.
- `--wrangler` requires an existing host `.wrangler` directory, warns about read-write Cloudflare credential exposure, mounts the exact `:rw` path only when requested, and remains absent by default.
- Startup path remains functional when `-gh` and/or `--mount-ssh` are enabled (no read-only mount ownership failures).
- Provider state persists across restart when config/data mount contracts are present.
- Persistence assertions verify state files are written to mounted host path, not only any in-container path.
- Docs contract check ensures Apache streams `/api/event` and websocket `/api/pty`, and excludes stale `/session/event`.
- OpenCode 2.x acceptance must include real-image UI/assets, protected `/api/info`
  auth, SSE, and session create/read across container recreation with host state.
  Real-image retention must test preview/no marker, recursive eligible/archived
  deletion, young descendant and queued preservation, marker persistence and
  recreation in both baseline/latest stable-2 lanes using APIs/clock override,
  never raw SQLite fixtures. Custom username fails; positive retention is enabled.
- Health/diagnostics command reports key prerequisites and failures clearly.
- Startup VACUUM tests cover existing and missing databases, custom XDG data paths, mapped-user execution, the 5000 ms SQLite busy timeout, the configurable positive `OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS` TERM deadline bounded to `2147483647` (default 300) with fixed KILL escalation 5 seconds later, concise ordinary-failure warnings, timeout-expiry warnings containing the effective TERM deadline, and no manual WAL/SHM/journal sidecar mutation.
- Retention accepts both flag forms, honors config/flag precedence, rejects invalid values, and propagates dry-run state.
- Retention tests cover cutoff/pagination/root filtering, active-session skips, serial deletion, API incompatibility/failure, marker success/failure/retry, and scheduler signal/exit behavior.
- Retention tests cover complete cross-location hierarchy mapping, young descendants, active/queued descendants and unknown IDs, migration deferral, refresh changes, DELETE-204-but-root/child-still-present verification, timeouts, stable-2 gating, future markers, invalid polls, unfiltered listing/opaque cursor loops and malformed responses. Document background blind spots and non-atomic TOCTOU.

## Test Design Rules

- Real-package cursor regression: cover string cursors on nonempty pages followed by an empty page with explicit null previous/next, plus absent fields, null fields on nonempty pages, and rejected empty/nonstrings. Use `OPENCODE_TEST_CLI` with the isolated real retention acceptance harness when Docker is unavailable; keep Docker CI lanes for entrypoint/ownership verification.
- Deterministically simulate an old child becoming recent between pre-delete pages and moving ahead of the cursor: a valid refreshed listing omits it, but no DELETE or marker is allowed. Also cover direct-member refresh becoming recent, mismatched identity/linkage/location, missing direct responses, newly accumulated descendants and final inbox/active ordering after direct age checks.
- Execute the runbook copy commands against top-level symlink roots and assert
  trial writes cannot mutate live/backup files. Verify installed runbook availability.
- Migration acceptance must read real pinned v1 session/message state before
  cloning, wait on v2 migration completion and exact content/config/dummy-auth
  assertions, recreate v2, and prove v1 restore from untouched pre-v2 state.
- Bound browser locator/navigation waits and the overall acceptance process.

- Prefer deterministic shell tests over timing-sensitive integration flows.
- Assert exact contract strings for security-critical behavior.
- Keep fixtures minimal and avoid network reliance unless unavoidable.
