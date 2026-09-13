# Install Layout

Use this file when editing `install.sh` or completion installation behavior.

## Managed Home

- Install into `~/.opencode_web_yolo`.
- Keep managed scripts and metadata in stable, documented paths.
- Keep installs idempotent on rerun.

## Required Installed Artifacts

- Tracked `.opencode_web_yolo.manifest` release-file manifest.
- Wrapper script entrypoint.
- Dockerfile and entrypoint assets required by runtime build.
- Runtime supervisor and retention worker assets required by the enabled scheduler.
- Completion scripts:
  - `.opencode_web_yolo_completion.bash`
  - `.opencode_web_yolo_completion.zsh`
- `VERSION` and changelog/runtime metadata used by update logic.

## Installer Behavior

- Validate prerequisites before partial file writes where possible.
- Streamed/bootstrap installation downloads and validates one GitHub branch archive rather than per-file raw URLs.
- Promote staged files with same-filesystem renames and place `VERSION` last so an interrupted install can be retried.
- Overwrite managed files intentionally on update.
- Keep user-specific configs separate from managed runtime files.
- Emit clear post-install usage and completion activation instructions.
