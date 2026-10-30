// Isolated real-image retention acceptance (or OPENCODE_TEST_CLI local binary).
// All session fixtures use public APIs,
// and only the worker clock is overridden; no database editing or provider calls.
const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { execFileSync, spawn } = require('node:child_process')
const net = require('node:net')
const cli = process.env.OPENCODE_TEST_CLI
const dir = fs.mkdtempSync(path.join(process.env.OPENCODE_TEST_TMPDIR || os.tmpdir(), 'real-retention-'))
const name = `opencode-retention-${process.pid}`
const docker = (...args) => execFileSync('docker', args, { encoding: 'utf8', timeout: 90000 })
const home = '/home/opencode'
const data = `${home}/.local/share/opencode`
const marker = path.join(dir, cli ? 'data/opencode/state/session-retention.last-success' : 'data/state/session-retention.last-success')
const workspace = cli ? path.join(dir, 'workspace') : '/workspace'
const localEnv = { ...process.env, HOME: path.join(dir, 'home'), XDG_CONFIG_HOME: path.join(dir, 'config'),
  XDG_DATA_HOME: path.join(dir, 'data'), XDG_STATE_HOME: path.dirname(marker),
  OPENCODE_PASSWORD: 'ci-secret', OPENCODE_SERVER_PASSWORD: 'ci-secret', OPENCODE_SERVER_USERNAME: 'opencode' }
