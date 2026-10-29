# OpenCode 2.x migration runbook

Wrapper 0.6.0 resolves scoped `@opencode/cli` once and automatically adopts
canonical exact stable 2.x releases, never 3.x. The release-tested baseline and
direct Docker default are 2.2.1. Advanced operators may set
`OPENCODE_WEB_EXPECTED_OPENCODE_VERSION` to a canonical exact stable `2.x.y`; such overrides
are operator-tested. Registry outages retain compatible exact 2.x image metadata
even for unrelated rebuilds; fresh/incompatible images warn and use baseline 2.2.1.
Skip-version-check preserves compatible image targets on rebuild, unless pinned.
CI covers baseline and current stable 2.x, not every override or migration.
No test guarantees rollback of migrated data: restore pre-upgrade backups.
The old `opencode-ai` package is not the 2.x distribution. Node remains 22.

## Authentication and protocol

Continue setting nonempty `OPENCODE_SERVER_PASSWORD` in the wrapper interface.
The wrapper and image entrypoint copy it into preferred `OPENCODE_PASSWORD`,
overriding any conflicting inherited value. Username is fixed `opencode`;
custom `OPENCODE_SERVER_USERNAME` values fail explicitly. The UI shell/assets are
public so the sign-in page can load. Protected `/api` routes require authentication;
HTTP 200 at `/` does not prove auth is disabled. Check authenticated `GET /api/info`
(JSON `version`), and expect 401 without credentials. SSE is `/api/event`; terminal
websockets use `/api/pty/:id/connect` with a ticket obtained through authenticated
API access. Preserve paths, cookies, authorization and query strings at the proxy.

## Backup, copy-first trial, cutover

1. Disable retention (`OPENCODE_WEB_RETENTION_DAYS=0`); positive values now fail
   fast. Do not attempt to use the legacy 1.18.x retention worker on 2.x.
2. Stop the old container cleanly (`docker stop opencode_web_yolo`). Ensure no
   host OpenCode process or other container is writing the same config/data.
3. Preserve the **running old container's** image ID (not a possibly moved tag)
   and old managed wrapper/config. Record its version and settings. Protect backups
   as secrets: provider credentials are included.
4. With writers stopped, copy **entire** effective config and data directories,
   including hidden files and any SQLite sidecars. Do not copy just `opencode.db`.
   For default paths, for example:

   ```bash
   set -euo pipefail
   umask 077
   backup="$HOME/opencode-pre-v2-$(date +%Y%m%d-%H%M%S)"
   mkdir "$backup" # Must be new, never reuse an existing backup directory.
   mkdir "$backup/trial"
   docker inspect --format '{{.Image}}' opencode_web_yolo >"$backup/image-id"
   saved_image_id="$(cat "$backup/image-id")"
   test "$(docker image inspect --format '{{.Id}}' "$saved_image_id")" = "$saved_image_id"
   docker tag "$saved_image_id" opencode_web_yolo:pre-v2
   # Resolve only the top-level source symlink. Preserve nested symlinks as-is;
   # cp -a on an unresolved root would copy a link back to the live data!
   config_root="$(cd "${XDG_CONFIG_HOME:-$HOME/.config}/opencode" && pwd -P)"
   data_root="$(cd "${XDG_DATA_HOME:-$HOME/.local/share}/opencode" && pwd -P)"
   cp -a "$config_root" "$backup/config"
   cp -a "$data_root" "$backup/data"
   test -d "$backup/config" && test ! -L "$backup/config"
   test -d "$backup/data" && test ! -L "$backup/data"
   test ! "$backup/config" -ef "$config_root"
   test ! "$backup/data" -ef "$data_root"
   cp -a "$backup/config" "$backup/trial/config"
   cp -a "$backup/data" "$backup/trial/data"
   test -d "$backup/trial/config" && test ! -L "$backup/trial/config"
   test -d "$backup/trial/data" && test ! -L "$backup/trial/data"
   test ! "$backup/trial/config" -ef "$backup/config"
   test ! "$backup/trial/data" -ef "$backup/data"
   ```

5. First launch against **trial copies**, never the only backup: set
   `OPENCODE_WEB_CONFIG_DIR="$backup/trial/config"` and
   `OPENCODE_WEB_DATA_DIR="$backup/trial/data"`, a distinct container name and
   port, and disable wrapper self-update during the trial. Confirm with `--dry-run`
   that both host mounts and HOME/XDG write paths agree. Do not run old and new
   versions concurrently on the same state. Review config/plugin compatibility.
   These assertions isolate the top roots only: inventory nested symlinks that
   point outside those roots and snapshot/disable their targets separately before
   trial startup. Never let a trial follow a link into live credentials/state.
6. Sign in, verify provider links, create/read a session, recreate the container
   with the same trial mounts, and verify that session again. Upstream migrates
   v1 histories in the background, resumably: readiness does **not** prove history
   import is complete. Check representative old histories and logs before cutover.
   Large databases may take time and extra disk space; keep the original backup.
