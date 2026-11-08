// Waitlist logic with no framework: validation, a small append-only store and a rate limiter.
import { appendFileSync, existsSync, mkdirSync, readFileSync } from 'node:fs'
import { dirname } from 'node:path'

const EMAIL = /^[^\s@]{1,64}@[^\s@.]+(\.[^\s@.]+)+$/

/** Returns a normalized email, or null when it isn't plausible. */
export function normalizeEmail(input) {
  if (typeof input !== 'string') return null
  const e = input.trim().toLowerCase()
  return e.length <= 254 && EMAIL.test(e) ? e : null
}

/**
 * One JSON object per line: { email, at }. Nothing else is stored (no IP, no user agent).
 * Duplicate addresses are ignored quietly.
 */
export function createStore(file) {
  mkdirSync(dirname(file), { recursive: true })
  const seen = new Set()
  if (existsSync(file)) {
    for (const line of readFileSync(file, 'utf8').split('\n')) {
      if (!line.trim()) continue
      try { seen.add(JSON.parse(line).email) } catch { /* skip a damaged line */ }
    }
  }
  return {
    add(email, now = new Date()) {
      if (seen.has(email)) return false
      appendFileSync(file, JSON.stringify({ email, at: now.toISOString() }) + '\n', { mode: 0o600 })
      seen.add(email)
      return true
    },
    count: () => seen.size,
  }
}

/** Fixed-window limiter, in memory, keyed by caller (the IP is never written to disk). */
export function createLimiter({ max = 5, windowMs = 60_000 } = {}) {
  const hits = new Map()
  return (key, now = Date.now()) => {
    const h = hits.get(key)
    if (!h || now - h.start >= windowMs) {
      hits.set(key, { start: now, n: 1 })
      if (hits.size > 5000) for (const [k, v] of hits) if (now - v.start >= windowMs) hits.delete(k)
      return true
    }
    h.n += 1
    return h.n <= max
  }
}

/**
 * Handles a parsed POST body. Returns { status, body }. A duplicate gets the same answer as a new
 * address, so the endpoint can't be used to check who is on the list. A filled honeypot is dropped
 * silently with a success reply.
 */
export function handleSignup(body, store) {
  if (!body || typeof body !== 'object') return { status: 400, body: { ok: false, error: 'Send an email address.' } }
  if (typeof body.website === 'string' && body.website !== '') return { status: 200, body: { ok: true } }
  const email = normalizeEmail(body.email)
  if (!email) return { status: 400, body: { ok: false, error: 'That doesn’t look like an email address.' } }
  store.add(email)
  return { status: 200, body: { ok: true } }
}
