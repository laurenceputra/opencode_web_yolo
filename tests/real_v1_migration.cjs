// Real pinned CLI migration/restore acceptance, not a SQL or HTTP mock.
// Usage: node tests/real_v1_migration.cjs [local-v1-binary local-v2-binary]
// With no arguments uses CI-built opencode_web_yolo:ci-v1 and :ci images.
const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawn, execFileSync } = require('node:child_process')
const { createHash } = require('node:crypto')
const { setTimeout: sleep } = require('node:timers/promises')
const fixture = path.resolve(__dirname, 'fixtures/v1-session.json')
const session = JSON.parse(fs.readFileSync(fixture)).info
const local = process.argv.length === 4
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'opencode-migration-'))
const baseline = path.join(root, 'baseline')
const trial = path.join(root, 'trial')
const restored = path.join(root, 'restored')
const name = `opencode-migration-${process.pid}`
const port = 14903
const base = `http://127.0.0.1:${port}`
const auth = `Basic ${Buffer.from('opencode:ci-secret').toString('base64')}`
const images = local ? [] : ['opencode_web_yolo:ci-v1', 'opencode_web_yolo:ci'].map(tag =>
  execFileSync('docker', ['image', 'inspect', '--format', '{{.Id}}', tag], { encoding: 'utf8', timeout: 10000 }).trim())
let child
const deadline = setTimeout(() => { console.error('Migration acceptance deadline exceeded'); cleanup(); process.exit(1) }, 240000)