7. Cut over using the validated copies and update proxy `/api/event` and
   `/api/pty` routing as shown in README. Preserve localhost-only publication.

## Restore / rollback

Stop the 2.x container and all writers. Preserve failed trial state separately
for investigation. Restore the complete pre-v2 config/data copies to clean
directories with the original ownership. **Do not use the wrapper for rollback:**
skip-update alone does not disable auto-pull, forced compatibility rebuilds, or
package version drift rebuilds. Use the recorded image ID directly with Docker
`--pull=never`, without any build or wrapper self/version-update path:

```bash
set -euo pipefail
# All writers must be stopped; these destinations must not already exist.
test ! -e "$backup/restored-config" && test ! -L "$backup/restored-config"
test ! -e "$backup/restored-data" && test ! -L "$backup/restored-data"
cp -a "$backup/config" "$backup/restored-config"
cp -a "$backup/data" "$backup/restored-data"
test -d "$backup/restored-config" && test ! -L "$backup/restored-config"
test -d "$backup/restored-data" && test ! -L "$backup/restored-data"
test ! "$backup/restored-config" -ef "$backup/config"
test ! "$backup/restored-data" -ef "$backup/data"
saved_image_id="$(cat "$backup/image-id")"
test "$(docker image inspect --format '{{.Id}}' "$saved_image_id")" = "$saved_image_id"
: "${OPENCODE_SERVER_PASSWORD:?Set the mandatory nonempty rollback password}"
export OPENCODE_SERVER_PASSWORD
docker run -d --pull=never --name opencode_web_yolo_restored \
  -p 127.0.0.1:4096:4096 -w /workspace \
  -e LOCAL_UID="$(id -u)" -e LOCAL_GID="$(id -g)" -e LOCAL_USER="$(id -un)" \
  -e OPENCODE_SERVER_PASSWORD -e OPENCODE_SERVER_USERNAME=opencode \
  -e OPENCODE_WEB_RETENTION_DAYS=0 -e OPENCODE_WEB_YOLO_HOME=/home/opencode \
  -e HOME=/home/opencode -e XDG_CONFIG_HOME=/home/opencode/.config \
  -e XDG_DATA_HOME=/home/opencode/.local/share \
  -e XDG_STATE_HOME=/home/opencode/.local/share/opencode/state \
  -v "$PWD:/workspace" \
  -v "$backup/restored-config:/home/opencode/.config/opencode" \
  -v "$backup/restored-data:/home/opencode/.local/share/opencode" \
  "$saved_image_id" opencode serve --hostname 0.0.0.0 --port 4096
test "$(docker inspect --format '{{.Image}}' opencode_web_yolo_restored)" = "$saved_image_id"
```

Use the recorded original UID/GID and workspace when different from the current
operator. Never downgrade by opening
2.x-mutated data in a 1.x binary. Verify histories and provider auth before serving
traffic. Do not delete the backups until migration and rollback have been rehearsed.

## Validation limits

CI exercises the real image's UI/assets, browser password connection/reload,
protected API, SSE, and session create/read across container recreation with host-backed state.
It also imports a deterministic sanitized user/assistant transcript through the real
pinned `opencode-ai@1.19.5` CLI, reads the v1 baseline, clones stopped-writer state,
waits for the v2 migration status to complete, checks exact message text and a
representative model config/dummy API credential, recreates v2 and rechecks, then
restores the pre-v2 copy and reads it with the retained v1 image ID. No real provider
credentials or model requests are used. This proves one baseline, **not** all
historical v1 data/config/plugin migrations or provider conversations.
Browser sign-in and PTY interaction should also be checked through the actual TLS
proxy before production cutover.

Protocol evidence is pinned to upstream tag `v2.2.1` (commit
`3ebcf9a32c7b28f658cfee80775448929361727a`):
[server info](https://github.com/anomalyco/opencode/blob/v2.2.1/packages/protocol/src/groups/server.ts),
[session API](https://github.com/anomalyco/opencode/blob/v2.2.1/packages/protocol/src/groups/session.ts),
[session creation test](https://github.com/anomalyco/opencode/blob/v2.2.1/packages/server/test/session-create.test.ts),
and [fixed username/auth](https://github.com/anomalyco/opencode/blob/v2.2.1/packages/server/src/auth.ts).
Migration completion uses the tagged
[migration status API](https://github.com/anomalyco/opencode/blob/v2.2.1/packages/protocol/src/groups/migration.ts);
the fixture's expected text conversion follows the upstream
[v1 migration tests](https://github.com/anomalyco/opencode/blob/v2.2.1/packages/core/test/v1-migration.test.ts).
The v1 fixture is imported and read with the real 1.19.5 CLI, rather than inserted
directly into SQLite or treated as a mocked server response.
