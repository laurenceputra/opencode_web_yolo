# Install Layout

Use this file when editing `install.sh` or completion installation behavior.

## Managed Home

- Install into `~/.opencode_web_yolo`.
- Keep managed scripts and metadata in stable, documented paths.
- Keep installs idempotent on rerun.

## Required Installed Artifacts

- Wrapper script entrypoint.
- Dockerfile and entrypoint assets required by runtime build.
- Completion scripts:
  - `.opencode_web_yolo_completion.bash`
  - `.opencode_web_yolo_completion.zsh`
- `VERSION` and changelog/runtime metadata used by update logic.

## Installer Behavior

- Validate prerequisites before partial file writes where possible.
- Overwrite managed files intentionally on update.
- Keep user-specific configs separate from managed runtime files.
- Emit clear post-install usage and completion activation instructions.
