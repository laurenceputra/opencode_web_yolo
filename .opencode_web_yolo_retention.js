#!/usr/bin/env node

const fs = require("node:fs")
const path = require("node:path")

const WEEK_MS = 7n * 24n * 60n * 60n * 1000n
const PAGE_LIMIT = 100
const DEFAULT_FETCH_TIMEOUT_MS = 10000
const DEFAULT_VERIFY_TIMEOUT_MS = 10000
const VERIFY_POLL_MS = 250

function log(message) {
  process.stdout.write(`[opencode_web_yolo retention] ${message}\n`)
}

function fail(message) {
  process.stderr.write(`[opencode_web_yolo retention] ERROR: ${message}\n`)
  process.exitCode = 1
}

function isTrue(value) {
  return ["1", "true", "yes", "on"].includes(String(value || "").toLowerCase())
}

function positiveInteger(name, fallback) {
  const value = process.env[name] ?? String(fallback)
  if (!/^[1-9][0-9]*$/.test(value)) {
    throw new Error(`${name} must be a positive integer`)
  }
  const result = Number(value)
  if (!Number.isSafeInteger(result) || result > 2147483647) {
    throw new Error(`${name} is outside the supported positive integer range`)
  }
  return result
}

function retentionDays() {
  const value = process.env.OPENCODE_WEB_RETENTION_DAYS
  if (!/^[0-9]+$/.test(value || "")) {
    throw new Error("OPENCODE_WEB_RETENTION_DAYS must be a non-negative integer")
  }
  return BigInt(value)
}

function stateMarkerPath() {
  const stateHome = process.env.XDG_STATE_HOME || `${process.env.XDG_DATA_HOME || `${process.env.HOME}/.local/share`}/opencode/state`
  return process.env.OPENCODE_WEB_RETENTION_MARKER || path.join(stateHome, "session-retention.last-success")
}

function markerTime(marker) {
  try {
    const value = fs.readFileSync(marker, "utf8").trim()
    return /^[0-9]+$/.test(value) ? BigInt(value) : undefined
  } catch (error) {
    if (error && error.code === "ENOENT") return undefined
    throw new Error(`cannot read success marker ${marker}: ${error.message}`)
  }
}

function due(marker, now) {
  const previous = markerTime(marker)
  return previous === undefined || now < previous || now - previous >= WEEK_MS
}

function writeMarker(marker, now) {
  fs.mkdirSync(path.dirname(marker), { recursive: true })
  const temporary = `${marker}.tmp-${process.pid}`
  fs.writeFileSync(temporary, `${now}\n`, { mode: 0o600 })
  fs.renameSync(temporary, marker)
}

function baseUrl() {
  return new URL(
    process.env.OPENCODE_WEB_RETENTION_URL || `http://127.0.0.1:${process.env.OPENCODE_WEB_PORT || "4096"}`,
  )
}

function authHeaders() {
  const username = process.env.OPENCODE_SERVER_USERNAME || "opencode"
  const password = process.env.OPENCODE_SERVER_PASSWORD || ""
  return {
    Authorization: `Basic ${Buffer.from(`${username}:${password}`).toString("base64")}`,
    Accept: "application/json",
  }
}

async function requestJson(route, options = {}, query = {}) {
  const url = new URL(route, baseUrl())
  for (const [key, value] of Object.entries(query)) {
    if (value !== undefined) url.searchParams.set(key, String(value))
  }

  let response
  const timeoutMs = options.timeoutMs ?? positiveInteger("OPENCODE_WEB_RETENTION_FETCH_TIMEOUT_MS", DEFAULT_FETCH_TIMEOUT_MS)
  try {
    response = await fetch(url, {
      method: options.method || "GET",
      headers: authHeaders(),
      signal: AbortSignal.timeout(timeoutMs),
    })
    if (response.status === 404 && options.expectNotFound === true) {
      return { notFound: true, headers: response.headers }
    }
    if (!response.ok) {
      throw new Error(`OpenCode API returned HTTP ${response.status} for ${route}`)
    }
    if (options.noContent) {
      if (response.status !== 204 || await response.text() !== "") {
        throw new Error(`OpenCode API returned incompatible deletion response for ${route}`)
      }
      return
    }
    const body = await response.text()

    try {
      return { value: JSON.parse(body), headers: response.headers }
    } catch {
      throw new Error(`OpenCode API returned incompatible JSON for ${route}`)
    }
  } catch (error) {
    if (error?.name === "TimeoutError" || error?.name === "AbortError") {
      throw new Error(`OpenCode API request timed out for ${route} after ${timeoutMs}ms`)
    }
    if (error instanceof Error && error.message.startsWith("OpenCode API returned ")) throw error
    throw new Error(`OpenCode API request failed for ${route}: ${error.message}`)
  }
}

