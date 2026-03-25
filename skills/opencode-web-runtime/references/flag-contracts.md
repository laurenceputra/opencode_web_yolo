# Flag Contracts

Use this file when adding or changing wrapper CLI behavior.

## Supported Wrapper Interface

- Core form: `opencode_web_yolo [wrapper_flags] [-- opencode_web_args...]`
- Wrapper flags:
  - `--pull`
  - `--no-pull`
  - `--agents-file <host-path>`
  - `--no-host-agents`
  - `--dry-run`
  - `--detach`, `-d`
  - `--foreground`, `-f`
  - `--mount-ssh`
  - `-gh`, `--gh`
  - `rehearse-migrations`
  - `health`, `--health`, `diagnostics`
  - `check-roadmap`, `roadmap-entropy`
  - `config`
  - `--help`, `-h`, `help`
  - `--version`, `version`
  - `--verbose`, `-v`

## Parsing Rules

- Recognize wrapper flags first.
- Recognize `rehearse-migrations` as a wrapper command while still preserving pass-through OpenCode args after wrapper parsing.
- Preserve pass-through args for OpenCode web command.
- Require an explicit separator strategy so wrapper flags do not leak into app args.
- Keep command behavior deterministic for both dry-run and run paths.

## Verification Expectations

- Dry-run output includes:
  - local-only port mapping
  - OpenCode web command
  - effective environment values
- Rehearsal dry-run also includes:
  - source host config/data paths
  - scratch config/data mount paths
  - scratch-staged AGENTS path when host instruction loading is active
  - proof that the real persistence paths are not mounted
- Unknown flags are either passed through or rejected intentionally with clear messaging.
- Instruction loading must not add unsupported app CLI flags; rely on OpenCode native project/global rules discovery and mounted config paths.
