# Mounts and Security

Use this file when modifying mount behavior or auth-context handling.

## Default Mount Set

- Mount current repo (`$(pwd)`) to `/workspace` read-write.
- Mount OpenCode config directory read-write.
- Mount OpenCode data directory read-write so provider/auth state persists across container restarts.

## Optional `-gh` Mounts

- Require host `gh` binary to exist before enabling.
- Require host `gh auth status` to succeed before enabling.
- Mount host gh config/auth directory into container.
- Emit explicit warning that host GitHub auth context is exposed in container.
- Keep mount read-only.

## Optional `--mount-ssh`

- Mount `~/.ssh` read-only only when explicitly requested.
- Mount `~/.gitconfig` read-only only when explicitly requested and present.
- Set `GIT_CONFIG_GLOBAL` to the mounted gitconfig path when mounted.
- Emit explicit warning before mount.
- Recommend minimizing blast radius (least privilege, branch protection, short-lived credentials).

## Entrypoint Ownership Safety

- Do not recursively `chown` broad parent paths that can include read-only mount points.
- Restrict ownership fixups to known writable directories only.
- Startup must remain successful when `-gh` and/or `--mount-ssh` are enabled.

## Persistence Path Integrity

- Persistence is valid only when app write-path and mounted host path are identical.
- Verify runtime user home/XDG resolution, not mount presence alone.
- Add explicit runtime env (`HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`) when user remapping could change effective write paths.

## Prohibited Defaults

- Do not mount `~/.ssh` by default.
- Do not mount gh auth/config by default.
- Do not skip password checks when sensitive mounts are requested.
