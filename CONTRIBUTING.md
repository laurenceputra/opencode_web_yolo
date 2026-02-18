# Contributing

## Development Workflow

- Follow `AGENTS.md` for repository workflow rules.
- Keep changes focused and aligned with `TECHNICAL.md`.
- Update tests and docs in the same change when behavior changes.

## Running Tests

```bash
bash tests/run.sh
```

## Coding Standards

- Bash scripts must pass `bash -n` and `shellcheck`.
- Avoid implicit credential mounts or weakening auth requirements.
