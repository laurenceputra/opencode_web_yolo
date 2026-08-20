# Image Rebuild Decision Matrix

Use this matrix when deciding whether the Docker image must be rebuilt.

## Rebuild Triggers

Rebuild when any trigger is true:

- Image tag does not exist locally.
- Wrapper version metadata in image does not match local `VERSION`.
- OpenCode version in image does not match expected npm-installed version.
- Playwright build metadata does not match the requested build toggle.
- Wrangler build metadata does not match the requested build toggle.
- Pull/no-cache flags request rebuild behavior.

## Metadata Requirements

- Store wrapper version in image (for example `/opt/opencode-web-yolo-version`).
- Store OpenCode version in image (for example `/opt/opencode-version`).
- Store optional build toggles in image metadata (for example `/opt/opencode-web-yolo-playwright` and `/opt/opencode-web-yolo-wrangler`).
- Use explicit checks in wrapper logic before launch.

## Decision Rules

- If all metadata checks match and no force flags are set, skip rebuild.
- If any check fails, rebuild before running container.
- Log exact reason(s) for rebuild to aid diagnostics.
