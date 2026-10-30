# opencode_web_yolo

`opencode_web_yolo` runs OpenCode Web in Docker and binds it to `127.0.0.1` for safe reverse-proxy access.

## Quickstart

Install directly from GitHub (this already runs the installer):

```bash
curl -fsSL https://raw.githubusercontent.com/laurenceputra/opencode_web_yolo/main/install.sh | bash
```

Then run:

```bash
export OPENCODE_SERVER_PASSWORD='change-me-now'
opencode_web_yolo
```

Install from a local clone instead:

```bash
git clone https://github.com/laurenceputra/opencode_web_yolo.git
cd opencode_web_yolo
./install.sh
export OPENCODE_SERVER_PASSWORD='change-me-now'
opencode_web_yolo
```

Defaults:
- Port: `4096`
- Bind/publish: `127.0.0.1:4096:4096`
- OpenCode serve host inside container: `0.0.0.0`
- OpenCode package install target: `latest` at build time
- Runtime base image: `node:22-slim` (release-owned and enforced during build)
- Playwright build: disabled by default; opt in with `OPENCODE_WEB_BUILD_PLAYWRIGHT=1` in the persistent config or `--playwright` for one run
- Container name: `opencode_web_yolo`
- Restart policy: `unless-stopped`
- Launch mode: background (`-d`)
- Pull behavior: pull-on-start enabled
- Session retention: disabled by default (`OPENCODE_WEB_RETENTION_DAYS=0`)
- Startup VACUUM TERM timeout: `300` seconds (KILL escalation remains fixed at 5 seconds)

## Authentication Requirement

`OPENCODE_SERVER_PASSWORD` is required on every run. Startup fails if it is missing or empty, including localhost usage.

Optional:
- `OPENCODE_SERVER_USERNAME` (default: `opencode`)

## Usage

```bash
opencode_web_yolo [wrapper_flags] [-- opencode_web_args...]
```

Wrapper flags:
- `--pull`
- `--no-pull`
- `--playwright` (one-shot Playwright build opt-in)
- `--wrangler`
- `--retention-days N` or `--retention-days=N` (0 disables weekly cleanup)
- `--agents-file <host-path>`
- `--no-host-agents`
- `--dry-run`
- `--detach`, `-d`
- `--foreground`, `-f`
- `--mount-ssh`
- `-gh`, `--gh`
- `health`, `--health`, `diagnostics`
- `config`
- `--help`, `-h`, `help`
- `--version`, `version`
- `--verbose`, `-v`

Additional environment variable:
- `OPENCODE_HOST_AGENTS` (host instruction-file path when `--agents-file` is absent)

Use `OPENCODE_WEB_DRY_RUN=1` or `--dry-run` to preview the exact docker command and effective settings.

`opencode_web_yolo` now defaults to background mode and pull-on-start. Use `--foreground --no-pull` for attached/no-pull runs.
If a container with the configured name already exists, wrapper launch replaces it (stops if running, then removes, then starts fresh).

### Self-update and repair

Managed installs check the configured GitHub branch on startup. An update downloads one branch archive snapshot, validates the complete release (including the runtime supervisor and retention worker), and only then promotes it before re-executing with the original arguments and environment. The re-exec marker prevents an update loop; explicit and inherited safety controls remain enabled, and original CLI flags remain authoritative. A value exported by a historical wrapper's config can survive that immediate re-exec, but the new loader ignores stale config assignments on the next fresh invocation. The tracked `.opencode_web_yolo.manifest` controls the release file set. Incomplete installs are repaired even when their local `VERSION` equals the remote version; malformed or incomplete archives are rejected before Docker build. Set `OPENCODE_WEB_SKIP_UPDATE_CHECK=1` to skip network checks, but an incomplete managed install still fails closed and must be repaired with `install.sh`.

Bootstrap installation from `curl | bash` uses the same archive-and-validation flow. `curl` and `tar` are required for streamed/bootstrap installs and self-update repairs. Branch names containing `/` are supported; other URL-significant branch characters are encoded safely.

Recovery note for historical `0.1.10` installs: that old updater relies on GNU `sort -V`, which stock macOS/BSD `sort` does not provide. If such an install cannot start its updater, rerun the latest `install.sh`; the current wrapper's portable comparator cannot repair an updater that fails before it can launch the current wrapper.

## Configuration

