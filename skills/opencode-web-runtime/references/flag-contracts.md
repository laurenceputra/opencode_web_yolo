# Flag Contracts

Use this file when adding or changing wrapper CLI behavior.

## Supported Wrapper Interface

- Core form: `opencode_web_yolo [wrapper_flags] [-- opencode_web_args...]`
- Wrapper flags:
  - `--pull`
  - `--mount-ssh`
  - `--wrangler`
  - `-gh`, `--gh`
  - `health`, `--health`, `diagnostics`
  - `config`
  - `--version`, `version`
  - `--verbose`, `-v`

## Parsing Rules

- Recognize wrapper flags first.
- Preserve pass-through args for OpenCode web command.
- Require an explicit separator strategy so wrapper flags do not leak into app args.
- Keep command behavior deterministic for both dry-run and run paths.
- `--wrangler` must set `OPENCODE_WEB_BUILD_WRANGLER=1`, require the host
  `${XDG_CONFIG_HOME:-$HOME/.config}/.wrangler` directory, and mount it as
  `${OPENCODE_WEB_YOLO_HOME}/.config/.wrangler:rw` only for that run.

## Verification Expectations

- Dry-run output includes:
  - local-only port mapping
  - OpenCode web command
  - effective environment values
- Unknown flags are either passed through or rejected intentionally with clear messaging.
- Instruction loading must not add unsupported app CLI flags; rely on OpenCode native project/global rules discovery and mounted config paths.
