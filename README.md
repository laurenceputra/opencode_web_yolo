# opencode_web_yolo

`opencode_web_yolo` runs OpenCode Web in Docker and binds it to `127.0.0.1` for safe reverse-proxy access.

## Quickstart

Install directly from GitHub:

```bash
curl -fsSL https://raw.githubusercontent.com/laurenceputra/opencode_web_yolo/main/install.sh | bash
```

Then run:

```bash
./install.sh
export OPENCODE_SERVER_PASSWORD='change-me-now'
opencode_web_yolo
```

Defaults:
- Port: `4096`
- Bind/publish: `127.0.0.1:4096:4096`
- OpenCode web host inside container: `0.0.0.0`
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
- `--detach`, `-d`
- `--foreground`, `-f`
- `--mount-ssh`
- `-gh`, `--gh`
- `health`, `--health`, `diagnostics`
- `config`
- `--help`, `-h`, `help`
- `--version`, `version`
- `--verbose`, `-v`

Use `OPENCODE_WEB_DRY_RUN=1` to preview the exact docker command and effective settings.

`opencode_web_yolo` now defaults to background mode and pull-on-start. Use `--foreground --no-pull` for attached/no-pull runs.

## Persistence Paths

- Wrapper config file: `~/.opencode_web_yolo/config`
- OpenCode config mount: `~/.config/opencode`
- OpenCode data/state mount: `~/.local/share/opencode`

Provider auth/session state (for example OpenAI and GitHub Copilot links) persists across restarts from the OpenCode data path.
The wrapper also pins runtime env (`HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`) to `/home/opencode` paths so app writes always land on mounted host directories.

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
docker build --pull --build-arg BASE_IMAGE=node:20-slim --build-arg WRAPPER_VERSION="$(cat VERSION)" --build-arg OPENCODE_NPM_PACKAGE=opencode-ai --build-arg OPENCODE_VERSION=latest -t opencode_web_yolo:latest -f .opencode_web_yolo.Dockerfile .
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

Enable modules: `proxy`, `proxy_http`, `headers`, `ssl`, `deflate`.

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

    ProxyPass        / http://127.0.0.1:4096/ timeout=120 retry=0
    ProxyPassReverse / http://127.0.0.1:4096/

    # Optional compatibility path if websocket endpoints are in use:
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

## Governance Files

- `LICENSE` and `CODEOWNERS` are installed by `install.sh` for local visibility.

## Troubleshooting

- Run `opencode_web_yolo health` for Docker/image/auth diagnostics.
- Use `OPENCODE_WEB_DRY_RUN=1` to verify port bind, env, and mount behavior.
- Use `--verbose` for extra wrapper logs.
- If browser output stalls behind Apache, verify SSE paths are proxied with longer timeouts and `no-gzip=1`.
- Workspace UI state (for example expanded workspaces and last-open session shortcut) is stored in browser localStorage by OpenCode Web, so it is not shared across different browsers/profiles.
- Session/project data still persists server-side in `~/.local/share/opencode/opencode.db`; use explicit session URLs (for example `/<workspace>/session/<id>`) when switching browsers.
