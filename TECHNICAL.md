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
- Reverse proxy is expected in front of localhost bind.
- Optional weekly session retention is disabled by default.

## Installation Contract

- `install.sh` supports two valid install flows:
  - repo-local install (`./install.sh`) using sibling managed files from the checkout
  - streamed/bootstrap install (for example `curl -fsSL .../install.sh | bash`) that fetches managed files before install
- Bootstrap fetch source defaults:
  - repo: `OPENCODE_WEB_YOLO_REPO` when set
  - repo fallback: current git `origin` in `${PWD}` when available
  - final repo fallback: `laurenceputra/opencode_web_yolo`
  - branch: `OPENCODE_WEB_YOLO_BRANCH` (default `main`)
- Installer always installs managed runtime files into `${OPENCODE_WEB_INSTALL_HOME:-$HOME/.opencode_web_yolo}` and symlinks command to `${OPENCODE_WEB_BIN_DIR:-$HOME/.local/bin}/opencode_web_yolo`.

## Security Model

Non-negotiable runtime checks:
- `OPENCODE_SERVER_PASSWORD` must be set and non-empty before container startup.
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
- OpenCode CLI (`opencode-ai` npm package by default)
- when Playwright build is enabled: global `@playwright/test` package/`playwright` CLI and Chromium browser binaries in shared path (`PLAYWRIGHT_BROWSERS_PATH=/ms-playwright`)
- the browser install is executed by that exact installed package, coupling the Chromium revision to the package version used for the image
- the global package is not a substitute for project dependencies: mounted projects should declare `@playwright/test` locally for normal Node.js imports
- when Wrangler build is enabled: global `wrangler@latest` CLI
- Dockerfile layering keeps stable base/apt layers ahead of volatile build args; build args are declared near consuming layers to preserve cache reuse.

Image metadata files:
- `/opt/opencode-web-yolo-version`
- `/opt/opencode-version`
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
- after ownership and HOME/XDG setup, checks `${XDG_DATA_HOME}/opencode/opencode.db`; when present, runs `VACUUM;` through `sqlite3` via `gosu` as the mapped user with a 5000 ms busy timeout. GNU `timeout` sends TERM after 300 seconds and KILL 5 seconds later if the command remains alive. Missing databases are skipped without creation. Vacuum failures or timeout expiry warn to stderr and do not block either direct or retention-supervised OpenCode launch. This startup maintenance is separate from retention, whose worker never uses raw SQL or mutates SQLite WAL/SHM files.
- when retention is enabled, starts OpenCode, waits for authenticated `/global/health`, and supervises a mapped-user scheduler; TERM/INT are forwarded and the app exit status is returned.
- Docker starts `tini -s -g` so orphaned descendants are reaped and TERM/INT are forwarded to the child process group. The supervisor preserves the received signal when forwarding it to the app.
- does not inject unsupported OpenCode CLI flags for instruction loading.
- relies on OpenCode's native rules discovery (project AGENTS/CLAUDE files and global config-path rules).

## Session Retention

- `OPENCODE_WEB_RETENTION_DAYS` is a non-negative integer; `0` disables cleanup. `--retention-days N` and `--retention-days=N` override it for one invocation.
- `OPENCODE_WEB_RETENTION_DRY_RUN=1` previews without deleting or advancing state.
- After authenticated health succeeds, the scheduler calls OpenCode 1.18.25's experimental complete global listing API: `GET /experimental/session?roots=false&archived=true&limit=100`, following its `x-next-cursor` pagination header. It validates the response, builds a complete root-ancestor map across directories, and fails closed on missing parents, cycles, duplicate IDs, or incompatible shapes.
- Before listing or deleting, the worker validates `/global/health` and accepts only a healthy `1.18.x` version. Every worker fetch has an `AbortSignal.timeout` deadline controlled by `OPENCODE_WEB_RETENTION_FETCH_TIMEOUT_MS`; deletion verification has its own bounded timeout.
- Candidates are root sessions whose `time.updated` (epoch milliseconds) is strictly older than `now - retention_days`. Status is checked through authenticated `GET /session/status?directory=...` for every directory in the complete hierarchy; every `busy`/`retry` ID must map to a listed session and its root, otherwise the run fails closed. A busy/retrying descendant blocks its mapped candidate root even when the child is in another directory.
- Immediately before each delete, the root is refreshed through `GET /session/:sessionID?directory=...`; a missing, non-root, mismatched, or refreshed/recent session is skipped. The complete hierarchy and all relevant statuses are then reloaded before serial authenticated `DELETE /session/:sessionID?directory=...`.
- Each successful delete is verified by bounded polling of the direct `GET /session/:sessionID?directory=...` until it returns HTTP 404/not-found; other errors remain failures. OpenCode owns recursive cleanup of children, messages, parts, and events. No raw SQL or SQLite WAL/SHM mutation is performed.
- Because the experimental cursor is only `time.updated`, a full page whose final timestamp is duplicated is rejected as an unsafe equal-timestamp boundary; other equal-timestamp cases remain an upstream completeness limitation.
- A successful, non-preview run atomically writes `${XDG_STATE_HOME}/session-retention.last-success`. The marker is persistent because `XDG_STATE_HOME` is within the mounted OpenCode data path. Missing/old markers run immediately/when due; failures leave the marker unchanged for retry.
- The scheduler polls without a cron dependency and stops when OpenCode exits. It never logs session titles or content.
- `OPENCODE_WEB_RETENTION_POLL_SECONDS` is a positive integer with a one-second minimum; the production default is 3600 seconds.
- OpenCode does not provide an atomic delete-if-idle operation. The direct root refresh and immediate hierarchy/status recheck narrow the status-to-delete race, while OpenCode's authenticated deletion/cancellation behavior is the final guard; absolute active-session safety cannot be guaranteed.

