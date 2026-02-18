# Test Acceptance Matrix

Use this matrix when authoring tests under `tests/`.

## Required Acceptance Coverage

- Shell syntax validation (`bash -n`) for wrapper scripts.
- Dry-run output includes:
  - local-only port mapping
  - OpenCode web command
  - expected env variables
  - OpenCode config mount
  - OpenCode data mount
  - explicit `HOME`, `XDG_CONFIG_HOME`, and `XDG_DATA_HOME` env contract when user mapping is enabled
- Password enforcement fails when `OPENCODE_SERVER_PASSWORD` is missing/empty.
- Image contains `gh`, `git`, `ssh` binaries.
- `-gh` validates host `gh` install/auth and applies gh mount behavior.
- `--mount-ssh` warns and mounts only on explicit request.
- Startup path remains functional when `-gh` and/or `--mount-ssh` are enabled (no read-only mount ownership failures).
- Provider state persists across restart when config/data mount contracts are present.
- Persistence assertions verify state files are written to mounted host path, not only any in-container path.
- Docs contract check ensures Apache stream endpoints include `/event` and `/global/event`, and excludes stale `/session/event`.
- Health/diagnostics command reports key prerequisites and failures clearly.

## Test Design Rules

- Prefer deterministic shell tests over timing-sensitive integration flows.
- Assert exact contract strings for security-critical behavior.
- Keep fixtures minimal and avoid network reliance unless unavoidable.
