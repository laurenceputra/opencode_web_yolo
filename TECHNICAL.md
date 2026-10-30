# TECHNICAL

## Runtime Architecture

- Host command: `opencode_web_yolo`
- Wrapper builds/validates runtime image and runs:
  - `opencode serve --hostname 0.0.0.0 --port ${OPENCODE_WEB_PORT}`
- Docker publish contract:
  - `-p 127.0.0.1:${OPENCODE_WEB_PORT}:${OPENCODE_WEB_PORT}`
- Container lifecycle defaults:
  - `--name ${OPENCODE_WEB_CONTAINER_NAME:-opencode_web_yolo}`
  - `--restart ${OPENCODE_WEB_RESTART_POLICY:-unless-stopped}`
  - detached launch by default (`OPENCODE_WEB_RUN_DETACHED=1`)
- Build/update defaults:
  - pull-on-start by default (`OPENCODE_WEB_AUTO_PULL=1`)
- Runtime release defaults:
  - fixed Docker base image `node:22-slim`
  - fixed OpenCode npm package `@opencode/cli`, exact tested default `2.2.1`
  - fixed internal serve hostname `0.0.0.0`, runtime home `/home/opencode`, workdir `/workspace`, and cleanup behavior
- Reverse proxy is expected in front of localhost bind.
- Session retention defaults to 0 (disabled); positive days enable automatic best-effort 2.x family cleanup.

## Installation Contract

- `install.sh` supports two valid install flows:
  - repo-local install (`./install.sh`) using sibling managed files from the checkout
  - streamed/bootstrap install (for example `curl -fsSL .../install.sh | bash`) that fetches one branch archive before install
- Bootstrap fetch source defaults:
  - repo: `OPENCODE_WEB_YOLO_REPO` when set
  - repo fallback: current git `origin` in `${PWD}` when available
  - final repo fallback: `laurenceputra/opencode_web_yolo`
  - branch: `OPENCODE_WEB_YOLO_BRANCH` (default `main`)
- Installer always installs managed runtime files into `${OPENCODE_WEB_INSTALL_HOME:-$HOME/.opencode_web_yolo}` and symlinks command to `${OPENCODE_WEB_BIN_DIR:-$HOME/.local/bin}/opencode_web_yolo`.
- `.opencode_web_yolo.manifest` is the tracked release asset manifest. Installer and self-update validate every listed file as a non-empty regular file; shell assets are syntax-checked before promotion.
- Bootstrap and self-update require `curl` and `tar` when an archive is needed. Archive contents are staged on the install filesystem, validated as one snapshot, and promoted with same-filesystem file renames. The wrapper is promoted near-last and `VERSION` last so an interrupted update can be retried without falsely advancing the installed release.
- Archive validation rejects absolute or multi-root paths, any `.`/`..` path component, duplicate manifest entries, and every non-regular/non-directory tar entry (including links, devices, and FIFOs) before extraction.

## Security Model

Non-negotiable runtime checks:
- `OPENCODE_SERVER_PASSWORD` must be set and non-empty before container startup.
- Wrapper and entrypoint set preferred `OPENCODE_PASSWORD` from that required value,
  overriding conflicting inherited values. Username is fixed `opencode`; custom
  `OPENCODE_SERVER_USERNAME` values fail before launch.
- The bundled UI shell/assets are public for sign-in; protected APIs require auth.
  Readiness is authenticated `GET /api/info` with a `version` field, not `/global/health`.
- Localhost is not exempt from password auth.
- Host credentials are never mounted implicitly.

Mount model:
- Default mounts:
  - `${PWD}` -> `/workspace` (rw)
  - `${XDG_CONFIG_HOME:-$HOME/.config}/opencode` -> `${OPENCODE_WEB_YOLO_HOME}/.config/opencode` (rw)
  - `${XDG_DATA_HOME:-$HOME/.local/share}/opencode` -> `${OPENCODE_WEB_YOLO_HOME}/.local/share/opencode` (rw)
- Optional host AGENTS:
  - Selection precedence: `--agents-file` > `OPENCODE_HOST_AGENTS` > `~/.config/opencode/AGENTS.md` > `~/.codex/AGENTS.md` > `~/.copilot/copilot-instructions.md` > `~/.claude/CLAUDE.md`.
  - The selected host file mounts read-only to `${OPENCODE_WEB_YOLO_HOME}/.config/opencode/AGENTS.md`.
  - This normalizes Codex/Copilot/Claude instruction files to OpenCode's global rules path.
  - `--no-host-agents` disables the selected-file mount.
