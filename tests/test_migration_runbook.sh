#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/live/config" "$tmp/live/data" "$tmp/xdg-config" "$tmp/xdg-data"
printf '%s\n' baseline >"$tmp/live/data/history"
printf '%s\n' config >"$tmp/live/config/settings"
ln -s "$tmp/live/config" "$tmp/xdg-config/opencode"
ln -s "$tmp/live/data" "$tmp/xdg-data/opencode"
ln -s history "$tmp/live/data/nested-link"
# Execute the exact documented backup commands, with Docker stubbed only for
# image identity capture. The copy operations and symlinks are real filesystem IO.
mkdir "$tmp/bin"
cat >"$tmp/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${DOCKER_LOG:?}"
if [ "$1" != tag ]; then printf '%s\n' sha256:retained-baseline; fi
EOF
chmod +x "$tmp/bin/docker"
export PATH="$tmp/bin:$PATH" HOME="$tmp" XDG_CONFIG_HOME="$tmp/xdg-config" XDG_DATA_HOME="$tmp/xdg-data"
export DOCKER_LOG="$tmp/docker.log"
commands="$(node -e 'const s=require("node:fs").readFileSync(process.argv[1],"utf8"); console.log(s.match(/```bash\n([\s\S]*?)```/)[1])' "$ROOT_DIR/OPENCODE_2_MIGRATION.md")"
backup='' # Assigned by the documented commands evaluated below.
eval "$commands"
test ! "$backup/trial/data" -ef "$tmp/live/data"
test -L "$backup/trial/data/nested-link"
printf '%s\n' migrated >"$backup/trial/data/history"
test "$(cat "$backup/data/history")" = baseline
test "$(cat "$tmp/live/data/history")" = baseline
test "$(cat "$backup/image-id")" = sha256:retained-baseline
export OPENCODE_SERVER_PASSWORD=ci-rollback-password
commands="$(node -e 'const s=require("node:fs").readFileSync(process.argv[1],"utf8"); console.log([...s.matchAll(/```bash\n([\s\S]*?)```/g)][1][1])' "$ROOT_DIR/OPENCODE_2_MIGRATION.md")"
eval "$commands"
test "$(cat "$backup/restored-data/history")" = baseline
test ! "$backup/restored-data" -ef "$backup/data"
grep -F 'run -d --pull=never' "$DOCKER_LOG" >/dev/null
grep -F 'sha256:retained-baseline opencode serve' "$DOCKER_LOG" >/dev/null
printf '%s\n' 'PASS: exact runbook commands isolate symlinked roots and retain image identity'
