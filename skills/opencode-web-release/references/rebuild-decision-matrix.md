# Image Rebuild Decision Matrix

Use this matrix when deciding whether the Docker image must be rebuilt.

## Rebuild Triggers

Rebuild when any trigger is true:

- Image tag does not exist locally.
- Wrapper version metadata in image does not match local `VERSION`.
- OpenCode version in image does not match expected npm-installed version.
- Playwright build metadata does not match the requested build toggle.
- Playwright package version metadata does not match the expected version when Playwright is enabled.
- Wrangler build metadata does not match the requested build toggle.
- Pull/no-cache flags request rebuild behavior.

## Metadata Requirements

- Store wrapper version in image (for example `/opt/opencode-web-yolo-version`).
- Store OpenCode version in image (for example `/opt/opencode-version`).
- Store optional build toggles in image metadata (for example `/opt/opencode-web-yolo-playwright` and `/opt/opencode-web-yolo-wrangler`).
- Store Playwright installed and expected package versions in image metadata (for example `/opt/opencode-web-yolo-playwright-version` and `/opt/opencode-web-yolo-playwright-expected-version`).
- Pass an explicit `PLAYWRIGHT_VERSION` build arg; the wrapper resolves `@playwright/test` before an enabled build unless an expected version override is supplied.
- Use explicit checks in wrapper logic before launch.

## Decision Rules

- If all metadata checks match and no force flags are set, skip rebuild.
- If any check fails, rebuild before running container.
- Compare Playwright package versions only when the requested Playwright build is enabled; `OPENCODE_WEB_SKIP_VERSION_CHECK=1` skips npm lookup and package-version drift checks. An explicit `OPENCODE_WEB_EXPECTED_PLAYWRIGHT_VERSION` remains the Docker install target during the skip.
- Log exact reason(s) for rebuild to aid diagnostics.
