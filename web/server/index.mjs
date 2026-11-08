// Kairo website server: server-rendered HTML page, static assets, and a small JSON API.
// Run `npm run build:all` first, then `npm start`.
import { createServer } from 'node:http'
import { readFileSync, existsSync, statSync } from 'node:fs'
import { extname, join, normalize, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { createLimiter, createStore, handleSignup } from './waitlist.mjs'

const root = resolve(fileURLToPath(new URL('..', import.meta.url)))
const dist = join(root, 'dist')
const PORT = Number(process.env.PORT ?? 3000)
const HOST = process.env.HOST ?? '127.0.0.1'
const DATA_FILE = process.env.WAITLIST_FILE ?? join(root, 'data', 'waitlist.jsonl')
const TRUST_PROXY = process.env.TRUST_PROXY === '1'

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.png': 'image/png', '.svg': 'image/svg+xml', '.ttf': 'font/ttf', '.txt': 'text/plain; charset=utf-8', '.json': 'application/json',
}
const SECURITY = {
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
  'X-Frame-Options': 'DENY',
  'Content-Security-Policy': "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
}

const { render } = await import(pathToFileURL(join(root, 'dist-server', 'entry-server.js')).href)
const template = readFileSync(join(dist, 'index.html'), 'utf8')
const store = createStore(DATA_FILE)
const allow = createLimiter({ max: 5, windowMs: 60_000 })

// The page is the same for every visitor, so render it once.
globalThis.__KAIRO__ = { waitlist: true }
const page = template.replace(
  '<div id="root"></div>',
  `<div id="root">${render()}</div><script>window.__KAIRO__={"waitlist":true}</script>`,
)

const send = (res, status, body, headers = {}) => {
  res.writeHead(status, { ...SECURITY, ...headers })
  res.end(body)
}
const json = (res, status, obj) => send(res, status, JSON.stringify(obj), { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' })

function readBody(req, limit = 2048) {
  return new Promise((ok, fail) => {
    let size = 0
    const chunks = []
    req.on('data', (c) => {
      size += c.length
      if (size > limit) { fail(new Error('too large')); req.destroy() } else chunks.push(c)
    })
    req.on('end', () => ok(Buffer.concat(chunks).toString('utf8')))
    req.on('error', fail)
  })
}

const sameOrigin = (req) => {
  const origin = req.headers.origin
  return !origin || new URL(origin).host === req.headers.host
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url ?? '/', 'http://x')

  if (url.pathname === '/api/health') return json(res, 200, { ok: true })

  if (url.pathname === '/api/waitlist') {
    if (req.method !== 'POST') return json(res, 405, { ok: false, error: 'Use POST.' })
    if (!sameOrigin(req)) return json(res, 403, { ok: false, error: 'Not allowed.' })
    const ip = (TRUST_PROXY && String(req.headers['x-forwarded-for'] ?? '').split(',')[0].trim()) || req.socket.remoteAddress || 'unknown'
    if (!allow(ip)) return json(res, 429, { ok: false, error: 'Too many tries. Please wait a minute.' })
    let body
    try { body = JSON.parse(await readBody(req)) } catch { return json(res, 400, { ok: false, error: 'Send an email address.' }) }
    const out = handleSignup(body, store)
    return json(res, out.status, out.body)
  }

  if (req.method !== 'GET' && req.method !== 'HEAD') return send(res, 405, 'Method not allowed')

  if (url.pathname === '/' || url.pathname === '/index.html') {
    return send(res, 200, req.method === 'HEAD' ? undefined : page, { 'Content-Type': TYPES['.html'], 'Cache-Control': 'no-cache' })
  }

  const file = normalize(join(dist, decodeURIComponent(url.pathname)))
  if (file.startsWith(dist + '/') && existsSync(file) && statSync(file).isFile()) {
    const hashed = url.pathname.startsWith('/assets/')
    return send(res, 200, readFileSync(file), {
      'Content-Type': TYPES[extname(file)] ?? 'application/octet-stream',
      'Cache-Control': hashed ? 'public, max-age=31536000, immutable' : 'public, max-age=3600',
    })
  }
  send(res, 404, 'Not found', { 'Content-Type': 'text/plain; charset=utf-8' })
})

server.listen(PORT, HOST, () => console.log(`Kairo site on http://${HOST}:${PORT} (waitlist: ${store.count()} signups stored)`))
