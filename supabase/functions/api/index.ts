// Supabase Edge Function `api`: the only read/write path. Deployed with --no-verify-jwt because the
// function checks the signed-in user itself (auth.getUser) and returns a clear 401 the app can act on.
// Uses the service role key, which Supabase injects as a function secret; it never ships in the app.
import { createClient } from 'npm:@supabase/supabase-js@2.119.0';
import { ApiError, handle } from '../_shared/api.ts';
import { claudeWriter } from '../_shared/notes.ts';
import { inviteCode, SupabaseDirectory } from './supabaseDb.ts';

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization, apikey, content-type, x-client-info',
  'access-control-allow-methods': 'POST, OPTIONS',
};
const MAX_BODY_BYTES = 64 * 1024;
// "Try the demo" sign-in: makes a throwaway account and hands back a one-time code, so a demo needs no email.
// Only works while the DEMO_SIGNIN secret is "on"; turn it off after the hackathon.
const DEMO_SIGNIN = Deno.env.get('DEMO_SIGNIN') === 'on';

function env(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`missing ${name}`);
  return v;
}

const sb = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false } });
const anthropicKey = Deno.env.get('ANTHROPIC_API_KEY');
const deps = {
  dir: new SupabaseDirectory(sb),
  notes: anthropicKey ? claudeWriter(anthropicKey) : undefined,
  newId: () => crypto.randomUUID(),
  inviteCode,
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'content-type': 'application/json' } });

async function callerOf(req: Request) {
  const token = req.headers.get('authorization')?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) throw new ApiError(401, 'sign in first');
  const { data, error } = await sb.auth.getUser(token);
  if (error || !data.user) throw new ApiError(401, 'your sign-in expired');
  return { userId: data.user.id, email: data.user.email ?? null };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json(405, { ok: false, error: 'POST only' });
  try {
    const text = await req.text();
    if (text.length > MAX_BODY_BYTES) return json(413, { ok: false, error: 'body too large' });
    let body: unknown;
    try { body = JSON.parse(text); } catch { return json(400, { ok: false, error: 'body must be JSON' }); }
    if ((body as { action?: unknown } | null)?.action === 'demo_signin') return json(200, await demoSignIn());
    const caller = await callerOf(req);
    return json(200, await handle(body, caller, deps, new Date()));
  } catch (e) {
    if (e instanceof ApiError) return json(e.status, { ok: false, error: e.message });
    console.error('api failed', e);
    return json(500, { ok: false, error: 'server error' });
  }
});

async function demoSignIn() {
  if (!DEMO_SIGNIN) throw new ApiError(403, 'demo sign-in is turned off');
  const email = `demo-${crypto.randomUUID().slice(0, 8)}@demo.goldenhour.invalid`;
  const created = await sb.auth.admin.createUser({ email, email_confirm: true });
  if (created.error) throw new Error(`demo createUser: ${created.error.message}`);
  const link = await sb.auth.admin.generateLink({ type: 'magiclink', email });
  const code = link.data?.properties?.email_otp;
  if (link.error || !code) throw new Error(`demo generateLink: ${link.error?.message ?? 'no code'}`);
  return { ok: true, email, code };
}
