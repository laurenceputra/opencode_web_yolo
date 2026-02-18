# Runtime Checklist

Use this checklist for runtime changes in `.opencode_web_yolo.sh`, `.opencode_web_yolo.Dockerfile`, and `.opencode_web_yolo_entrypoint.sh`.

## Wrapper Behavior

- Parse wrapper flags before pass-through args.
- Keep pass-through args unchanged after `--`.
- Gate container startup on required auth checks.
- Keep dry-run output faithful to the real docker invocation.
- Keep diagnostics callable without launching the app container.
- Ensure dry-run and diagnostics include both OpenCode config and OpenCode data mount contracts.

## Runtime Security Contracts

- Require non-empty `OPENCODE_SERVER_PASSWORD` on every run.
- Keep default port publish local-only (`127.0.0.1` binding).
- Keep auth mandatory even for localhost access.
- Do not add implicit secret mounts.
- Print warnings before enabling `-gh` or `--mount-ssh`.

## Container Runtime Contracts

- Install `gh`, `git`, `ssh` client binaries in image.
- Keep entrypoint UID/GID mapping aligned to host user.
- Ensure mapped user has writable home/config/data/workspace paths.
- If runtime process user differs from image default user, explicitly pin `HOME`, `XDG_CONFIG_HOME`, and `XDG_DATA_HOME` to mounted persistence paths.
- Avoid recursive ownership operations on paths that can contain read-only mounts.
- Use `gosu` handoff for final command execution.
- Run OpenCode web with configured host and port.
- Preserve provider/auth state across restart by mounting host OpenCode data directory.

## Exit Criteria

- Wrapper, Dockerfile, and entrypoint behavior all match `TECHNICAL.md`.
- Security checks fail fast with clear, actionable messages.
- Dry-run and normal-run command assembly are equivalent.
