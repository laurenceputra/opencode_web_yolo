# CI Job Outline

Use this file when creating or updating `.github/workflows/ci.yml`.

## Required Jobs

- Shell lint/syntax job:
  - run `bash -n` on scripts
  - run `shellcheck`
- Docker validation job:
  - build runtime image from repo Dockerfile
  - run minimal binary presence checks in built image
- Behavior checks job:
  - run dry-run assertions
  - run auth-failure assertions
  - run persistence/mount contract assertions
  - run sensitive-mount startup safety regression assertions
- Version discipline job:
  - validate `VERSION` format
  - enforce version-bump guard for distributed runtime file changes

## CI Principles

- Fail fast on contract regressions.
- Keep job logs actionable and concise.
- Avoid hidden dependencies between jobs.
- Pin tool versions where flakiness risk is high.
