// Kairo agent (Supabase Edge Function, Deno). UNVERIFIED in this environment: not deployed or run.
//
// Security model
//  • Every request carries the END USER's JWT. All database access uses that JWT, so RLS and the
//    SECURITY DEFINER functions authorize every mutation. There is no service-role key here.
//  • Claude is offered read/rank/create tools only. confirm/decline are NOT model tools: they exist as
//    separate user-initiated routes, so the agent cannot impersonate a participant's consent.
//  • Only scheduling facts go to Claude (levels, coarse confidence, local times). Never message bodies,
//    audio, or raw activity events (this server never has them).
//  • If the Anthropic API fails, deterministic ranking + a templated explanation are returned.
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const MODEL = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-sonnet-5-5";
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

// ── validation ────────────────────────────────────────────────────────────
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PID = /^[A-Za-z0-9_+.:\-]{1,80}$/;
class BadArg extends Error {}
const uuid = (v: unknown, n: string) => { if (typeof v !== "string" || !UUID.test(v)) throw new BadArg(`${n} must be a uuid`); return v; };
const uuids = (v: unknown, n: string) => {
  if (!Array.isArray(v) || v.length < 2 || v.length > 6) throw new BadArg(`${n} must have 2-6 ids`);
  const ids = v.map((x) => uuid(x, n)); if (new Set(ids).size !== ids.length) throw new BadArg(`${n} must be unique`); return ids;
};
const iso = (v: unknown, n: string) => { const d = new Date(String(v)); if (isNaN(+d)) throw new BadArg(`${n} must be ISO-8601`); return d; };
const minutes = (v: unknown) => { const n = v === undefined ? 30 : Number(v); if (!Number.isInteger(n) || n < 15 || n > 120) throw new BadArg("duration_minutes 15-120"); return n; };

// ── deterministic tools (shared by the model path and the fallback path) ──────────
type Level = "likelyFree" | "maybeFree" | "unlikely" | "busy" | "quietHours" | "learning";
const SCORE: Record<Level, number> = { likelyFree: 0.8, maybeFree: 0.5, unlikely: 0.25, learning: 0.5, busy: 0, quietHours: 0 };
const CONF = { low: 0.5, medium: 0.8, high: 1 } as const;

async function sharedAvailability(db: SupabaseClient, group: string, users: string[], from: Date, to: Date) {
  const { data, error } = await db.from("availability_summaries").select("user_id,slot_start,level,confidence")
    .eq("group_id", group).in("user_id", users).gte("slot_start", from.toISOString()).lt("slot_start", to.toISOString());
  if (error) throw error; return data ?? [];
}
async function restrictions(db: SupabaseClient, group: string, users: string[]) {
  const { data, error } = await db.from("scheduling_restrictions").select("*").eq("group_id", group).in("user_id", users);
  if (error) throw error; return data ?? [];
}
async function burden(db: SupabaseClient, group: string, users: string[]) {
  const { data, error } = await db.from("scheduling_burden").select("user_id,amount,at").eq("group_id", group).in("user_id", users)
    .order("at", { ascending: false }).limit(60);
  if (error) throw error;
  const load: Record<string, number> = {};
  for (const u of users) {
    const rows = (data ?? []).filter((r) => r.user_id === u).slice(0, 10);
    load[u] = Math.min(1, rows.reduce((a, r) => a + r.amount * Math.pow(0.5, (Date.now() - +new Date(r.at)) / 864e5 / 14), 0) / 2);
  }
  return load;
}
const localMinute = (d: Date, tz: string) => {
  const p = new Intl.DateTimeFormat("en-GB", { timeZone: tz, hour: "2-digit", minute: "2-digit", hour12: false }).formatToParts(d);
  return Number(p.find((x) => x.type === "hour")!.value) % 24 * 60 + Number(p.find((x) => x.type === "minute")!.value);
};
const quiet = (m: number, s: number, e: number) => (s < e ? m >= s && m < e : m >= s || m < e);

/** Server port of the Swift SchedulingEngine's shape (hard filter → fit → least-convenient → fairness).
 *  Parity tests against the Swift engine are deferred. */