- Runtime env contract:
  - `HOME=${OPENCODE_WEB_YOLO_HOME}`
  - `XDG_CONFIG_HOME=${OPENCODE_WEB_YOLO_HOME}/.config`
  - `XDG_DATA_HOME=${OPENCODE_WEB_YOLO_HOME}/.local/share`
  - `XDG_STATE_HOME=${OPENCODE_WEB_YOLO_HOME}/.local/share/opencode/state`
  - this prevents user-remap drift (for example writes to `/home/ubuntu/...`) and keeps state on mounted host paths
- Persistence scope:
  - server-side OpenCode state (projects/sessions/provider auth/db) persists on mounted host data paths.
  - workspace UI layout state in OpenCode Web is browser-local (`localStorage`) and is not shared across different browsers/profiles.
- Optional `-gh`:
  - Validates host `gh` binary and `gh auth status`.
  - Mounts host gh config/auth (ro) and prints warning.
- Optional `--mount-ssh`:
  - Mounts `${HOME}/.ssh` (ro) only on explicit request and prints warning.
  - Also mounts `${HOME}/.gitconfig` (ro) when present.
  - Exports `GIT_CONFIG_GLOBAL=${OPENCODE_WEB_YOLO_HOME}/.gitconfig` when mounted to avoid home-resolution drift.
- Optional `--wrangler`:
  - Requires `${XDG_CONFIG_HOME:-$HOME/.config}/.wrangler` to exist.
  - Mounts it explicitly read-write to `${OPENCODE_WEB_YOLO_HOME}/.config/.wrangler`.
  - Prints a strong warning because container processes can read, modify, and rotate Cloudflare credentials.
  - Never mounts Wrangler config by default.

## Image Contents and Entrypoint

Docker image includes:
- `gh`
- `git`
- `openssh-client`
- `sqlite3`
- Debian coreutils `timeout`
- runtime helpers (`gosu`, `sudo`, `passwd`, `ca-certificates`)
- PID 1 init/subreaper (`tini`)
- OpenCode CLI (`@opencode/cli@2.2.1` npm package by default)
- when Playwright build is enabled: global `@playwright/test` package/`playwright` CLI and Chromium browser binaries in shared path (`PLAYWRIGHT_BROWSERS_PATH=/ms-playwright`)
- the browser install is executed by that exact installed package, coupling the Chromium revision to the package version used for the image
- the global package is not a substitute for project dependencies: mounted projects should declare `@playwright/test` locally for normal Node.js imports
- when Wrangler build is enabled: global `wrangler@latest` CLI
- Dockerfile layering keeps stable base/apt layers ahead of volatile build args; build args are declared near consuming layers to preserve cache reuse.

Image metadata files:
- `/opt/opencode-web-yolo-version`
- `/opt/opencode-version`
- `/opt/opencode-web-yolo-node-version`
- `/opt/opencode-web-yolo-node-major` (must be `22`)
- `/opt/opencode-web-yolo-playwright`
- `/opt/opencode-web-yolo-playwright-version` (installed package version, or `disabled`)
- `/opt/opencode-web-yolo-playwright-expected-version` (Docker build arg version)
- `/opt/opencode-web-yolo-wrangler`
- `/app/AGENTS.md` (packaged fallback document)
- `/usr/local/bin/opencode_web_yolo_runtime.sh` (app/scheduler supervisor)
- `/usr/local/bin/opencode_web_yolo_retention.js` (authenticated retention worker)

Entrypoint behavior:
- maps runtime user/group to host UID/GID.
- pins runtime passwd home to `${OPENCODE_WEB_YOLO_HOME}` to keep SSH/git home resolution aligned.
- ensures writable home/config/data/workspace paths.
- avoids recursive ownership operations across read-only mount boundaries.
- installs passwordless sudo policy for mapped user.
- executes command via `gosu`.
- after ownership and HOME/XDG setup, checks `${XDG_DATA_HOME}/opencode/opencode.db`; when present, runs `VACUUM;` through `sqlite3` via `gosu` as the mapped user with a 5000 ms busy timeout. `OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS` is a persistent positive integer bounded to `2147483647`, defaults to 300, and controls GNU `timeout`'s TERM deadline; KILL escalation remains fixed at 5 seconds. Missing databases are skipped without creation. Ordinary vacuum failures warn concisely, while timeout-expiry warnings include the effective TERM deadline; neither blocks direct or retention-supervised OpenCode launch. This startup maintenance is separate from retention, whose worker never uses raw SQL or mutates SQLite WAL/SHM files.
- enabled retention executes the supervisor as the mapped user after HOME/XDG setup.
- Docker starts `tini -s -g` so orphaned descendants are reaped and TERM/INT are forwarded to the child process group. The supervisor preserves the received signal when forwarding it to the app.
- does not inject unsupported OpenCode CLI flags for instruction loading.
- relies on OpenCode's native rules discovery (project AGENTS/CLAUDE files and global config-path rules).

