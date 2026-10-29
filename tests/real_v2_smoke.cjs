// Real-server acceptance, not a mock. Run against the CI-built image only.
// Schema source: upstream v2.2.1 packages/server/test/session-create.test.ts.
const assert = require('node:assert/strict')
const fs = require('node:fs')

const [base, mode, stateFile] = process.argv.slice(2)
const auth = `Basic ${Buffer.from('opencode:ci-secret').toString('base64')}`
async function request(path, options = {}) {
  return fetch(new URL(path, base), { signal: AbortSignal.timeout(15000), ...options })
}
async function main() {
  assert.equal((await request('/api/info')).status, 401)
  assert.equal((await request('/api/info', { headers: { authorization: 'Basic b3BlbmNvZGU6d3Jvbmc=' } })).status, 401)
  const info = await request('/api/info', { headers: { authorization: auth } })
  assert.equal(info.status, 200)
  assert.equal((await info.json()).version, process.env.OPENCODE_TEST_VERSION || '2.2.1')
  if (mode === 'create') {
    const ui = await request('/')
    assert.equal(ui.status, 200)
    assert.match(ui.headers.get('content-type'), /text\/html/)
    const html = await ui.text()
    const scripts = [...html.matchAll(/<script\b[^>]*src=["']([^"']+)["']/g)].map(match => match[1])
    assert.ok(scripts.length > 0, 'UI must reference bundled scripts')
    for (const path of scripts) {
      assert.equal(new URL(path, base).origin, new URL(base).origin)
      const asset = await request(path)
      assert.equal(asset.status, 200)
      assert.match(asset.headers.get('content-type'), /javascript/)
      assert.ok((await asset.text()).length > 0)
    }
    const stream = await request('/api/event', { headers: { authorization: auth } })
    assert.equal(stream.status, 200)
    assert.match(stream.headers.get('content-type'), /text\/event-stream/)
    const reader = stream.body.getReader()
    const first = await reader.read()
    assert.equal(first.done, false)
    assert.ok(first.value.length > 0)
    await reader.cancel()
    const created = await request('/api/session', {
      method: 'POST',
      headers: { authorization: auth, 'content-type': 'application/json' },
      body: JSON.stringify({ title: 'CI persistent session', location: { directory: '/workspace' } }),
    })
    assert.equal(created.status, 200, await created.clone().text())
    const session = (await created.json()).data
    assert.equal(typeof session.id, 'string')
    fs.writeFileSync(stateFile, session.id, { mode: 0o600 })
  }
  const id = fs.readFileSync(stateFile, 'utf8')
  const response = await request(`/api/session/${encodeURIComponent(id)}`, { headers: { authorization: auth } })
  assert.equal(response.status, 200)
  const session = (await response.json()).data
  assert.equal(session.id, id)
  assert.equal(session.title, 'CI persistent session')
  console.log(`PASS: real OpenCode 2.x ${mode}`)
}
main().catch(error => { console.error(error); process.exitCode = 1 })