async function rank(db: SupabaseClient, group: string, users: string[], dur: number) {
  const [rs, burdens] = await Promise.all([restrictions(db, group, users), burden(db, group, users)]);
  const now = Date.now(), step = 1800e3, horizon = 72 * 3600e3;
  const sums = await sharedAvailability(db, group, users, new Date(now), new Date(now + horizon));
  const { data: busy } = await db.from("busy_overrides").select("user_id,starts_at,ends_at").eq("group_id", group).in("user_id", users);
  const out: any[] = [];
  for (let t = Math.ceil((now + 30 * 60e3) / step) * step; t < now + horizon; t += step) {
    const start = new Date(t), end = new Date(t + dur * 60e3);
    let blocked = false; const fits: number[] = []; let pen = 0;
    for (const u of users) {
      const r = rs.find((x) => x.user_id === u);
      for (let s = +start; s < +end && r; s += 15 * 60e3)
        if (quiet(localMinute(new Date(s), r.time_zone), r.quiet_start_min, r.quiet_end_min)) blocked = true;
      if (r && quiet(localMinute(new Date(+end - 1000), r.time_zone), r.quiet_start_min, r.quiet_end_min)) blocked = true;
      if ((busy ?? []).some((b) => b.user_id === u && +new Date(b.starts_at) < +end && +new Date(b.ends_at) > +start)) blocked = true;
      const row = sums.find((x) => x.user_id === u && +new Date(x.slot_start) === Math.floor(t / step) * step);
      const lvl = (row?.level ?? "learning") as Level; if (lvl === "busy" || lvl === "quietHours") blocked = true;
      const m = r ? localMinute(start, r.time_zone) : 720; const inc = m >= 540 && m < 1260 ? 0 : 0.5;
      fits.push(SCORE[lvl] * (0.5 + 0.5 * CONF[(row?.confidence ?? "low") as keyof typeof CONF]) * (1 - 0.35 * inc));
      pen += (burdens[u] ?? 0) * inc / users.length;
    }
    if (blocked) continue;
    const total = 0.5 * (fits.reduce((a, b) => a + b, 0) / fits.length) + 0.5 * Math.min(...fits) - 0.3 * pen;
    out.push({ start: start.toISOString(), end: end.toISOString(), total, fairness_penalty: pen });
  }
  out.sort((a, b) => b.total - a.total);
  const picked: any[] = [];
  for (const c of out) { if (picked.every((p) => Math.abs(+new Date(p.start) - +new Date(c.start)) >= 2 * 3600e3)) picked.push(c); if (picked.length === 3) break; }
  return picked.sort((a, b) => +new Date(a.start) - +new Date(b.start));
}
const proposalId = (start: string, users: string[]) =>
  `p-${new Date(start).toISOString().replace(/[-:]/g, "").slice(0, 13)}Z-${[...users].sort().join("+")}`.slice(0, 80);

// ── tool dispatch (Claude-facing) ───────────────────────────────────────────
async function runTool(db: SupabaseClient, name: string, a: any) {
  switch (name) {
    case "get_shared_availability": {
      const g = uuid(a.group_id, "group_id"), u = uuids(a.participants, "participants");
      const from = iso(a.start, "start"), to = iso(a.end, "end");
      if (+to <= +from || +to - +from > 7 * 864e5) throw new BadArg("range");
      return await sharedAvailability(db, g, u, from, to);        // coarse level + confidence bucket only
    }
    case "get_scheduling_preferences": {
      return await restrictions(db, uuid(a.group_id, "group_id"), [uuid(a.person_id, "person_id")]);
    }
    case "get_recent_scheduling_burden": {
      return await burden(db, uuid(a.group_id, "group_id"), uuids(a.participants, "participants"));
    }
    case "rank_candidate_windows": {
      return await rank(db, uuid(a.group_id, "group_id"), uuids(a.participants, "participants"), minutes(a.duration_minutes));
    }
    case "create_proposal": {
      const g = uuid(a.group_id, "group_id"), u = uuids(a.participants, "participants");
      const start = iso(a.start, "start"), end = new Date(+start + minutes(a.duration_minutes) * 60e3);
      const { data, error } = await db.rpc("create_proposal", {
        p_id: proposalId(start.toISOString(), u), p_group: g, p_participants: u, p_starts: start.toISOString(),
        p_ends: end.toISOString(), p_explanation: String(a.explanation ?? "").slice(0, 300), p_via_agent: true });
      if (error) throw new BadArg(error.message);                  // quiet hours / busy violations surface here
      return { id: data.id, status: data.status };
    }
    default: throw new BadArg("unknown tool");
  }
}

const TOOLS = [
  { name: "get_shared_availability", description: "Coarse availability levels for participants in a time range.",
    input_schema: { type: "object", properties: { group_id: { type: "string" }, participants: { type: "array", items: { type: "string" } }, start: { type: "string" }, end: { type: "string" } }, required: ["group_id", "participants", "start", "end"] } },
  { name: "get_scheduling_preferences", description: "Quiet hours and preferred call length for one person.",
    input_schema: { type: "object", properties: { group_id: { type: "string" }, person_id: { type: "string" } }, required: ["group_id", "person_id"] } },
  { name: "get_recent_scheduling_burden", description: "Recent inconvenient-call load per person (0-1).",
    input_schema: { type: "object", properties: { group_id: { type: "string" }, participants: { type: "array", items: { type: "string" } } }, required: ["group_id", "participants"] } },
  { name: "rank_candidate_windows", description: "Deterministically ranked top windows. Hard constraints already applied.",
    input_schema: { type: "object", properties: { group_id: { type: "string" }, participants: { type: "array", items: { type: "string" } }, duration_minutes: { type: "integer" } }, required: ["group_id", "participants"] } },
  { name: "create_proposal", description: "Create a suggested proposal (does NOT confirm anyone). Rejected if it violates quiet hours or busy.",
    input_schema: { type: "object", properties: { group_id: { type: "string" }, participants: { type: "array", items: { type: "string" } }, start: { type: "string" }, duration_minutes: { type: "integer" }, explanation: { type: "string" } }, required: ["group_id", "participants", "start"] } },
];