## Session Retention

- Wire contracts are sourced from upstream tag `v2.2.1`: `packages/protocol/src/groups/session.ts`, `packages/schema/src/session-inbox.ts`, and `packages/server/src/handlers/session.ts`. The active API explicitly describes process-local foreground drains, not an atomic idle proof.
- `OPENCODE_WEB_RETENTION_DAYS` is a non-negative integer; `0` disables cleanup. `--retention-days N` and `--retention-days=N` override it for one invocation.
- `OPENCODE_WEB_RETENTION_DRY_RUN=1` previews without deleting or advancing state.
- Automatic best-effort cleanup requires no maintenance gate. Authenticated `/api/info` must identify canonical stable 2.x; `/api/experimental/migration/v1` must report `status: completed`. Required/running/error migration defers with no marker. Automatic stable-2 updates remain enabled; response validation fails closed on incompatible APIs.
- The complete listing is `GET /api/session?limit=100` with no archived, parent, directory, project or location filter. Both archive states and every hierarchy level are included. Validate the `data` array and `cursor` object; follow opaque `cursor.next` until absent or null, including a nonempty last page with a next cursor. Both cursor fields may be absent/null; present tokens must be nonempty strings. Published 2.2.1/2.2.2 return `{previous:null,next:null}` on the empty terminal page. Reject malformed cursors, loops, duplicate IDs, missing parents and cycles. Session location is `location.directory`, not legacy `directory`.
- Every member of a candidate root family must have safe-integer epoch-millisecond `time.updated` strictly older than `now - days * 86400000`; equality and young descendants preserve the entire family.
- `/api/session/active` returns `{data: {ID: {type: "running"}}}`. Every ID must map to the complete hierarchy; a running descendant protects its root. `/api/session/:id/inbox` returns `{data: [...]}` of enqueued user/synthetic/compaction/move items with id, sessionID, payload, delivery (queue/steer), and time.created. Any nonempty member inbox protects its root. Unknown/malformed responses fail closed.
- Initially scan inboxes only for age-eligible candidate families; before each serial `DELETE /api/session/:id`, refresh migration, complete hierarchy, family cutoff and all accumulated current-family inboxes. Sample the global active map last and validate every active ID against the complete refreshed hierarchy, including unrelated families; unmapped IDs fail closed. This reduces inbox requests, not the cost of per-candidate global listings. DELETE must return empty HTTP 204. Verify the root and every observed descendant through direct GET 404 polling before advancing state. OpenCode owns recursive deletion and interruption; never mutate raw SQL or WAL/SHM files.
- Retain initial candidate family IDs and accumulate descendants across refreshed listings; never shrink a known family. Every previously observed member must remain accounted for under the same root with unchanged parent linkage/location, otherwise abort/defer the pass without a marker. Before DELETE, directly GET every accumulated member and validate identity, parent linkage, location and current age against the refreshed hierarchy/cutoff. A directly observed recent member preserves the family. Final inbox/active checks follow these direct age checks, and deletion verification covers the accumulated ID set. This guards against an updated child moving ahead of a pagination cursor, but listings/direct reads are still non-atomic and later updates/new children remain a best-effort limitation.
- Every fetch has an `AbortSignal.timeout` deadline (`OPENCODE_WEB_RETENTION_FETCH_TIMEOUT_MS`, default 10000); each member's deletion verification has a bounded timeout (`OPENCODE_WEB_RETENTION_VERIFY_TIMEOUT_MS`, default 10000).
- A successful, non-preview run atomically writes `${XDG_STATE_HOME}/session-retention.last-success`. The marker is persistent because `XDG_STATE_HOME` is within the mounted OpenCode data path. Missing/old markers run immediately/when due; failures leave the marker unchanged for retry.
- The scheduler polls without a cron dependency and stops when OpenCode exits. It never logs session titles or content.
- `OPENCODE_WEB_RETENTION_POLL_SECONDS` is a positive integer with a one-second minimum; the production default is 3600 seconds.
- No atomic guarantee: activity is process-local foreground only, with background-tool/other-process blind spots. A TOCTOU race permits new work/children after checks; DELETE interrupts rather than atomically refusing active families. Keep retention disabled when these best-effort limits are unacceptable.

