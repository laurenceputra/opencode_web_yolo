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
- Runtime env contract:
  - `HOME=${OPENCODE_WEB_YOLO_HOME}`
  - `XDG_CONFIG_HOME=${OPENCODE_WEB_YOLO_HOME}/.config`
  - `XDG_DATA_HOME=${OPENCODE_WEB_YOLO_HOME}/.local/share`
  - this prevents user-remap drift (for example writes to `/home/ubuntu/...`) and keeps state on mounted host paths
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

Entrypoint behavior:
- maps runtime user/group to host UID/GID.
- ensures writable home/config/data/workspace paths.
- avoids recursive ownership operations across read-only mount boundaries.
- installs passwordless sudo policy for mapped user.
- executes command via `gosu`.

## Proxy Streaming Notes

- OpenCode browser output uses long-lived event streams.
- Apache reverse proxy config must treat stream endpoints as SSE-style traffic:
  - `/global/event` and `/event` must both be stream-safe
  - longer proxy timeouts
  - chunked streaming enabled
  - compression disabled on event-stream routes
- Websocket proxy rules are optional compatibility paths, not a replacement for stream-safe SSE handling.

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
- Docker image build and runtime binary presence (`gh`, `git`, `ssh`).
- `VERSION` semver format and runtime-file/version drift guard.
- Security workflow runs a Trivy image scan on every push/PR.