function validateSession(session) {
  if (!isObject(session) || typeof session.id !== "string" || !session.id.length) {
    throw new Error("OpenCode global session API returned a malformed session")
  }
  if (
    session.parentID !== undefined &&
    session.parentID !== null &&
    (typeof session.parentID !== "string" || session.parentID.length === 0)
  ) {
    throw new Error("OpenCode session API returned an invalid parentID")
  }
  if (!isObject(session.location) || typeof session.location.directory !== "string" || !session.location.directory.startsWith("/") || !isObject(session.time) || typeof session.time.updated !== "number") {
    throw new Error("OpenCode global session API returned a session without location/time.updated")
  }
  if (!Number.isSafeInteger(session.time.updated) || session.time.updated < 0) {
    throw new Error("OpenCode global session API returned an invalid time.updated")
  }
}

async function listSessions() {
  const sessions = []
  let cursor
  const seenCursors = new Set()

  for (let pageNumber = 0; pageNumber < 10000; pageNumber += 1) {
    const result = await requestJson("/api/session", {}, {
      limit: PAGE_LIMIT,
      cursor,
    })
    if (!Array.isArray(result.value?.data) || !isObject(result.value.cursor)) {
      throw new Error("OpenCode global session API is incompatible: expected a session array")
    }
    result.value.data.forEach(validateSession)
    sessions.push(...result.value.data)

    const nextCursor = result.value.cursor.next
    const previous = result.value.cursor.previous
    if (previous !== undefined && previous !== null && (typeof previous !== "string" || !previous.length)) throw new Error("invalid previous cursor")
    if (nextCursor === undefined || nextCursor === null) return sessions
    if (typeof nextCursor !== "string" || !nextCursor.length || !result.value.data.length) {
      throw new Error("OpenCode global session API returned an invalid pagination cursor")
    }
    if (seenCursors.has(nextCursor) || nextCursor === cursor) {
      throw new Error("OpenCode global session API returned a repeated pagination cursor")
    }
    seenCursors.add(nextCursor)
    cursor = nextCursor
  }

  throw new Error("OpenCode global session API pagination exceeded the safety limit")
}