## Proxy Streaming Notes

- OpenCode browser output uses long-lived event streams.
- OpenCode terminal sessions use websocket connections under `/api/pty` (for example `/api/pty/<id>/connect`), with upstream-issued tickets. Preserve query strings and avoid logging tickets.
- Apache reverse proxy config must treat stream endpoints as SSE-style traffic:
  - `/api/event` must be stream-safe
  - longer proxy timeouts
  - chunked streaming enabled
  - compression disabled on event-stream routes
- Reverse proxies must forward `/api/pty` with websocket upgrade semantics (`ws://` upstream on Apache with `mod_proxy_wstunnel`).
- Websocket proxy rules are optional compatibility paths for non-PTY endpoints, not a replacement for stream-safe SSE handling.

## Update and Re-exec

On run, unless disabled:
- wrapper checks remote `VERSION` from `${OPENCODE_WEB_YOLO_REPO}` and `${OPENCODE_WEB_YOLO_BRANCH}`.
  - default repo: `laurenceputra/opencode_web_yolo`
  - default branch: `main`
- if remote version is newer, the complete source is downloaded from `https://github.com/${repo}/archive/refs/heads/${branch}.tar.gz`, extracted to install-home staging, validated against `.opencode_web_yolo.manifest`, promoted with atomic individual renames, and the wrapper re-execs with original args/environment.
- if the local managed install is incomplete, the same archive repair runs even when local and remote `VERSION` values are equal. A re-exec marker prevents an update loop, and an incomplete or malformed archive fails closed before Docker build.
- `OPENCODE_WEB_UPDATE_REEXECED=1` prevents an update loop. Explicit and inherited safety controls are preserved across the immediate re-exec, and CLI arguments are parsed afterward and remain authoritative. A stale value exported by a historical config may survive that one re-exec because its provenance is unknowable; a fresh invocation ignores the stale config assignment.

Update can be disabled with:
- `OPENCODE_WEB_SKIP_UPDATE_CHECK=1`

## Rebuild Decision Logic

Image rebuild happens when any trigger is true:
- image tag missing locally
- wrapper version metadata mismatch
- OpenCode version metadata mismatch (unless version check disabled)
- Node version metadata missing or not major 22 (compatibility rebuild forces Docker `--pull`)
- Playwright build metadata mismatch
- Playwright package version metadata mismatch when the Playwright build is enabled (unless version check disabled)
- Wrangler build metadata mismatch
- pull/no-cache build flags requested

When `--no-pull` is explicit, the compatibility pull override applies only to a missing image,
wrapper release metadata drift, or missing/malformed/non-22 Node metadata. OpenCode, Playwright,
and Wrangler drift still rebuilds without `--pull`; normal `OPENCODE_WEB_AUTO_PULL` behavior
continues to apply when `--no-pull` is not selected.

OpenCode install target during build:
- resolves `npm view @opencode/cli version` once; only canonical exact stable 2.x
  (no leading zeros, prerelease, build suffix or whitespace) is accepted. Successful
  malformed/unsupported responses fail before build or container replacement.
  The same exact target drives comparison and build; never automatically install 3.x.
- if `OPENCODE_WEB_EXPECTED_OPENCODE_VERSION` is set, it must be an exact stable `2.x.y`.
  Overrides are operator-tested; the release default is the acceptance-tested target.
- Explicit pins bypass lookup. Lookup failures/missing npm warn and retain valid
  exact 2.x image metadata, including during unrelated rebuilds; missing/incompatible
  images use tested baseline 2.2.1, never reuse 1.x metadata. Skipping checks omits
  lookup/drift comparison but preserves compatible image versions for other rebuilds;
  an explicit pin controls the build. Direct Docker default remains 2.2.1 and uses
  the same strict canonical validation. CI matrix tests baseline and latest stable
  2.x on PR, scheduled and manual runs. No compatibility test guarantees rollback
  of migrated data; restore pre-upgrade backups.
- Config/data roots remain unchanged. See [migration runbook](OPENCODE_2_MIGRATION.md)
  for stopped-writer backups, copy-first trials, background/resumable v1 history migration,
  and rollback using restored pre-v2 state (never downgrade mutated data).

