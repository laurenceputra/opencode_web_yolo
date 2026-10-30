const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const http = require('node:http')
const { spawn } = require('node:child_process')
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'retention-lifecycle-'))
const app = path.join(dir, 'app.cjs')
const worker = path.join(dir, 'worker.cjs')
fs.writeFileSync(app, `const fs = require('node:fs'); fs.writeFileSync(process.env.APP_PID, String(process.pid));
for (const signal of ['SIGTERM', 'SIGINT']) process.on(signal, () => { fs.writeFileSync(process.env.SIGNAL_FILE, signal); process.exit(23) });
setInterval(() => {}, 1000); if (process.env.NATURAL_EXIT) setTimeout(() => process.exit(23), 500);`)
fs.writeFileSync(worker, `require('node:fs').writeFileSync(process.env.WORKER_PID, String(process.pid));
if (process.env.LONG_WORKER) setInterval(() => {}, 1000);`)
const delay = ms => new Promise(resolve => setTimeout(resolve, ms))
async function until(check) {
  for (let i = 0; i < 200; i++) { if (check()) return; await delay(25) }
  throw new Error('lifecycle wait timed out')
}
const running = pid => { try { process.kill(pid, 0); return true } catch { return false } }
async function main() {
  const server = http.createServer((req, res) => {
    assert.equal(req.url, '/api/info')
    assert.equal(req.headers.authorization, `Basic ${Buffer.from('opencode:secret').toString('base64')}`)
    res.end('{"version":"2.2.1"}')
  })
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
  try {
    for (const mode of ['natural', 'TERM-worker', 'INT-worker', 'TERM-sleep', 'INT-sleep']) {
      const appPID = path.join(dir, `app-${mode}`)
      const workerPID = path.join(dir, `worker-${mode}`)
      const signalFile = path.join(dir, `signal-${mode}`)
      const runtime = spawn('bash', [path.join(__dirname, '../.opencode_web_yolo_runtime.sh'), process.execPath, app], {
        env: { ...process.env, OPENCODE_WEB_RETENTION_DAYS: '1', OPENCODE_WEB_RETENTION_POLL_SECONDS: '3600',
          OPENCODE_WEB_RETENTION_URL: `http://127.0.0.1:${server.address().port}`, OPENCODE_WEB_RETENTION_HELPER: worker,
          OPENCODE_SERVER_PASSWORD: 'secret', APP_PID: appPID, WORKER_PID: workerPID, SIGNAL_FILE: signalFile,
          LONG_WORKER: mode.endsWith('worker') ? '1' : '', NATURAL_EXIT: mode === 'natural' ? '1' : '' },
        stdio: 'ignore',
      })
      const exited = new Promise(resolve => runtime.on('exit', resolve))
      let sleepPID
      try {
        await until(() => fs.existsSync(workerPID))
        if (mode !== 'natural') {
          if (mode.endsWith('sleep')) {
            if (process.platform === 'linux') {
              const readProc = file => { try { return fs.readFileSync(file, 'utf8') } catch (error) { if (error.code === 'ENOENT') return ''; throw error } }
              const children = pid => readProc(`/proc/${pid}/task/${pid}/children`).trim().split(/\s+/).filter(Boolean)
              await until(() => {
                for (const scheduler of children(runtime.pid)) {
                  for (const child of children(scheduler)) {
                    if (readProc(`/proc/${child}/comm`).trim() === 'sleep') sleepPID = Number(child)
                  }
                }
                return sleepPID !== undefined
              })
            } else await delay(100)
          }
          runtime.kill(mode.startsWith('INT') ? 'SIGINT' : 'SIGTERM')
        }
        const status = await Promise.race([exited, delay(5000).then(() => { throw new Error(`${mode}: shutdown timeout`) })])
        assert.equal(status, 23, mode)
        if (mode !== 'natural') assert.equal(fs.readFileSync(signalFile, 'utf8'), mode.startsWith('INT') ? 'SIGINT' : 'SIGTERM')
        for (const file of [appPID, workerPID]) assert.equal(running(Number(fs.readFileSync(file, 'utf8'))), false, `${mode}: child reaped`)
        if (sleepPID) assert.equal(running(sleepPID), false, `${mode}: scheduler sleep reaped`)
      } finally { if (runtime.exitCode === null) runtime.kill('SIGTERM') }
    }
    console.log('PASS: supervisor readiness, worker/sleep shutdown, TERM/INT and app status')
  } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)) }
}
main().catch(error => { console.error(error); process.exitCode = 1 }).finally(() => fs.rmSync(dir, { recursive: true, force: true }))
