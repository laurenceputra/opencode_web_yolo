# Weekly OpenCode Session Retention

## Objective

Optionally remove inactive OpenCode root sessions older than a configured number
of days while preserving projects, accounts, provider authentication, and
configuration. Cleanup must run safely inside the existing mapped-user runtime.

## Non-negotiables

- `--retention-days N` and `--retention-days=N` accept only non-negative
  integers; `OPENCODE_WEB_RETENTION_DAYS` is the durable setting and defaults to
  `0` (disabled). A flag wins for that invocation.
- Cleanup uses authenticated OpenCode HTTP APIs, not SQL or direct SQLite/WAL/SHM
  mutation. Deletion is serial and uses OpenCode's recursive deletion behavior.
- Only old root sessions are candidates. The complete global hierarchy is mapped
  to root ancestors across directories; sessions reported `busy` or `retry`
  block their mapped candidate root, while unmapped active IDs and malformed
  hierarchies fail closed.
- Cleanup starts only after health succeeds, runs as the mapped user, and writes
  a persistent success marker under `XDG_STATE_HOME` only after a full success.
- The scheduler has no cron dependency, runs at most once per seven days, retries
  failures, forwards TERM/INT through `tini -s -g`, stops with the app, and
  returns the app status.
- Titles, prompts, messages, and parts are never logged.

## Scope of changes

- Add a Node-based authenticated retention worker for the OpenCode 1.18.25
  experimental complete global session listing, hierarchy mapping, status lookup,
  pagination, direct refresh/verification, and deletion.
- Add a small shell supervisor and connect it to the existing entrypoint.
- Gate the worker on healthy OpenCode `1.18.x`, bound every fetch, directly
  refresh each candidate root and require it to remain old/root, reload the
  hierarchy and activity before deletion, and verify direct 404/not-found after
  DELETE before marking success.
- Add wrapper parsing, configuration, dry-run/health visibility, completions,
  image/install assets, tests, contracts, and operator documentation.

## Files to change/add

- `.opencode_web_yolo.sh`, `.opencode_web_yolo_config.sh`
- `.opencode_web_yolo_entrypoint.sh`, `.opencode_web_yolo_runtime.sh`
- `.opencode_web_yolo_retention.js`, `.opencode_web_yolo.Dockerfile`
- `install.sh`, shell completions, `tests/`
- `README.md`, `TECHNICAL.md`, runtime/quality skills and references
- `docs/specs/weekly-session-retention.md`, `VERSION`, `CHANGELOG.md`

## Test and validation plan

- Shell syntax and shellcheck for every changed shell script.
- Deterministic wrapper tests for defaults, both flag forms, precedence,
  validation, dry-run propagation, health output, installation, and assets.
- A local HTTP mock for pagination, cutoff selection, complete cross-directory
  hierarchy mapping, stale refreshes, active skips including descendants, status
  races, serial deletion, direct-404 verification, dry-run, API failure/timeout/
  version gating, and marker semantics.
- Lifecycle assertions for health gating, signal forwarding, scheduler stop, and
  app exit status; run the complete `tests/run.sh` suite.
- Build the Docker image and verify helper assets when Docker is available.

## Acceptance criteria

- Disabled retention preserves the existing direct app launch path.
- Enabled retention runs after authenticated health, immediately when no valid
  marker exists, and no more than weekly after success.
- A failed or preview run never advances the marker; a later scheduler pass can
  retry a failed run.
- The worker follows `x-next-cursor`, validates the complete session hierarchy,
  status/delete responses, and health version, and never intentionally deletes
  a refreshed active/recent/non-root session.
- A DELETE response is not trusted alone: the direct GET must return 404/not-found
  within a bounded verification period before success is recorded.
- The wrapper refreshes and rechecks immediately before deletion, but the API has
  no atomic delete-if-idle operation; a residual status-to-delete race remains
  possible and OpenCode cancellation/deletion behavior is the final guard.
- OpenCode's delete endpoint is the only mutation path and receives the session's
  directory for correct instance routing.
- Dry-run and health output expose effective retention settings and marker state.
- README, TECHNICAL, contracts, release metadata, completions, installer, and
  Docker assets describe and ship the same behavior.

## Out of scope

- Cron/systemd integration, retention of projects/accounts/provider credentials,
  browser-local UI state, or changing OpenCode itself.
- Raw database repair, WAL checkpointing, bulk/concurrent deletion, or title/content
  reporting.

## Open decisions and spec gaps

- The global session API is experimental and may change. **Resolved default:**
  require the documented 1.18.25 response shapes and fail closed with an
  actionable error when they do.
- A session can become active between status lookup and deletion. **Resolved
  default:** directly refresh the root, reload the complete hierarchy, recheck
  all involved-directory statuses immediately before each serial deletion, and
  rely on OpenCode's own authenticated cancellation/deletion behavior as the
  final guard. The API has no atomic delete-if-idle operation, so residual race
  risk cannot be eliminated; uncertain failures leave the marker unchanged for
  retry.
- A preview is not a successful cleanup. **Resolved default:** return success for
  a preview but do not write the success marker, so previews cannot suppress a
  real cleanup.
- The global cursor contains only `time.updated`. **Resolved default:** reject a
  full page ending in duplicate timestamps as unsafe; other equal-timestamp
  boundaries remain an upstream completeness limitation and are documented
  rather than presented as guaranteed complete pagination.
- No separate operator ownership or alerting service is defined. **Gap:** logs
  are the current actionable failure signal; deployments needing alerting should
  monitor the container logs and marker age.