Run `opencode_web_yolo config` to generate a sample config file at `~/.opencode_web_yolo/config`.
The wrapper sources that file on startup, so it is the right place for persistent operator overrides.
The generated file is an override-only, mode-0600 commented template. Release-owned runtime
settings (the Node base image, OpenCode package, internal hostname/home/workdir/cleanup, and
Playwright package-version pin) are not configurable; stale assignments in older config files
are ignored. One-shot build/debug controls should be supplied as flags or environment variables.

Common workflow:

```bash
opencode_web_yolo config
$EDITOR ~/.opencode_web_yolo/config
opencode_web_yolo
```

Operator-facing settings:

| Variable | Default | Purpose |
| --- | --- | --- |
| `OPENCODE_SERVER_PASSWORD` | none, required | Required non-empty password for OpenCode Web. Startup fails if it is missing or empty. |
| `OPENCODE_SERVER_USERNAME` | `opencode` | Login username paired with `OPENCODE_SERVER_PASSWORD`. |
| `OPENCODE_WEB_PORT` | `4096` | Host/container port used for `opencode serve` and the local Docker publish mapping. |
| `OPENCODE_WEB_CONTAINER_NAME` | `opencode_web_yolo` | Docker container name used for launch, replacement, and diagnostics. |
| `OPENCODE_WEB_RESTART_POLICY` | `unless-stopped` | Docker restart policy applied to the container. |
| `OPENCODE_WEB_RUN_DETACHED` | `1` | Launch mode default. Use `1` for background mode or `0` for attached runs unless overridden by flags. |
| `OPENCODE_WEB_AUTO_PULL` | `1` | Persistent pull-on-start setting. Set to `0` in `~/.opencode_web_yolo/config` to disable ordinary automatic pulls; compatibility rebuilds still force Docker `--pull`. |
| `OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS` | `300` | Persistent positive integer timeout for startup SQLite VACUUM's GNU `timeout` TERM deadline; values above `2147483647` are rejected. The SQLite busy timeout remains 5000 ms and KILL escalation remains fixed at 5 seconds. |
| `OPENCODE_WEB_YOLO_REPO` | `laurenceputra/opencode_web_yolo` | GitHub repo used for wrapper self-update checks and bootstrap downloads. |
| `OPENCODE_WEB_YOLO_BRANCH` | `main` | Branch used with `OPENCODE_WEB_YOLO_REPO` for update checks and bootstrap downloads. |
| `OPENCODE_WEB_SKIP_UPDATE_CHECK` | `0` | Set to `1` to skip the wrapper's remote `VERSION` check and self-update flow. |
| `OPENCODE_WEB_CONFIG_DIR` | `${XDG_CONFIG_HOME:-$HOME/.config}/opencode` | Host OpenCode config directory mounted into the container for persistent config and rules. |
| `OPENCODE_WEB_DATA_DIR` | `${XDG_DATA_HOME:-$HOME/.local/share}/opencode` | Host OpenCode data directory mounted into the container for persistent sessions, provider auth, and state. |
| `OPENCODE_WEB_YOLO_IMAGE` | `opencode_web_yolo:latest` | Docker image tag the wrapper builds and runs. |
| `OPENCODE_WEB_BUILD_PLAYWRIGHT` | `0` | Set to `1` in `~/.opencode_web_yolo/config` for durable Playwright enablement; `--playwright` enables it for one run and preinstalls Chromium into `/ms-playwright`. |
| `OPENCODE_WEB_BUILD_WRANGLER` | `0` | Set to `1` to install `wrangler@latest` globally in the runtime image. `--wrangler` enables this and mounts host Wrangler config for the run. |
| `OPENCODE_WEB_RETENTION_DAYS` | `0` | Non-negative number of days. After health succeeds, delete inactive root sessions older than this cutoff at most once per seven days. A flag overrides the configured value for that invocation. |
| `OPENCODE_WEB_RETENTION_DRY_RUN` | `0` | Safely preview retention candidates without deleting or advancing the success marker. |
| `OPENCODE_WEB_RETENTION_FETCH_TIMEOUT_MS` | `10000` | Positive per-request worker timeout in milliseconds. Requests that stall fail closed. |
| `OPENCODE_WEB_RETENTION_VERIFY_TIMEOUT_MS` | `10000` | Positive bounded deletion-verification timeout in milliseconds. |
| `OPENCODE_WEB_RETENTION_POLL_SECONDS` | `3600` | Positive scheduler interval; values below one second are rejected. |

