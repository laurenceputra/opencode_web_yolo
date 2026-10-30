# Docs Coverage Checklist

Use this checklist when editing `README.md` and `TECHNICAL.md`.

## README Coverage

- Quickstart for install and first run.
- Mandatory password setup (`OPENCODE_SERVER_PASSWORD`).
- Local-only port publish default and rationale.
- Reverse proxy example for Nginx with required headers and websocket upgrade handling.
- Reverse proxy example for Apache with `ProxyPass`/`ProxyPassReverse` and explicit event-stream/SSE-safe handling (timeouts, no buffering/compression on stream paths).
- Apache stream endpoint examples must include `/event` and `/global/event`; do not document stale `/session/event`.
- Clarify websocket settings as optional compatibility guidance, not the only streaming path.
- TLS termination guidance at proxy layer.
- Persistence notes for both OpenCode config and OpenCode data directories.
- Security notes for `-gh` and `--mount-ssh`.
- Troubleshooting section referencing diagnostics/health command.

## TECHNICAL Coverage

- Runtime architecture and process topology.
- Mount model and security rationale.
- Update/re-exec and rebuild decision logic.
- Test strategy and CI gate intent.

## Accuracy Rules

- Keep docs synchronized with actual defaults (port, host binding, env names).
- Update docs in the same change as behavior changes.
- Prefer copy-pastable command examples.
