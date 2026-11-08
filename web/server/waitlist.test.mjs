import { mkdtempSync, readFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { createLimiter, createStore, handleSignup, normalizeEmail } from './waitlist.mjs'

const tmp = () => join(mkdtempSync(join(tmpdir(), 'kairo-')), 'w.jsonl')

describe('normalizeEmail', () => {
  it('accepts and lowercases plausible addresses', () => {
    expect(normalizeEmail('  Alex@Example.COM ')).toBe('alex@example.com')
  })
  it.each(['', 'nope', 'a@b', 'a b@c.com', '@x.com', 'a@.com', 42, null])('rejects %p', (v) => {
    expect(normalizeEmail(v)).toBeNull()
  })
  it('rejects over-long input', () => {
    expect(normalizeEmail('a'.repeat(250) + '@x.com')).toBeNull()
  })
})

describe('store', () => {
  it('stores only email and time, ignores duplicates, and survives a restart', () => {
    const f = tmp()
    const s = createStore(f)
    expect(s.add('a@example.com', new Date('2026-11-08T00:00:00Z'))).toBe(true)
    expect(s.add('a@example.com')).toBe(false)
    expect(JSON.parse(readFileSync(f, 'utf8').trim())).toEqual({ email: 'a@example.com', at: '2026-11-08T00:00:00.000Z' })
    expect(createStore(f).count()).toBe(1)
    expect(createStore(f).add('a@example.com')).toBe(false)
  })
})

describe('handleSignup', () => {
  it('saves a valid address and answers a duplicate identically', () => {
    const s = createStore(tmp())
    const a = handleSignup({ email: 'b@example.com' }, s)
    const b = handleSignup({ email: 'B@example.com' }, s)
    expect(a).toEqual({ status: 200, body: { ok: true } })
    expect(b).toEqual(a)
    expect(s.count()).toBe(1)
  })
  it('rejects bad input without saving', () => {
    const s = createStore(tmp())
    expect(handleSignup({ email: 'bad' }, s).status).toBe(400)
    expect(handleSignup(null, s).status).toBe(400)
    expect(s.count()).toBe(0)
  })
  it('silently drops honeypot submissions', () => {
    const s = createStore(tmp())
    expect(handleSignup({ email: 'c@example.com', website: 'http://spam' }, s).status).toBe(200)
    expect(s.count()).toBe(0)
  })
})

describe('limiter', () => {
  it('allows 5 per window per key, then recovers', () => {
    const allow = createLimiter({ max: 5, windowMs: 1000 })
    const r = Array.from({ length: 6 }, () => allow('ip', 0))
    expect(r).toEqual([true, true, true, true, true, false])
    expect(allow('other', 0)).toBe(true)
    expect(allow('ip', 1000)).toBe(true)
  })
})