let localServer
let localLogs = ''
let base
async function request(route, method = 'GET', body) {
  const response = await fetch(new URL(route, base), { method, signal: AbortSignal.timeout(15000),
    headers: { authorization: `Basic ${Buffer.from('opencode:ci-secret').toString('base64')}`, 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body) })
  return response
}
async function start() {
  if (cli) {
    const socket = net.createServer()
    await new Promise(resolve => socket.listen(0, '127.0.0.1', resolve))
    const port = socket.address().port
    await new Promise(resolve => socket.close(resolve))
    base = `http://127.0.0.1:${port}`
    localServer = spawn(cli, ['serve', '--hostname', '127.0.0.1', '--port', String(port)], { env: localEnv, cwd: workspace })
    localServer.stdout.on('data', data => { localLogs += data })
    localServer.stderr.on('data', data => { localLogs += data })
  } else {
    docker('run', '-d', '--name', name, '-p', '127.0.0.1::4096',
      '-e', `LOCAL_UID=${process.getuid()}`, '-e', `LOCAL_GID=${process.getgid()}`, '-e', 'LOCAL_USER=ci',
      '-e', 'OPENCODE_SERVER_PASSWORD=ci-secret', '-e', 'OPENCODE_WEB_RETENTION_DAYS=0',
      '-e', `HOME=${home}`, '-e', `XDG_CONFIG_HOME=${home}/.config`, '-e', `XDG_DATA_HOME=${home}/.local/share`,
      '-e', `XDG_STATE_HOME=${data}/state`, '-v', `${dir}/config:${home}/.config/opencode`,
      '-v', `${dir}/data:${data}`, 'opencode_web_yolo:ci', 'opencode', 'serve', '--hostname', '0.0.0.0', '--port', '4096')
    const port = docker('port', name, '4096/tcp').trim().split(':').pop()
    base = `http://127.0.0.1:${port}`
  }
  for (let attempt = 0; attempt < 60; attempt++) {
    try {
      const response = await request('/api/experimental/migration/v1')
      if (response.ok && (await response.json()).status === 'completed') return
    } catch {}
    await new Promise(resolve => setTimeout(resolve, 1000))
  }
  throw new Error('real server/migration readiness timed out')
}
async function stop() {
  if (!cli) {
    docker('stop', name)
    docker('rm', name)
  } else if (localServer && localServer.exitCode === null && localServer.signalCode === null) {
    const exited = new Promise(resolve => localServer.once('exit', resolve))
    localServer.kill('SIGTERM')
    const timer = setTimeout(() => localServer.kill('SIGKILL'), 10000)
    await exited
    clearTimeout(timer)
  }
}
async function create(parentID) {
  const response = await request('/api/session', 'POST', parentID ? { parentID } : { location: { directory: workspace } })
  assert.equal(response.status, 200, await response.clone().text())
  return (await response.json()).data
}
async function exists(id, expected) {
  assert.equal((await request(`/api/session/${id}`)).status, expected ? 200 : 404, id)
}
async function main() {
  fs.mkdirSync(path.join(dir, 'config'))
  fs.mkdirSync(path.join(dir, 'data'))
  if (cli) {
    fs.mkdirSync(path.join(dir, 'home'))
    fs.mkdirSync(workspace)
  }
  await start()
  const root = await create()
  const child = await create(root.id)
  const grand = await create(child.id)
  const archived = await create()
  assert.equal((await request(`/api/session/${archived.id}`, 'PATCH', { archived: true })).status, 204)
  const protectedRoot = await create()
  const queuedRoot = await create()
  const queuedChild = await create(queuedRoot.id)
  const queued = await request(`/api/session/${queuedChild.id}/synthetic`, 'POST', { text: 'parked acceptance work', delivery: 'queue', resume: false })
  assert.equal(queued.status, 200, await queued.clone().text())
  const old = [root, child, grand, archived, protectedRoot, queuedRoot, queuedChild]
  // Capture all real update times after archive/input mutations.
  const times = await Promise.all(old.map(async s => (await (await request(`/api/session/${s.id}`)).json()).data.time.updated))
  const cutoff = Math.max(...times) + 1
  while (Date.now() <= cutoff) await new Promise(resolve => setTimeout(resolve, 10))
  const recentChild = await create(protectedRoot.id)
  assert.ok(recentChild.time.updated >= cutoff)
  const clock = String(cutoff + 7 * 86400000)
  const listing = await request('/api/session?limit=100')
  assert.equal(listing.status, 200)
  const cursor = (await listing.json()).cursor
  if (cursor.next) {
    const terminal = await request(`/api/session?limit=100&cursor=${encodeURIComponent(cursor.next)}`)
    assert.equal(terminal.status, 200)
    const page = await terminal.json()
    assert.deepEqual(page.data, [], 'small fixture reaches an empty terminal page')
    console.log(`Real terminal session cursor: ${JSON.stringify(page.cursor)}`)
  }
  const worker = preview => cli ? execFileSync(process.execPath, [path.join(__dirname, '../.opencode_web_yolo_retention.js'), '--run-once'], {
    encoding: 'utf8', timeout: 90000, env: { ...localEnv, OPENCODE_WEB_RETENTION_DAYS: '7',
      OPENCODE_WEB_RETENTION_NOW_MS: clock, OPENCODE_WEB_RETENTION_DRY_RUN: preview ? '1' : '0', OPENCODE_WEB_RETENTION_URL: base },
  }) : docker('exec', '--user', `${process.getuid()}:${process.getgid()}`,
    '-e', 'OPENCODE_WEB_RETENTION_DAYS=7', '-e', `OPENCODE_WEB_RETENTION_NOW_MS=${clock}`,
    '-e', `OPENCODE_WEB_RETENTION_DRY_RUN=${preview ? 1 : 0}`, name,
    'node', '/usr/local/bin/opencode_web_yolo_retention.js', '--run-once')
  assert.match(worker(true), /dry-run: 2 /)
  assert.equal(fs.existsSync(marker), false)
  for (const s of old) await exists(s.id, true)
  assert.match(worker(false), /deleted 2 /)
  const deleted = [root, child, grand, archived]
  const retained = [protectedRoot, recentChild, queuedRoot, queuedChild]
  for (const s of deleted) await exists(s.id, false)
  for (const s of retained) await exists(s.id, true)
  assert.equal(fs.readFileSync(marker, 'utf8').trim(), clock)
  assert.equal(fs.statSync(marker).uid, process.getuid(), 'marker written as mapped user on host mount')
  await stop()
  await start()
  for (const s of deleted) await exists(s.id, false)
  for (const s of retained) await exists(s.id, true)
  assert.ok((await (await request(`/api/session/${queuedChild.id}/inbox`)).json()).data.length > 0)
  assert.match(worker(false), /not due/)
  assert.equal(fs.readFileSync(marker, 'utf8').trim(), clock)
  console.log('PASS: real v2 retention preview, recursive/archived deletion, young/queued preservation and recreation')
}
main().catch(error => {
  console.error(error)
  if (cli) console.error(localLogs)
  else try { console.error(docker('logs', name)) } catch {}
  process.exitCode = 1
}).finally(async () => {
  if (cli) await stop()
  else try { docker('rm', '-f', name) } catch {}
  fs.rmSync(dir, { recursive: true, force: true })
})