`OPENCODE_WEB_SKIP_VERSION_CHECK=1`, `OPENCODE_WEB_BUILD_PULL=1`,
`OPENCODE_WEB_BUILD_NO_CACHE=1`, `OPENCODE_WEB_DRY_RUN=1`, and
`OPENCODE_WEB_VERBOSE=1` plus `OPENCODE_WEB_RETENTION_DRY_RUN=1` remain supported as environment compatibility/troubleshooting
controls, but are not generated as persistent defaults. `--pull`, `--no-pull`, `--dry-run`,
and `--verbose` are likewise one-shot. A compatibility rebuild for a legacy or missing Node
metadata image always adds Docker `--pull`, including when `--no-pull` is used or persistent
auto-pull is disabled.

`OPENCODE_WEB_AUTO_PULL` is persistent when set in the generated config file. Use `--pull` or
`--no-pull` when the pull behavior should apply only to one invocation.

### Playwright runtime

Playwright is intentionally opt-in because its Chromium browser and Linux dependencies make the image substantially larger. To keep it enabled across runs, edit the generated config and set:

```bash
export OPENCODE_WEB_BUILD_PLAYWRIGHT=1
```

Use `--playwright` instead when the build should be enabled only for that invocation. The enabled image installs the wrapper-owned global `@playwright/test` package, resolving the current npm version when checks are enabled and using the release fallback when checks are skipped. It runs that package's `playwright install --with-deps chromium` and stores the expected and installed versions in image metadata; users cannot pin the package through wrapper config. The global CLI is a convenience for runtime diagnostics and commands; arbitrary mounted projects should still declare `@playwright/test` locally for normal Node.js imports and project dependency resolution.

Truthy toggle values such as `true`, `yes`, and `on` are accepted and normalized to `1` before image build arguments and metadata comparisons. `OPENCODE_WEB_SKIP_VERSION_CHECK=1` skips remote version lookup and package-version drift checks only; Playwright build enablement remains effective.

## Persistence Paths

- Wrapper config file: `~/.opencode_web_yolo/config`
- OpenCode config mount: `~/.config/opencode`
- OpenCode data/state mount: `~/.local/share/opencode`

Provider auth/session state (for example OpenAI and GitHub Copilot links) persists across restarts from the OpenCode data path.
The wrapper also pins runtime env (`HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`) to `/home/opencode` paths so app writes always land on mounted host directories.

On every container startup, after the mapped-user ownership and XDG setup, the entrypoint checks
`$XDG_DATA_HOME/opencode/opencode.db`. If that database exists, it runs `VACUUM;` with `sqlite3` as
the mapped runtime user, waiting up to 5000 ms for a lock. GNU `timeout` sends TERM after the
configured `OPENCODE_WEB_STARTUP_VACUUM_TERM_TIMEOUT_SECONDS` deadline (300 seconds by default)
and sends KILL 5 seconds later if VACUUM is still running. A missing database is skipped
without creating one. Vacuum can add startup latency and temporarily require additional disk space
while SQLite rewrites the database. If it cannot vacuum because of a lock, permissions, corruption,
disk space, or another non-timeout error, startup prints a concise warning and continues. Timeout-
expiry warnings include the effective TERM deadline. `health` and `--dry-run` show the effective TERM
timeout, and the wrapper passes it into Docker.

Startup VACUUM is separate from weekly retention. The retention worker remains an authenticated
OpenCode API worker: it does not use raw SQL or manually modify SQLite WAL, SHM, or journal
sidecars.

## Weekly session retention

Enable retention in the generated config, or override it for one invocation:

```bash
export OPENCODE_WEB_RETENTION_DAYS=30
opencode_web_yolo
opencode_web_yolo --retention-days=14
```

The container starts OpenCode first, waits for authenticated `/global/health`, and then runs a lightweight scheduler as the mapped runtime user. The first enabled run is due immediately; later runs use the success marker at `$XDG_STATE_HOME/session-retention.last-success` and are no more frequent than once every seven days. Stopped containers do not lose schedule state, and failed runs do not advance the marker. The image uses `tini -s -g` as PID 1 for subreaping and signal-group forwarding.