const SYSTEM = `You help family members across time zones find a call time. Use the tools. Rules:
- Never invent availability. Only use tool results.
- Never override quiet hours or busy; tools enforce them and will reject violations.
- You cannot confirm or decline for anyone. People confirm for themselves.
- Create at most 3 proposals from rank_candidate_windows results. Finish with 1-2 plain sentences explaining the choice using only tool facts. No reasoning transcript.`;

async function claude(messages: any[]) {
  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": ANTHROPIC_API_KEY!, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({ model: MODEL, max_tokens: 1024, system: SYSTEM, tools: TOOLS, messages }),
    signal: AbortSignal.timeout(20000),
  });
  if (!r.ok) throw new Error(`anthropic ${r.status}`);
  return await r.json();
}

// ── routes ──────────────────────────────────────────────────────────────────
Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const auth = req.headers.get("Authorization");
  if (!auth) return json({ error: "unauthorized" }, 401);
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
  const { data: { user } } = await db.auth.getUser();
  if (!user) return json({ error: "unauthorized" }, 401);
  const route = new URL(req.url).pathname.split("/").pop();
  let body: any; try { body = await req.json(); } catch { return json({ error: "bad json" }, 400); }

  try {
    if (route === "confirm" || route === "decline") {
      // User-initiated consent. Not reachable by the model.
      if (typeof body.proposal_id !== "string" || !PID.test(body.proposal_id)) throw new BadArg("proposal_id");
      const { data, error } = await db.rpc(route === "confirm" ? "confirm_proposal" : "decline_proposal", { p_id: body.proposal_id });
      if (error) return json({ error: error.message }, 409);
      return json({ status: data.status });
    }
    if (route === "explain") {
      const fallback = String(body.fallback ?? "").slice(0, 280);
      if (!ANTHROPIC_API_KEY) return json({ explanation: fallback, source: "deterministic" });
      try {
        const facts = JSON.stringify({ fits: body.fits, fairness_penalty: body.fairness_penalty }).slice(0, 2000);
        const res = await fetch("https://api.anthropic.com/v1/messages", {
          method: "POST", signal: AbortSignal.timeout(8000),
          headers: { "x-api-key": ANTHROPIC_API_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
          body: JSON.stringify({ model: MODEL, max_tokens: 120, system: "Write ONE short, warm sentence (max 200 chars) explaining why this call window was chosen, using only the given facts. Do not claim certainty; availability is estimated.",
            messages: [{ role: "user", content: facts }] }) });
        const j = await res.json(); const text = String(j?.content?.[0]?.text ?? "").trim();
        return json(text && text.length < 280 ? { explanation: text, source: "claude" } : { explanation: fallback, source: "deterministic" });
      } catch { return json({ explanation: fallback, source: "deterministic" }); }
    }
    if (route === "negotiate") {
      const g = uuid(body.group_id, "group_id"), users = uuids(body.participants, "participants");
      if (!users.includes(user.id)) throw new BadArg("caller must be a participant");
      const dur = minutes(body.duration_minutes);
      if (ANTHROPIC_API_KEY) {
        try {
          const messages: any[] = [{ role: "user", content: `group_id=${g} participants=${JSON.stringify(users)} duration_minutes=${dur}. Find and propose up to 3 times.` }];
          for (let turn = 0; turn < 6; turn++) {
            const res = await claude(messages);
            messages.push({ role: "assistant", content: res.content });
            const uses = res.content.filter((b: any) => b.type === "tool_use");
            if (!uses.length) return json({ source: "claude", summary: res.content.filter((b: any) => b.type === "text").map((b: any) => b.text).join(" ").slice(0, 400) });
            const results = [];
            for (const u of uses) {
              let content: string, is_error = false;
              try { content = JSON.stringify(await runTool(db, u.name, u.input)); } catch (e) { content = String((e as Error).message); is_error = true; }
              results.push({ type: "tool_result", tool_use_id: u.id, content, is_error });
            }
            messages.push({ role: "user", content: results });
          }
        } catch (_) { /* fall through to deterministic path */ }
      }
      // Deterministic fallback: same hard constraints, no LLM.
      const top = await rank(db, g, users, dur); const made = [];
      for (const w of top) made.push(await runTool(db, "create_proposal", { group_id: g, participants: users, start: w.start, duration_minutes: dur, explanation: "Both people are outside quiet hours and busy times." }).catch(() => null));
      return json({ source: "deterministic", proposals: made.filter(Boolean) });
    }
    return json({ error: "not found" }, 404);
  } catch (e) {
    if (e instanceof BadArg) return json({ error: e.message }, 400);
    return json({ error: "internal" }, 500);
  }
});