Controls:
- `--pull` or `OPENCODE_WEB_BUILD_PULL=1`
- `--playwright` or `OPENCODE_WEB_BUILD_PLAYWRIGHT=1`
- `PLAYWRIGHT_VERSION` is a wrapper-owned Docker build arg (default fallback `1.62.1`); enabled builds resolve the current `@playwright/test` npm version, while skipped checks use that release fallback. User config cannot pin the package version.
- `--wrangler` or `OPENCODE_WEB_BUILD_WRANGLER=1`
- `OPENCODE_WEB_BUILD_NO_CACHE=1`
- `OPENCODE_WEB_AUTO_PULL=1` enables pull-on-start by default and may be set to `0` in the
  persistent wrapper config; missing images, wrapper metadata drift, and invalid/missing/non-22
  Node metadata still force Docker `--pull`.
- `OPENCODE_WEB_SKIP_VERSION_CHECK=1` skips npm lookup and OpenCode/Playwright package-version drift comparisons, but does not disable enabled builds. Pull/no-cache, dry-run, verbose, retention dry-run, and skip-version-check settings are one-shot/troubleshooting controls and are not generated as active config defaults. Truthy build toggles (`true`, `yes`, `on`) are normalized to `0`/`1` before Docker args and metadata comparisons.

## Release Checklist

- Update `VERSION` and `CHANGELOG.md` together.
- Run `bash tests/run.sh`.
- Run `bash -n` and `shellcheck` for touched shell scripts.
- Build the runtime image and verify required binaries (`gh`, `git`, `ssh`, `sqlite3`) plus `opencode serve --help`.
- Verify README/TECHNICAL accuracy for any behavior changes.

## Test and CI Strategy

Tests and CI assert:
- `bash -n` and `shellcheck` on touched shell scripts.
- dry-run output contract (local-only port mapping, `opencode serve` command, env values, config/data mounts, lifecycle flags, detach/pull defaults).
- launch behavior replaces same-name containers by stopping running instances, then removing the old container before re-run.
- password gate behavior when `OPENCODE_SERVER_PASSWORD` is missing.
- `-gh` validation/mount behavior and `--mount-ssh` explicit warning/mount behavior.
- `--wrangler` explicit read-write mount, warning, missing-directory failure, and disabled-by-default behavior.
- health output includes persistence/lifecycle settings.
- health output includes browser-vs-server persistence scope visibility.
- retention configuration, marker path, API schedule, and dry-run state.
- retention API compatibility, active-session skipping, serial deletion, marker retry semantics, and supervisor signal/exit behavior.
- Docker image build and runtime binary presence (`gh`, `git`, `ssh`, `sqlite3`), including a successful `opencode serve --help` check.
- Real-image CI checks public UI/bundled JS, missing/wrong API auth, `/api/info`,
  `/api/event` SSE, and session create/read after container recreation on identical
  host-backed mounts. The Playwright-enabled image also checks browser password
  connection and reload. This does not prove provider/model responses,
  PTY interaction, TLS proxy behavior, or arbitrary historical migration correctness.
- `tests/real_v2_retention.cjs` exercises the same API-only deletion acceptance against the CI image by default, or a published local CLI via `OPENCODE_TEST_CLI=/absolute/path/to/opencode node tests/real_v2_retention.cjs`. Local mode uses isolated HOME/XDG/workspace directories and recreates the server on identical state; it does not prove Docker ownership/entrypoint behavior. Both modes check real terminal cursor responses, preview/no marker, recursive and archived deletion, young/queued preservation and persistent markers.
- Baseline acceptance imports a sanitized user/assistant transcript using the actual
  pinned `opencode-ai@1.19.5` CLI, reads it through v1 APIs, stops writers and clones
  config/data, waits for `/api/experimental/migration/v1` completion on 2.2.1, checks
  exact transcript content plus representative model config and dummy credential
  import, recreates v2, and proves v1 reads the restored pre-v2 copy. This synthetic
  fixture covers one baseline, not arbitrary provider/plugin/history migrations.
- The migration runbook is a flat managed manifest asset, compatible with the
  unmodified 0.5.0 updater's validator; backup regression tests execute its
  exact commands against symlinked top roots, preserving nested symlinks.
- startup VACUUM behavior for existing and missing databases, custom XDG data paths, mapped-user invocation, the configurable bounded TERM timeout plus fixed 5-second KILL escalation, warning-only failures, and continued application execution.
- `VERSION` semver format and runtime-file/version drift guard.
