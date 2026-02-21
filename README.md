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
- OpenCode web host inside container: `0.0.0.0`
- OpenCode package install target: `latest` at build time
- Container name: `opencode_web_yolo`
- Restart policy: `unless-stopped`
- Launch mode: background (`-d`)
- Pull behavior: pull-on-start enabled

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

Environment variables:
- `OPENCODE_HOST_AGENTS` (host path for AGENTS.md when `--agents-file` is absent)
- `OPENCODE_INSTRUCTION_PATH` (in-container path used by the runtime)

Use `OPENCODE_WEB_DRY_RUN=1` or `--dry-run` to preview the exact docker command and effective settings.

`opencode_web_yolo` now defaults to background mode and pull-on-start. Use `--foreground --no-pull` for attached/no-pull runs.

## Persistence Paths

- Wrapper config file: `~/.opencode_web_yolo/config`
- OpenCode config mount: `~/.config/opencode`
- OpenCode data/state mount: `~/.local/share/opencode`

Provider auth/session state (for example OpenAI and GitHub Copilot links) persists across restarts from the OpenCode data path.
The wrapper also pins runtime env (`HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`) to `/home/opencode` paths so app writes always land on mounted host directories.

## Instruction File Selection

OpenCode can load an instruction file from the host and mount it read-only into the container.

Precedence:
1) `--agents-file <host-path>`
2) `OPENCODE_HOST_AGENTS=<host-path>`
3) `~/.codex/AGENTS.md` when present

Mount behavior:
- The selected file is mounted read-only to `/etc/opencode/AGENTS.md`.
- `OPENCODE_INSTRUCTION_PATH=/etc/opencode/AGENTS.md` is set inside the container.
- Use `--no-host-agents` to opt out.

Runtime resolution:
- `OPENCODE_INSTRUCTION_PATH` points to the instruction file OpenCode will load.
- If the path is unreadable, the entrypoint falls back to `/app/AGENTS.md`.
- If no host file is available and `--no-host-agents` is not set, the default selection is optional (run without host mount).

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
mkdir -p "$HOME/.config/opencode" "$HOME/.local/share/opencode" && (docker rm -f opencode_web_yolo >/dev/null 2>&1 || true) && docker run -d --name opencode_web_yolo --restart unless-stopped -p 127.0.0.1:4096:4096 -e LOCAL_UID="$(id -u)" -e LOCAL_GID="$(id -g)" -e LOCAL_USER="$(id -un)" -e OPENCODE_SERVER_PASSWORD='change-me-now' -e HOME=/home/opencode -e XDG_CONFIG_HOME=/home/opencode/.config -e XDG_DATA_HOME=/home/opencode/.local/share -e XDG_STATE_HOME=/home/opencode/.local/share/opencode/state -v "$PWD:/workspace" -v "$HOME/.config/opencode:/home/opencode/.config/opencode" -v "$HOME/.local/share/opencode:/home/opencode/.local/share/opencode" opencode_web_yolo:latest opencode web --hostname 0.0.0.0 --port 4096
```

Force-refresh image to latest OpenCode version:

```bash
docker build --pull --build-arg BASE_IMAGE=node:20-slim --build-arg WRAPPER_VERSION="$(cat VERSION)" --build-arg NPM_VERSION=11.10.1 --build-arg OPENCODE_NPM_PACKAGE=opencode-ai --build-arg OPENCODE_VERSION=latest -t opencode_web_yolo:latest -f .opencode_web_yolo.Dockerfile .
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
- Host AGENTS mount:
  - `--agents-file` and `OPENCODE_HOST_AGENTS` only mount a single file, read-only.
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
