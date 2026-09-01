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
  if (!session || typeof session !== "object" || typeof session.id !== "string") {
    throw new Error("OpenCode global session API returned a malformed session")
  }
  if (
    session.parentID !== undefined &&
    session.parentID !== null &&
    (typeof session.parentID !== "string" || session.parentID.length === 0)
  ) {
    throw new Error("OpenCode session API returned an invalid parentID")
  }
  if (typeof session.directory !== "string" || !session.time || typeof session.time.updated !== "number") {
    throw new Error("OpenCode global session API returned a session without directory/time.updated")
  }
  if (!Number.isSafeInteger(session.time.updated) || session.time.updated < 0) {
    throw new Error("OpenCode global session API returned an invalid time.updated")
  }
}

async function listSessions(deadline) {
  const sessions = []
  let cursor
  const seenCursors = new Set()

  for (let pageNumber = 0; pageNumber < 10000; pageNumber += 1) {
    const remaining = deadline === undefined ? undefined : deadline - Date.now()
    if (remaining !== undefined && remaining <= 0) {
      throw new Error("session deletion verification timed out")
    }
    const result = await requestJson("/experimental/session", remaining === undefined ? {} : {
      timeoutMs: Math.min(remaining, positiveInteger("OPENCODE_WEB_RETENTION_FETCH_TIMEOUT_MS", DEFAULT_FETCH_TIMEOUT_MS)),
    }, {
      roots: "false",
      archived: "true",
      limit: PAGE_LIMIT,
      cursor,
    })
    if (!Array.isArray(result.value)) {
      throw new Error("OpenCode global session API is incompatible: expected a session array")
    }
    result.value.forEach(validateSession)
    sessions.push(...result.value)

    const nextCursor = result.headers.get("x-next-cursor")
    if (!nextCursor) return sessions
    const last = result.value[result.value.length - 1]
    if (!last || String(last.time.updated) !== nextCursor || !/^[0-9]+$/.test(nextCursor)) {
      throw new Error("OpenCode global session API returned an invalid pagination cursor")
    }
    if (result.value.filter((session) => session.time.updated === last.time.updated).length > 1) {
      throw new Error("OpenCode global session API cannot safely paginate equal session timestamps")
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
    directories: [...new Set(sessions.map((session) => session.directory))],
  }
}

function validateStatusMap(statuses) {
  if (!statuses || typeof statuses !== "object" || Array.isArray(statuses)) {
    throw new Error("OpenCode session status API returned an incompatible response")
  }
  for (const status of Object.values(statuses)) {
    if (!status || !["idle", "busy", "retry"].includes(status.type)) {
      throw new Error("OpenCode session status API returned an unknown status")
    }
  }
  return statuses
}

async function activeRoots(hierarchy) {
  const active = new Set()
  for (const directory of hierarchy.directories) {
    const result = await requestJson("/session/status", {}, { directory })
    const status = validateStatusMap(result.value)
    for (const [sessionID, info] of Object.entries(status)) {
      const session = hierarchy.byID.get(sessionID)
      if (!session) {
        throw new Error(`OpenCode session status API returned an unmapped session ${sessionID}`)
      }
      if (session.directory !== directory) {
        throw new Error(`OpenCode session status API mapped session ${sessionID} to the wrong directory`)
      }
      const rootID = hierarchy.rootByID.get(sessionID)
      if (!rootID) {
        throw new Error(`OpenCode session hierarchy could not map session ${sessionID} to a root`)
      }
      if (info.type !== "busy" && info.type !== "retry") continue
      active.add(rootID)
    }
  }
  return active
}

async function getSession(sessionID, directory, expectNotFound = false) {
  return requestJson(`/session/${encodeURIComponent(sessionID)}`, {
    expectNotFound,
  }, { directory })
}

function validateRootResponse(result, sessionID, directory) {
  if (result.notFound) return undefined
  validateSession(result.value)
  if (result.value.id !== sessionID || result.value.directory !== directory) {
    throw new Error(`OpenCode session API returned a mismatched session for ${sessionID}`)
  }
  if (result.value.parentID !== undefined && result.value.parentID !== null) {
    throw new Error(`OpenCode session API returned non-root session ${sessionID}`)
  }
  return result.value
}

async function verifyDeleted(sessionID, directory, timeoutMs) {
  const deadline = Date.now() + timeoutMs
  while (true) {
    const result = await getSession(sessionID, directory, true)
    if (result.notFound) return
    validateRootResponse(result, sessionID, directory)
    if (Date.now() >= deadline) {
      throw new Error(`session ${sessionID} remained present after deletion verification`)
    }
    await new Promise((resolve) => setTimeout(resolve, VERIFY_POLL_MS))
  }
}

async function checkServerCapability() {
  const result = await requestJson("/global/health")
  if (!result.value || result.value.healthy !== true || typeof result.value.version !== "string") {
    throw new Error("OpenCode health API is incompatible; retention requires healthy 1.18.x capability metadata")
  }
  if (!/^1\.18\.[0-9]+$/.test(result.value.version)) {
    throw new Error(`OpenCode version ${result.value.version} is unsupported; retention requires tested 1.18.x APIs`)
  }
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
  const cutoff = now - days * 24n * 60n * 60n * 1000n
  const hierarchy = buildHierarchy(await listSessions())
  const candidates = hierarchy.sessions.filter(
    (session) => (session.parentID === undefined || session.parentID === null) && BigInt(session.time.updated) < cutoff,
  )
  const active = await activeRoots(hierarchy)
  const inactive = candidates.filter((session) => !active.has(session.id))

  if (isTrue(process.env.OPENCODE_WEB_RETENTION_DRY_RUN)) {
    log(`dry-run: ${inactive.length} inactive root session(s) would be deleted`)
    return
  }

  let deleted = 0
  for (const session of inactive) {
    const refreshedResult = await getSession(session.id, session.directory, true)
    const refreshed = validateRootResponse(refreshedResult, session.id, session.directory)
    if (!refreshed || BigInt(refreshed.time.updated) >= cutoff) continue

    const currentHierarchy = buildHierarchy(await listSessions())
    const current = currentHierarchy.byID.get(session.id)
    if (
      !current ||
      current.directory !== refreshed.directory ||
      currentHierarchy.rootByID.get(session.id) !== session.id ||
      BigInt(current.time.updated) >= cutoff
    ) continue
    const activeNow = await activeRoots(currentHierarchy)
    if (activeNow.has(session.id)) continue

    const result = await requestJson(`/session/${encodeURIComponent(session.id)}`, { method: "DELETE" }, {
      directory: refreshed.directory,
    })
    if (result.value !== true) {
      throw new Error(`OpenCode deletion API returned an incompatible response for session ${session.id}`)
    }
    await verifyDeleted(session.id, refreshed.directory, verifyTimeoutMs)
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