## Proxy Streaming Notes

- OpenCode browser output uses long-lived event streams.
- OpenCode terminal sessions use websocket connections under `/pty` (for example `/pty/<id>/connect`).
- Apache reverse proxy config must treat stream endpoints as SSE-style traffic:
  - `/global/event` and `/event` must both be stream-safe
  - longer proxy timeouts
  - chunked streaming enabled
  - compression disabled on event-stream routes
- Reverse proxies must forward `/pty` with websocket upgrade semantics (`ws://` upstream on Apache with `mod_proxy_wstunnel`).
- Websocket proxy rules are optional compatibility paths for non-PTY endpoints, not a replacement for stream-safe SSE handling.

## Update and Re-exec

On run, unless disabled:
- wrapper checks remote `VERSION` from `${OPENCODE_WEB_YOLO_REPO}` and `${OPENCODE_WEB_YOLO_BRANCH}`.
  - default repo: `laurenceputra/opencode_web_yolo`
  - default branch: `main`
- if remote version is newer, managed files are downloaded, replaced, and wrapper re-execs with original args.

Update can be disabled with:
- `OPENCODE_WEB_SKIP_UPDATE_CHECK=1`

## Rebuild Decision Logic

Image rebuild happens when any trigger is true:
- image tag missing locally
- wrapper version metadata mismatch
- OpenCode version metadata mismatch (unless version check disabled)
- Playwright build metadata mismatch
- Playwright package version metadata mismatch when the Playwright build is enabled (unless version check disabled)
- Wrangler build metadata mismatch
- pull/no-cache build flags requested

OpenCode install target during build:
- defaults to `latest` (`OPENCODE_VERSION=latest`)
- if `OPENCODE_WEB_EXPECTED_OPENCODE_VERSION` is set, build installs that explicit version

Controls:
- `--pull` or `OPENCODE_WEB_BUILD_PULL=1`
- `--playwright` or `OPENCODE_WEB_BUILD_PLAYWRIGHT=1`
- `PLAYWRIGHT_VERSION` is an explicit Docker build arg (default `1.62.1`); the wrapper resolves the current `@playwright/test` version before an enabled build unless `OPENCODE_WEB_EXPECTED_PLAYWRIGHT_VERSION` is set. An explicit expected version remains the install target when version checks are skipped.
- `--wrangler` or `OPENCODE_WEB_BUILD_WRANGLER=1`
- `OPENCODE_WEB_BUILD_NO_CACHE=1`
- `OPENCODE_WEB_SKIP_VERSION_CHECK=1` skips npm lookup and OpenCode/Playwright package-version drift comparisons, but does not disable enabled builds or discard an explicit Playwright pin. Truthy build toggles (`true`, `yes`, `on`) are normalized to `0`/`1` before Docker args and metadata comparisons.

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
- startup VACUUM behavior for existing and missing databases, custom XDG data paths, mapped-user invocation, SQLite timeout plus TERM/KILL escalation, warning-only failures, and continued application execution.
- `VERSION` semver format and runtime-file/version drift guard.
