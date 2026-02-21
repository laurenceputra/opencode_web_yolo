# TECHNICAL

## Runtime Architecture

- Host command: `opencode_web_yolo`
- Wrapper builds/validates runtime image and runs:
  - `opencode web --hostname 0.0.0.0 --port ${OPENCODE_WEB_PORT}`
- Docker publish contract:
  - `-p 127.0.0.1:${OPENCODE_WEB_PORT}:${OPENCODE_WEB_PORT}`
- Container lifecycle defaults:
  - `--name ${OPENCODE_WEB_CONTAINER_NAME:-opencode_web_yolo}`
  - `--restart ${OPENCODE_WEB_RESTART_POLICY:-unless-stopped}`
  - detached launch by default (`OPENCODE_WEB_RUN_DETACHED=1`)
- Build/update defaults:
  - pull-on-start by default (`OPENCODE_WEB_AUTO_PULL=1`)
- Reverse proxy is expected in front of localhost bind.

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
  - Precedence: `--agents-file` > `OPENCODE_HOST_AGENTS` > `$HOME/.codex/AGENTS.md`.
  - Mounts a single host file read-only at `/etc/opencode/AGENTS.md`.
  - Exports `OPENCODE_INSTRUCTION_PATH=/etc/opencode/AGENTS.md` in the container.
  - `--no-host-agents` disables the host file mount.
  - If no default file exists, wrapper continues without the host mount.
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

## Image Contents and Entrypoint

Docker image includes:
- `gh`
- `git`
- `openssh-client`
- runtime helpers (`gosu`, `sudo`, `passwd`, `ca-certificates`)
- OpenCode CLI (`opencode-ai` npm package by default)

Image metadata files:
- `/opt/opencode-web-yolo-version`
- `/opt/opencode-version`
- `/app/AGENTS.md` (fallback instruction file)

Entrypoint behavior:
- maps runtime user/group to host UID/GID.
- pins runtime passwd home to `${OPENCODE_WEB_YOLO_HOME}` to keep SSH/git home resolution aligned.
- ensures writable home/config/data/workspace paths.
- avoids recursive ownership operations across read-only mount boundaries.
- installs passwordless sudo policy for mapped user.
- executes command via `gosu`.
- resolves instruction file from `OPENCODE_INSTRUCTION_PATH` (default `/app/AGENTS.md`).
- falls back to `/app/AGENTS.md` if the requested instruction path is unreadable.
- exits with an error when no readable instruction file is found.

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
- if remote version is newer, managed files are downloaded, replaced, and wrapper re-execs with original args.

Update can be disabled with:
- `OPENCODE_WEB_SKIP_UPDATE_CHECK=1`

## Rebuild Decision Logic

Image rebuild happens when any trigger is true:
- image tag missing locally
- wrapper version metadata mismatch
- OpenCode version metadata mismatch (unless version check disabled)
- pull/no-cache build flags requested

OpenCode install target during build:
- defaults to `latest` (`OPENCODE_VERSION=latest`)
- if `OPENCODE_WEB_EXPECTED_OPENCODE_VERSION` is set, build installs that explicit version

Controls:
- `--pull` or `OPENCODE_WEB_BUILD_PULL=1`
- `OPENCODE_WEB_BUILD_NO_CACHE=1`
- `OPENCODE_WEB_SKIP_VERSION_CHECK=1`

## Release Checklist

- Update `VERSION` and `CHANGELOG.md` together.
- Run `bash tests/run.sh`.
- Run `bash -n` and `shellcheck` for touched shell scripts.
- Build the runtime image and verify required binaries (`gh`, `git`, `ssh`).
- Verify README/TECHNICAL accuracy for any behavior changes.

## Test and CI Strategy

Tests and CI assert:
- `bash -n` and `shellcheck` on touched shell scripts.
- dry-run output contract (local-only port mapping, opencode web command, env values, config/data mounts, lifecycle flags, detach/pull defaults).
- password gate behavior when `OPENCODE_SERVER_PASSWORD` is missing.
- `-gh` validation/mount behavior and `--mount-ssh` explicit warning/mount behavior.
- health output includes persistence/lifecycle settings.
- health output includes browser-vs-server persistence scope visibility.
- Docker image build and runtime binary presence (`gh`, `git`, `ssh`).
- `VERSION` semver format and runtime-file/version drift guard.
- Security workflow runs a Trivy image scan on every push/PR.