Cleanup first requires a healthy OpenCode `1.18.x` server, then uses OpenCode 1.18.25's experimental complete global listing (`/experimental/session` with `roots=false` and `archived=true`) and safely maps every listed session to its root across directories. It checks `/session/status` for every involved directory; any busy/retrying descendant or unmapped active ID fails closed, and the affected root is skipped. Before each delete it directly refreshes the root through `GET /session/:id?directory=...`, confirms it is still an old root, reloads the hierarchy, and re-checks activity. Deletes remain serial through `DELETE /session/:id?directory=...`; each successful delete is verified by polling the direct GET until it returns 404/not-found. This lets OpenCode recursively remove children, messages, parts, and events. It never edits SQLite directly or removes WAL/SHM files. An incompatible, unsupported, stalled, or failed API response fails closed and is retried later. Session IDs may be logged for diagnostics, but titles and content are not.

The API has no atomic delete-if-idle operation, so a residual status-to-delete race cannot be eliminated completely. The wrapper's direct refresh and immediate activity/hierarchy recheck narrow that window; OpenCode's own authenticated deletion/cancellation behavior is the final guard, and any failed or uncertain run is retried later.

The global API's cursor contains only `time.updated`; when a full page ends with duplicate timestamps, the worker refuses to delete rather than risk skipping sessions at that boundary. Equal timestamps without this detectable page-boundary pattern remain an upstream limitation of the experimental cursor API.
Only sessions are targeted; projects, accounts, provider auth, and OpenCode configuration are preserved.

For a safe preview, set `OPENCODE_WEB_RETENTION_DRY_RUN=1`; previews never write the success marker. `health` and `--dry-run` show the effective retention setting and marker path.

## Instruction File Selection

Host instruction-file precedence:
1) `--agents-file <host-path>`
2) `OPENCODE_HOST_AGENTS=<host-path>`
3) `~/.config/opencode/AGENTS.md`
4) `~/.codex/AGENTS.md`
5) `~/.copilot/copilot-instructions.md`
6) `~/.claude/CLAUDE.md`

Mount behavior:
- The selected file is mounted read-only to `/home/opencode/.config/opencode/AGENTS.md`.
- This normalizes non-OpenCode filenames (Codex/Copilot/Claude conventions) to OpenCode's global rule path.
- `--no-host-agents` disables this selected-file mount.

Examples:

```bash
opencode_web_yolo --agents-file /path/to/my/AGENTS.md
```

```bash
OPENCODE_HOST_AGENTS=/ci/path/AGENTS.md opencode_web_yolo
```

```bash
opencode_web_yolo --no-host-agents
```

```bash
opencode_web_yolo --dry-run
```

## Operational One-Liners

Start with the wrapper binary (pull + background defaults):

```bash
OPENCODE_SERVER_PASSWORD='change-me-now' opencode_web_yolo
```

Run in background (with automatic startup on reboot):

```bash
export OPENCODE_SERVER_PASSWORD='change-me-now'
mkdir -p "$HOME/.config/opencode" "$HOME/.local/share/opencode" && (docker rm -f opencode_web_yolo >/dev/null 2>&1 || true) && docker run -d --name opencode_web_yolo --restart unless-stopped -p 127.0.0.1:4096:4096 -e LOCAL_UID="$(id -u)" -e LOCAL_GID="$(id -g)" -e LOCAL_USER="$(id -un)" -e OPENCODE_SERVER_PASSWORD -e HOME=/home/opencode -e XDG_CONFIG_HOME=/home/opencode/.config -e XDG_DATA_HOME=/home/opencode/.local/share -e XDG_STATE_HOME=/home/opencode/.local/share/opencode/state -v "$PWD:/workspace" -v "$HOME/.config/opencode:/home/opencode/.config/opencode" -v "$HOME/.local/share/opencode:/home/opencode/.local/share/opencode" opencode_web_yolo:latest opencode serve --hostname 0.0.0.0 --port 4096
```

Force-refresh image to the resolved latest OpenCode and Playwright versions:

```bash
OPENCODE_VERSION="$(npm view opencode-ai version)"
PLAYWRIGHT_VERSION="$(npm view @playwright/test version)"
docker build --pull --build-arg WRAPPER_VERSION="$(cat VERSION)" --build-arg OPENCODE_VERSION="${OPENCODE_VERSION}" --build-arg OPENCODE_WEB_BUILD_PLAYWRIGHT=1 --build-arg PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION}" -t opencode_web_yolo:latest -f .opencode_web_yolo.Dockerfile .
```