function cli(version, state, args) {
  const env = { ...process.env, HOME: state, XDG_CONFIG_HOME: `${state}/config`, XDG_DATA_HOME: `${state}/data`, XDG_STATE_HOME: `${state}/data/opencode/state`, OPENCODE_SERVER_PASSWORD: 'ci-secret', OPENCODE_PASSWORD: 'ci-secret', OPENCODE_WEB_RETENTION_DAYS: '0' }
  if (local) return { command: process.argv[version === 1 ? 2 : 3], args, env }
  const image = images[version - 1] // Capture IDs once; rollback cannot follow a moving tag.
  return { command: 'docker', args: ['run', '--rm', '--pull=never', '--name', name,
    '-p', `127.0.0.1:${port}:${port}`, '-e', 'OPENCODE_SERVER_PASSWORD=ci-secret', '-e', 'OPENCODE_WEB_RETENTION_DAYS=0',
    '-e', `LOCAL_UID=${process.getuid()}`, '-e', `LOCAL_GID=${process.getgid()}`, '-e', 'LOCAL_USER=ci',
    '-e', 'HOME=/home/opencode', '-e', 'XDG_CONFIG_HOME=/home/opencode/.config', '-e', 'XDG_DATA_HOME=/home/opencode/.local/share',
    '-e', 'XDG_STATE_HOME=/home/opencode/.local/share/opencode/state',
    '-v', `${state}/config/opencode:/home/opencode/.config/opencode`, '-v', `${state}/data/opencode:/home/opencode/.local/share/opencode`,
    '-v', `${fixture}:/fixture.json:ro`, image, 'opencode', ...args.map(x => x === fixture ? '/fixture.json' : x)], env: process.env }
}
function run(version, state, args) {
  const cmd = cli(version, state, args)
  return execFileSync(cmd.command, cmd.args, { env: cmd.env, cwd: root, timeout: 60000, encoding: 'utf8' })
}
async function request(route) {
  const response = await fetch(base + route, { headers: { authorization: auth }, signal: AbortSignal.timeout(5000) })
  assert.equal(response.status, 200, `${route}: ${response.status}`)
  return response.json()
}
async function start(version, state) {
  const cmd = cli(version, state, ['serve', '--hostname', '0.0.0.0', '--port', String(port)])
  child = spawn(cmd.command, cmd.args, { env: cmd.env, cwd: root, stdio: ['ignore', 'inherit', 'inherit'] })
  for (let attempt = 0; attempt < 60; attempt++) {
    if (child.exitCode !== null) throw new Error('Server exited before readiness')
    try {
      const info = await request(version === 1 ? '/global/health' : '/api/info')
      assert.equal(info.version, version === 1 ? '1.19.5' : '2.2.1')
      if (!local) assert.equal(execFileSync('docker', ['inspect', '--format', '{{.Image}}', name], { encoding: 'utf8', timeout: 10000 }).trim(), images[version - 1])
      return
    } catch { await sleep(500) }
  }
  throw new Error('Server readiness timed out')
}
async function stop() {
  const processToStop = child
  if (!processToStop) return
  if (!local) execFileSync('docker', ['stop', '--time', '10', name], { timeout: 20000 })
  else processToStop.kill('SIGTERM')
  await Promise.race([new Promise(resolve => processToStop.once('exit', resolve)), sleep(15000).then(() => { if (processToStop.exitCode === null && processToStop.signalCode === null) throw new Error('Server did not stop'); })])
  child = undefined
}
function cleanup() {
  if (child) {
    if (local) child.kill('SIGKILL')
    else { try { execFileSync('docker', ['rm', '-f', name], { timeout: 15000, stdio: 'ignore' }) } catch {} }
  }
}
function snapshot(directory) {
  return Object.fromEntries(fs.readdirSync(directory, { recursive: true }).sort().map(file => {
    const full = path.join(directory, file)
    const stat = fs.lstatSync(full)
    return [file, stat.isFile() ? createHash('sha256').update(fs.readFileSync(full)).digest('hex') : stat.isSymbolicLink() ? fs.readlinkSync(full) : 'directory']
  }))
}
async function checkV1() {
  const info = await request(`/session/${session.id}`)
  assert.equal(info.title, session.title)
  const messages = await request(`/session/${session.id}/message`)
  assert.deepEqual(messages.map(m => [m.info.role, m.parts[0].text]), [
    ['user', 'Sanitized migration question'], ['assistant', 'Sanitized migration answer'],
  ])
  assert.equal((await request('/config')).model, 'openai/gpt-4o-mini')
}
async function checkV2() {
  for (let attempt = 0; attempt < 120; attempt++) {
    const status = await request('/api/experimental/migration/v1')
    assert.notEqual(status.status, 'error', JSON.stringify(status))
    if (status.status === 'completed') break
    assert.notEqual(attempt, 119, 'History migration did not complete')
    await sleep(500)
  }
  assert.equal((await request(`/api/session/${session.id}`)).data.title, session.title)
  const messages = (await request(`/api/session/${session.id}/context`)).data
  assert.equal(messages.find(m => m.id === 'msg_000000000001aaaaaaaaaaaaaa').text, 'Sanitized migration question')
  assert.equal(messages.find(m => m.id === 'msg_000000000002aaaaaaaaaaaaaa').content[0].text, 'Sanitized migration answer')
  // No live credentials: assert the sentinel is actually imported, not just that
  // auth.json remains on disk. Never print real credential API responses.
  const credentials = await request('/api/credential')
  assert.ok(JSON.stringify(credentials).includes('ci-not-a-real-key'))
  const config = await request('/api/config')
  assert.ok(JSON.stringify(config).includes('gpt-4o-mini'))
}
async function main() {
  fs.mkdirSync(`${baseline}/config/opencode`, { recursive: true })
  fs.mkdirSync(`${baseline}/data/opencode`, { recursive: true })
  fs.writeFileSync(`${baseline}/config/opencode/opencode.json`, JSON.stringify({ model: 'openai/gpt-4o-mini' }))
  fs.writeFileSync(`${baseline}/data/opencode/auth.json`, JSON.stringify({ openai: { type: 'api', key: 'ci-not-a-real-key' } }), { mode: 0o600 })
  assert.match(run(1, baseline, ['import', fixture]), /Imported session/)
  await start(1, baseline)
  await checkV1()
  await stop() // Only stopped, fully materialized v1 state is cloned.
  const original = snapshot(baseline)
  fs.cpSync(baseline, trial, { recursive: true })
  await start(2, trial)
  await checkV2()
  await stop()
  await start(2, trial)
  await checkV2() // Imported content and credentials survive process/container recreation.
  await stop()
  assert.deepEqual(snapshot(baseline), original, 'Trial must not alter original v1 state')
  fs.cpSync(baseline, restored, { recursive: true })
  await start(1, restored)
  await checkV1() // Restore pre-v2 copy, never downgrade v2-mutated state.
  assert.equal(JSON.parse(fs.readFileSync(`${restored}/data/opencode/auth.json`)).openai.key, 'ci-not-a-real-key')
  await stop()
  console.log('PASS: real 1.19.5 baseline, 2.2.1 history/config/auth migration, recreation, and v1 restore')
}
main().catch(error => { console.error(error); process.exitCode = 1 }).finally(() => {
  clearTimeout(deadline)
  cleanup()
  fs.rmSync(root, { recursive: true, force: true })
})
