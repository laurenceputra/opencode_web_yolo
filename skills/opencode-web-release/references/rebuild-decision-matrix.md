# Image Rebuild Decision Matrix

Use this matrix when deciding whether the Docker image must be rebuilt.

## Rebuild Triggers

Rebuild when any trigger is true:

- Image tag does not exist locally.
- Wrapper version metadata in image does not match local `VERSION`.
- OpenCode version in image does not match expected npm-installed version.
- Node runtime metadata is missing, malformed, or not major 22.
- Playwright build metadata does not match the requested build toggle.
- Playwright package version metadata does not match the expected version when Playwright is enabled.
- Wrangler build metadata does not match the requested build toggle.
- Pull/no-cache flags request rebuild behavior.

## Metadata Requirements

- Store wrapper version in image (for example `/opt/opencode-web-yolo-version`).
- Store OpenCode version in image (for example `/opt/opencode-version`).
- Store optional build toggles in image metadata (for example `/opt/opencode-web-yolo-playwright` and `/opt/opencode-web-yolo-wrangler`).
- Store Playwright installed and expected package versions in image metadata (for example `/opt/opencode-web-yolo-playwright-version` and `/opt/opencode-web-yolo-playwright-expected-version`).
- Pass a wrapper-owned `PLAYWRIGHT_VERSION` build arg; enabled builds resolve the current `@playwright/test` npm version, while skipped checks use the release fallback, without a user package-version override.
- Use explicit checks in wrapper logic before launch.
- A compatibility/version-driven rebuild must pass Docker `--pull`, regardless of auto-pull or
  `--no-pull` controls, so old base images cannot be reused.
- This mandatory override is limited to a missing image, wrapper release drift, or malformed/
  missing/non-22 Node metadata; OpenCode, Playwright, and Wrangler drift do not override an
  explicit `--no-pull`.

## Decision Rules

- If all metadata checks match and no force flags are set, skip rebuild.
- If any check fails, rebuild before running container.
- Compare Playwright package versions only when the requested Playwright build is enabled; `OPENCODE_WEB_SKIP_VERSION_CHECK=1` skips npm lookup and package-version drift checks. The package version remains release-selected rather than user-configurable.
- Log exact reason(s) for rebuild to aid diagnostics.
