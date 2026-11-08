// Local demo server: the same family logic as the deployed `api` function, kept in memory on this Mac,
// with no sign-in. Only for the iOS Simulator's "Try the demo" mode (it reaches the Mac at 127.0.0.1).
// Run: bun scripts/local_demo_server.ts   (Ctrl-C to stop; every restart starts a fresh demo family)
import { ApiError, handle, type Caller, type Deps } from '../supabase/functions/_shared/api.ts';
import { MemoryDirectory } from '../supabase/functions/_shared/memoryDb.ts';

const PORT = 8787;
const ME: Caller = { userId: 'local-demo-user', email: 'demo@golden-hour.local' };
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

const randomCode = () => Array.from({ length: 6 }, () => CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)]).join('');
const deps: Deps = { dir: new MemoryDirectory(randomCode), newId: () => crypto.randomUUID(), inviteCode: randomCode };

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

// Start with a ready family: you in Durham plus the simulated Mom, Grandpa and Dad with two weeks of history.
await handle({
  action: 'create_family', family_name: 'Kim family', name: 'You', tz: 'America/New_York', city: 'Durham',
  wake: '07:00', bed: '23:30', busy: [['09:00', '17:00']],
}, ME, deps, new Date());
await handle({ action: 'add_demo_family' }, ME, deps, new Date());

Bun.serve({
  hostname: '127.0.0.1',
  port: PORT,
  async fetch(req) {
    if (req.method !== 'POST' || !new URL(req.url).pathname.endsWith('/functions/v1/api')) return json(404, { ok: false, error: 'not found' });
    let body: unknown;
    try { body = await req.json(); } catch { return json(400, { ok: false, error: 'body must be JSON' }); }
    try {
      const result = await handle(body, ME, deps, new Date());
      console.log(`${new Date().toLocaleTimeString()}  ${(body as { action?: string }).action ?? '?'}`);
      return json(200, result);
    } catch (e) {
      if (e instanceof ApiError) return json(e.status, { ok: false, error: e.message });
      console.error('local api failed', e);
      return json(500, { ok: false, error: 'server error' });
    }
  },
});
console.log(`Golden Hour local demo server on http://127.0.0.1:${PORT} — demo family ready`);
