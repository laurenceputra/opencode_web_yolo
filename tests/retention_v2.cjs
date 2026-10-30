// Deterministic v2.2.1 wire fixtures, including opaque pagination and recursive deletion.
const assert = require('node:assert/strict')
const http = require('node:http')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawn } = require('node:child_process')
const now = 2000000000000
const cutoff = now - 7 * 86400000
const session = (id, parentID, updated = 1) => ({ id, parentID, location: { directory: '/workspace' }, time: { updated } })
async function test(mode) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'retention-v2-'))
  const marker = path.join(dir, 'marker')
  let sessions = [session('root'), session('child', 'root'), session('grand', 'child'), session('archived')]
  sessions[3].time.archived = 1
  if (mode === 'cursor-move') sessions = [session('root'), session('archived'), session('child', 'root')]
  if (mode === 'young') sessions[2].time.updated = cutoff
  if (mode === 'scoped-inboxes') sessions.push(session('recent', undefined, cutoff), session('recent-child', 'recent'))
  if (mode === 'cycle') sessions[0].parentID = 'grand'
  if (mode === 'orphan') sessions[1].parentID = 'missing'
  if (mode === 'duplicate') sessions.push(sessions[0])
  if (mode === 'malformed') sessions[2].time.updated = '1'
  const deletes = []
  const requests = []
  let listings = 0
  let migrations = 0
  const server = http.createServer((req, res) => {
    assert.equal(req.headers.authorization, `Basic ${Buffer.from('opencode:secret').toString('base64')}`)
    const url = new URL(req.url, 'http://localhost')
    requests.push(`${req.method} ${url.pathname}`)
    const send = value => { res.setHeader('content-type', 'application/json'); res.end(JSON.stringify(value)) }
    if (mode === 'timeout') return
    if (url.pathname === '/api/info') return send({ version: mode === 'unsupported' ? '3.0.0' : '2.2.1' })
    if (url.pathname === '/api/experimental/migration/v1') {
      migrations++
      return send({ status: mode === 'migration-change' ? (migrations > 1 ? 'running' : 'completed') : mode.startsWith('migration-') ? mode.slice(10) : 'completed' })
    }
    if (url.pathname === '/api/session') {
      assert.equal(url.searchParams.get('limit'), '100')
      assert.deepEqual([...url.searchParams.keys()].filter(k => k !== 'limit' && k !== 'cursor'), [])
      if (!url.searchParams.has('cursor')) listings++
      if (mode === 'refresh-young' && listings > 1) sessions[2].time.updated = cutoff
      const cursor = url.searchParams.get('cursor')
      if (mode === 'added-descendant' && listings === 2 && !cursor) sessions.push(session('extra', 'grand'))
      if (mode === 'cursor-move' && listings > 1 && cursor) {
        // Between pages the old child becomes recent and moves ahead of the
        // opaque cursor. The refreshed traversal is valid but omits that child.
        sessions.find(s => s.id === 'child').time.updated = cutoff
        return send({ data: [], cursor: {} })
      }
      assert.ok(cursor === null || cursor === 'opaque+/=' || ['terminal-extra', 'real-cursors'].includes(mode) && cursor === 'terminal')
      // Published 2.2.1/2.2.2 return string cursors on nonempty pages, then
      // {previous:null,next:null} on the empty terminal page, not omitted keys.
      if (mode === 'real-cursors') {
        if (cursor === 'terminal' || sessions.length === 0 || cursor && sessions.length <= 2) return send({ data: [], cursor: { previous: null, next: null } })
        return send({ data: cursor ? sessions.slice(2) : sessions.slice(0, 2), cursor: { previous: 'opaque-previous', next: cursor ? 'terminal' : 'opaque+/=' } })
      }
      if (mode === 'null-cursors') return send({ data: sessions, cursor: { previous: null, next: null } })
      if (mode === 'bad-previous') return send({ data: sessions, cursor: { previous: 42, next: null } })
      if (mode === 'empty-previous') return send({ data: sessions, cursor: { previous: '', next: null } })
      if (mode === 'empty-cursor') return send({ data: sessions, cursor: { next: '' } })
      if (mode === 'terminal-extra' && cursor === 'terminal') return send({ data: [], cursor: {} })
      if (mode === 'terminal-extra' && cursor && sessions.length > 2) return send({ data: sessions.slice(2), cursor: { next: 'terminal' } })
      if (mode === 'bad-cursor') return send({ data: sessions, cursor: { next: 42 } })
      if (mode === 'no-cursor') return send({ data: sessions })
      if (mode === 'bad-page') return send({ data: {}, cursor: {} })
      if (mode === 'empty-next') return send({ data: [], cursor: { next: 'opaque+/=' } })
      return send({ data: cursor ? sessions.slice(2) : sessions.slice(0, 2), cursor: sessions.length <= 2 || cursor && mode !== 'loop' ? {} : { next: 'opaque+/=' } })
    }
    if (url.pathname === '/api/session/active') return send({ data: mode === 'unknown' || mode === 'refresh-unknown' && listings > 1 ? { missing: { type: 'running' } } :
      mode === 'running-root' || mode === 'refresh-running-root' && listings > 1 ? { root: { type: 'running' } } :
      mode === 'running' || mode === 'refresh-running' && listings > 1 ? { grand: { type: 'running' } } : mode === 'bad-active' ? [] : {} })
    const match = url.pathname.match(/^\/api\/session\/([^/]+)(\/inbox)?$/)
    if (!match) { res.statusCode = 500; return res.end() }
    const id = match[1]
    if (match[2]) return send({ data: mode === 'bad-inbox' ? {} : mode === 'wrong-inbox' ? [{ id: 'input', sessionID: 'wrong', type: 'synthetic', payload: {}, delivery: 'queue', time: { created: 1 } }] :
      ((mode === 'queued' || mode === 'refresh-queued' && listings > 1) && id === 'grand' ||
        (mode === 'queued-root' || mode === 'refresh-queued-root' && listings > 1) && id === 'root') ?
        [{ id: 'input', sessionID: id, type: 'synthetic', payload: { text: 'work' }, delivery: 'queue', time: { created: 1 } }] : [] })
    if (req.method === 'DELETE') {
      deletes.push(id)
      if (mode !== 'still-present' && mode !== 'child-present') sessions = sessions.filter(s => id === 'root' ? !['root', 'child', 'grand', 'extra'].includes(s.id) : s.id !== id)
      if (mode === 'child-present') sessions = sessions.filter(s => s.id !== id)
      res.statusCode = mode === 'bad-delete' ? 200 : 204
      return res.end()
    }
    const found = sessions.find(s => s.id === id)
    if (!found) { res.statusCode = 404; return res.end('{}') }
    if (listings > 1 && id === 'grand') {
      if (mode === 'direct-young') return send({ data: { ...found, time: { updated: cutoff } } })
      if (mode === 'direct-parent') return send({ data: { ...found, parentID: 'root' } })
      if (mode === 'direct-location') return send({ data: { ...found, location: { directory: '/changed' } } })
      if (mode === 'direct-identity') return send({ data: { ...found, id: 'wrong' } })
      if (mode === 'direct-missing') { res.statusCode = 404; return res.end('{}') }
    }
    send({ data: found })
  })
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
  async function run(extra = {}) {
    return new Promise(resolve => {
      const child = spawn(process.execPath, [path.join(__dirname, '../.opencode_web_yolo_retention.js'), '--run-once'], {
        env: { ...process.env, OPENCODE_SERVER_PASSWORD: 'secret', OPENCODE_WEB_RETENTION_DAYS: '7',
          OPENCODE_WEB_RETENTION_NOW_MS: String(now), OPENCODE_WEB_RETENTION_MARKER: marker,
          OPENCODE_WEB_RETENTION_URL: `http://127.0.0.1:${server.address().port}`,
          OPENCODE_WEB_RETENTION_FETCH_TIMEOUT_MS: mode === 'timeout' ? '100' : '3000',
          OPENCODE_WEB_RETENTION_VERIFY_TIMEOUT_MS: ['still-present', 'child-present'].includes(mode) ? '100' : '3000', ...extra },
      })
      let output = ''
      child.stdout.on('data', data => { output += data })
      child.stderr.on('data', data => { output += data })
      child.on('exit', code => resolve({ code, output }))
    })
  }
  try {
    if (mode === 'preview') {
      assert.equal((await run({ OPENCODE_WEB_RETENTION_DRY_RUN: '1' })).code, 0)
      assert.deepEqual(deletes, [])
      assert.equal(fs.existsSync(marker), false)
    } else {
      const result = await run()
      const failed = ['bad-previous', 'empty-previous', 'empty-cursor', 'cursor-move', 'direct-parent', 'direct-location', 'direct-identity', 'direct-missing', 'cycle', 'orphan', 'duplicate', 'malformed', 'loop', 'bad-cursor', 'no-cursor', 'bad-page', 'empty-next', 'unknown', 'bad-active', 'bad-inbox', 'wrong-inbox', 'unsupported', 'timeout', 'still-present', 'child-present', 'bad-delete'].includes(mode) || mode.startsWith('migration-')
      const shouldFail = failed || mode === 'refresh-unknown'
      assert.equal(result.code, shouldFail ? 1 : 0, `${mode}: ${result.output}`)
      assert.equal(fs.existsSync(marker), !shouldFail, `${mode}: marker`)
      if (!shouldFail) {
        const preserved = ['direct-young', 'young', 'queued', 'running', 'refresh-young', 'refresh-running', 'refresh-queued', 'queued-root', 'running-root', 'refresh-queued-root', 'refresh-running-root'].includes(mode)
        assert.deepEqual(deletes, preserved ? ['archived'] : ['root', 'archived'], mode)
        if (mode === 'normal' || mode === 'added-descendant') {
          const deletion = requests.indexOf('DELETE /api/session/root')
          const direct = requests.lastIndexOf('GET /api/session/grand', deletion)
          const inbox = requests.lastIndexOf('GET /api/session/grand/inbox', deletion)
          const active = requests.lastIndexOf('GET /api/session/active', deletion)
          assert.ok(direct > 0 && direct < inbox && inbox < active && active < deletion, 'direct ages precede final inbox/active checks')
        }
        if (mode === 'added-descendant') assert.equal(requests.filter(r => r === 'GET /api/session/extra').length, 2, 'new descendant directly refreshed and verified deleted')
        if (mode === 'scoped-inboxes') {
          for (const id of ['root', 'child', 'grand', 'archived']) {
            assert.equal(requests.filter(r => r === `GET /api/session/${id}/inbox`).length, 2, `${id}: initial and own candidate scan only`)
          }
          for (const id of ['recent', 'recent-child']) assert.equal(requests.filter(r => r === `GET /api/session/${id}/inbox`).length, 0, 'recent family inboxes never fetched')
          assert.equal(listings, 3, 'complete global listing retained per candidate')
          assert.equal(requests.filter(r => r === 'GET /api/session/active').length, 3, 'global active map retained per candidate')
        }
        const before = listings
        assert.equal((await run()).code, 0)
        assert.equal(listings, before, 'weekly marker avoids API work')
        fs.writeFileSync(marker, String(now + 1))
        const retry = await run()
        assert.equal(retry.code, 0, `${mode}: future markers trigger retry: ${retry.output}`)
      } else if (!['still-present', 'child-present', 'bad-delete'].includes(mode)) assert.deepEqual(deletes, [], mode)
    }
  } finally {
    server.closeAllConnections()
    await new Promise(resolve => server.close(resolve))
    fs.rmSync(dir, { recursive: true, force: true })
  }
}
;(async () => {
  for (const mode of ['normal', 'real-cursors', 'null-cursors', 'bad-previous', 'empty-previous', 'empty-cursor', 'added-descendant', 'cursor-move', 'direct-young', 'direct-parent', 'direct-location', 'direct-identity', 'direct-missing', 'terminal-extra', 'preview', 'young', 'queued', 'running', 'refresh-young', 'refresh-running', 'refresh-queued',
    'scoped-inboxes', 'queued-root', 'running-root', 'refresh-queued-root', 'refresh-running-root', 'refresh-unknown',
    'cycle', 'orphan', 'duplicate', 'malformed', 'loop', 'bad-cursor', 'no-cursor', 'bad-page', 'empty-next', 'unknown', 'bad-active', 'bad-inbox', 'wrong-inbox', 'unsupported', 'timeout',
    'migration-required', 'migration-running', 'migration-error', 'migration-change', 'still-present', 'child-present', 'bad-delete']) await test(mode)
  console.log('PASS: deterministic v2 API retention scenarios')
})().catch(error => { console.error(error); process.exitCode = 1 })