## Reverse Proxy (Nginx)

Terminate TLS at Nginx and proxy to local upstream.

```nginx
upstream opencode_web_yolo {
    server 127.0.0.1:4096;
}

server {
    listen 443 ssl http2;
    server_name opencode.example.com;

    ssl_certificate     /etc/letsencrypt/live/opencode.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/opencode.example.com/privkey.pem;

    location / {
        proxy_pass http://opencode_web_yolo;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

## Reverse Proxy (Apache)

Enable modules: `proxy`, `proxy_http`, `proxy_wstunnel`, `headers`, `ssl`, `deflate`.

```apache
<VirtualHost *:443>
    ServerName opencode.example.com

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/opencode.example.com/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/opencode.example.com/privkey.pem

    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "https"

    # Stream endpoints: keep long-lived SSE responses unbuffered/uncompressed.
    ProxyTimeout 600
    SetEnv proxy-sendchunked 1
    SetEnvIfNoCase Request_URI "^/(global/event|event)" no-gzip=1

    ProxyPass        /global/event  http://127.0.0.1:4096/global/event  timeout=600 retry=0
    ProxyPassReverse /global/event  http://127.0.0.1:4096/global/event
    ProxyPass        /event http://127.0.0.1:4096/event timeout=600 retry=0
    ProxyPassReverse /event http://127.0.0.1:4096/event

    # Terminal PTY endpoint uses websocket upgrades.
    ProxyPass        /pty ws://127.0.0.1:4096/pty retry=0
    ProxyPassReverse /pty ws://127.0.0.1:4096/pty

    ProxyPass        / http://127.0.0.1:4096/ timeout=120 retry=0
    ProxyPassReverse / http://127.0.0.1:4096/

    # Optional compatibility path if additional websocket endpoints are in use:
    # ProxyPass        /ws ws://127.0.0.1:4096/ws
    # ProxyPassReverse /ws ws://127.0.0.1:4096/ws
</VirtualHost>
```

## Security Notes

- `-gh`/`--gh`:
  - Requires host `gh` CLI and successful `gh auth status`.
  - Mounts host GitHub CLI auth config into container (read-only).
  - Wrapper prints a warning before mount.
- `--mount-ssh`:
  - Mounts host `~/.ssh` into container (read-only) only when explicitly requested.
  - Also mounts host `~/.gitconfig` read-only when present.
  - Sets `GIT_CONFIG_GLOBAL=/home/opencode/.gitconfig` so git clients resolve the mounted config consistently.
  - Entrypoint also pins runtime user home resolution to `/home/opencode` for SSH/git consistency.
  - Wrapper prints a warning and recommends least-privilege credentials.
- `--wrangler`:
  - Requires `${XDG_CONFIG_HOME:-$HOME/.config}/.wrangler` to already exist.
  - Mounts it read-write at `/home/opencode/.config/.wrangler`; it is never mounted by default.
  - Container processes can read, modify, and rotate Cloudflare credentials. Use only with trusted code.
- Host instruction-file mount:
  - Wrapper resolves one file using the documented fallback chain and mounts it read-only to `/home/opencode/.config/opencode/AGENTS.md`.
  - `--agents-file` and `OPENCODE_HOST_AGENTS` override all defaults.
  - No other host config (SSH, gh, XDG) is mounted implicitly.

## Governance Files

- `LICENSE` and `CODEOWNERS` are installed by `install.sh` for local visibility.

## Troubleshooting

- Run `opencode_web_yolo health` for Docker/image/auth diagnostics.
- Use `OPENCODE_WEB_DRY_RUN=1` or `--dry-run` to verify port bind, env, and mount behavior.
- Use `--verbose` for extra wrapper logs.
- If terminal open/connect fails with `502 Bad Gateway` or `NS_ERROR_WEBSOCKET_CONNECTION_REFUSED`, verify proxy websocket routing for `/pty` (Apache requires `proxy_wstunnel` and `ws://` `ProxyPass` rules).
- If browser output stalls behind Apache, verify SSE paths are proxied with longer timeouts and `no-gzip=1`.
- Workspace UI state (for example expanded workspaces and last-open session shortcut) is stored in browser localStorage by OpenCode Web, so it is not shared across different browsers/profiles.
- Session/project data still persists server-side in `~/.local/share/opencode/opencode.db`; use explicit session URLs (for example `/<workspace>/session/<id>`) when switching browsers.