function buildHierarchy(sessions) {
  const byID = new Map()
  for (const session of sessions) {
    if (byID.has(session.id)) {
      throw new Error(`OpenCode global session API returned duplicate session ID ${session.id}`)
    }
    byID.set(session.id, session)
  }

  const rootByID = new Map()
  const resolving = new Set()
  const resolveRoot = (sessionID) => {
    if (rootByID.has(sessionID)) return rootByID.get(sessionID)
    if (resolving.has(sessionID)) {
      throw new Error("OpenCode global session API returned a cyclic session hierarchy")
    }
    const session = byID.get(sessionID)
    if (!session) {
      throw new Error(`OpenCode global session API is missing parent session ${sessionID}`)
    }
    resolving.add(sessionID)
    const rootID = session.parentID === undefined || session.parentID === null
      ? session.id
      : resolveRoot(session.parentID)
    resolving.delete(sessionID)
    rootByID.set(sessionID, rootID)
    return rootID
  }

  for (const session of sessions) resolveRoot(session.id)
  return {
    sessions,
    byID,
    rootByID,
  }
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function validateStatusMap(statuses) {
  if (!statuses || typeof statuses !== "object" || Array.isArray(statuses)) {
    throw new Error("OpenCode session status API returned an incompatible response")
  }
  for (const status of Object.values(statuses)) {
    if (!status || status.type !== "running") {
      throw new Error("OpenCode session status API returned an unknown status")
    }
  }
  return statuses
}

async function activeRoots(hierarchy) {
  const active = new Set()
  for (const session of hierarchy.sessions) {
    const inbox = (await requestJson(`/api/session/${encodeURIComponent(session.id)}/inbox`)).value?.data
    if (!Array.isArray(inbox)) throw new Error("OpenCode inbox API returned an incompatible response")
    const ids = new Set()
    for (const item of inbox) {
      if (!isObject(item) || typeof item.id !== "string" || !item.id.length || ids.has(item.id) ||
          item.sessionID !== session.id || !["user", "synthetic", "compaction", "move"].includes(item.type) ||
          !["queue", "steer"].includes(item.delivery) || !isObject(item.payload) ||
          !Number.isSafeInteger(item.time?.created) || item.time.created < 0) {
        throw new Error("OpenCode inbox API returned malformed queued work")
      }
      ids.add(item.id)
    }
    if (inbox.length) active.add(hierarchy.rootByID.get(session.id))
  }
  // Foreground activity is sampled last to narrow (not eliminate) the race.
  const result = await requestJson("/api/session/active")
  const status = validateStatusMap(result.value?.data)
  for (const sessionID of Object.keys(status)) {
    const rootID = hierarchy.rootByID.get(sessionID)
    if (!rootID) {
      throw new Error(`OpenCode session status API returned an unmapped session ${sessionID}`)
    }
    active.add(rootID)
  }
  return active
}

async function getSession(sessionID, expectNotFound = false, timeoutMs) {
  return requestJson(`/api/session/${encodeURIComponent(sessionID)}`, {
    expectNotFound,
    timeoutMs,
  })
}

function validateSessionResponse(result, sessionID) {
  if (result.notFound) return undefined
  validateSession(result.value?.data)
  if (result.value.data.id !== sessionID) {
    throw new Error(`OpenCode session API returned a mismatched session for ${sessionID}`)
  }
  return result.value.data
}

async function verifyDeleted(sessionID, timeoutMs) {
  const deadline = Date.now() + timeoutMs
  while (true) {
    const remaining = Math.max(1, deadline - Date.now())
    const fetchTimeout = positiveInteger("OPENCODE_WEB_RETENTION_FETCH_TIMEOUT_MS", DEFAULT_FETCH_TIMEOUT_MS)
    const result = await getSession(sessionID, true, Math.min(remaining, fetchTimeout))
    if (result.notFound) return
    validateSessionResponse(result, sessionID)
    if (Date.now() >= deadline) {
      throw new Error(`session ${sessionID} remained present after deletion verification`)
    }
    await new Promise((resolve) => setTimeout(resolve, Math.min(VERIFY_POLL_MS, Math.max(1, deadline - Date.now()))))
  }
}

async function checkServerCapability() {
  const result = await requestJson("/api/info")
  if (!result.value || typeof result.value.version !== "string") {
    throw new Error("OpenCode info API is incompatible")
  }
  if (!/^2\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.test(result.value.version)) {
    throw new Error(`OpenCode version ${result.value.version} is unsupported; retention requires stable 2.x APIs`)
  }
}

async function migrationComplete() {
  const value = (await requestJson("/api/experimental/migration/v1")).value
  if (!isObject(value) || !["completed", "required", "running", "error"].includes(value.status)) {
    throw new Error("OpenCode migration API returned an incompatible response")
  }
  if (value.status !== "completed") throw new Error("retention deferred until v1 migration is completed")
}

function family(hierarchy, rootID) {
  return hierarchy.sessions.filter(session => hierarchy.rootByID.get(session.id) === rootID)
}

function eligible(hierarchy, rootID, cutoff) {
  return hierarchy.rootByID.get(rootID) === rootID &&
    family(hierarchy, rootID).every(session => BigInt(session.time.updated) < cutoff)
}

function sameLinkage(left, right) {
  return (left.parentID ?? null) === (right.parentID ?? null) &&
    left.location.directory === right.location.directory &&
    left.location.workspaceID === right.location.workspaceID
}

function observeFamilies(hierarchy, observedFamilies) {
  for (const [rootID, observed] of observedFamilies) {
    // Pagination is not a snapshot: an updated child can move ahead of the
    // cursor and disappear from a later traversal. Never shrink a known family.
    for (const [id, previous] of observed) {
      const current = hierarchy.byID.get(id)
      if (!current || hierarchy.rootByID.get(id) !== rootID || !sameLinkage(previous, current)) {
        throw new Error(`retention deferred: observed family member ${id} is missing or changed linkage/location`)
      }
    }
    for (const member of family(hierarchy, rootID)) {
      if (!observed.has(member.id)) observed.set(member.id, member)
    }
  }
}

async function refreshFamilyAges(hierarchy, observed, cutoff) {
  let old = true
  for (const id of observed.keys()) {
    const current = validateSessionResponse(await getSession(id), id)
    if (!sameLinkage(hierarchy.byID.get(id), current)) {
      throw new Error(`retention deferred: observed family member ${id} changed linkage/location during direct refresh`)
    }
    if (BigInt(current.time.updated) >= cutoff) old = false
  }
  return old
}

async function runOnce() {
  const days = retentionDays()
  if (days === 0n) {
    log("disabled (retention days is 0)")
    return
  }

  const now = BigInt(process.env.OPENCODE_WEB_RETENTION_NOW_MS || Date.now())
  const marker = stateMarkerPath()
  if (!due(marker, now)) {
    log("not due; the last successful run is less than 7 days old")
    return
  }

  const verifyTimeoutMs = positiveInteger("OPENCODE_WEB_RETENTION_VERIFY_TIMEOUT_MS", DEFAULT_VERIFY_TIMEOUT_MS)
  await checkServerCapability()
  await migrationComplete()
  const cutoff = now - days * 24n * 60n * 60n * 1000n
  const hierarchy = buildHierarchy(await listSessions())
  const candidates = hierarchy.sessions.filter(
    (session) => eligible(hierarchy, session.id, cutoff),
  )
  const active = await activeRoots(hierarchy)
  const inactive = candidates.filter((session) => !active.has(session.id))

  if (isTrue(process.env.OPENCODE_WEB_RETENTION_DRY_RUN)) {
    log(`dry-run: ${inactive.length} inactive root session(s) would be deleted`)
    return
  }

  const observedFamilies = new Map(inactive.map(session => [
    session.id,
    new Map(family(hierarchy, session.id).map(member => [member.id, member])),
  ]))
  let deleted = 0
  for (const session of inactive) {
    await migrationComplete()
    const currentHierarchy = buildHierarchy(await listSessions())
    observeFamilies(currentHierarchy, observedFamilies)
    const observed = observedFamilies.get(session.id)
    if (!eligible(currentHierarchy, session.id, cutoff) ||
        !await refreshFamilyAges(currentHierarchy, observed, cutoff)) {
      observedFamilies.delete(session.id)
      continue
    }
    // Inbox and foreground activity checks must follow the direct age checks.
    const activeNow = await activeRoots(currentHierarchy)
    if (activeNow.has(session.id)) {
      observedFamilies.delete(session.id)
      continue
    }

    await requestJson(`/api/session/${encodeURIComponent(session.id)}`, { method: "DELETE", noContent: true })
    for (const id of observed.keys()) await verifyDeleted(id, verifyTimeoutMs)
    observedFamilies.delete(session.id)
    deleted += 1
  }

  writeMarker(marker, now)
  log(`completed: deleted ${deleted} inactive root session(s); active sessions were skipped`)
}

if (process.argv.includes("--help")) {
  process.stdout.write("Usage: opencode_web_yolo_retention.js --run-once\n")
} else if (!process.argv.includes("--run-once")) {
  fail("--run-once is required")
} else {
  runOnce().catch((error) => fail(error.message))
}
