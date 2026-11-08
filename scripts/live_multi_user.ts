// Live end-to-end test against the deployed server with three separate accounts.
// Needs "Allow anonymous sign-ins" ON in Supabase → Auth → Providers (turn it off after).
// Run: bun scripts/live_multi_user.ts
import { readFileSync } from "node:fs";

const secrets = readFileSync(new URL("../ios/Config/Secrets.xcconfig", import.meta.url), "utf8");
const pick = (k: string) => secrets.match(new RegExp(`^${k}\\s*=\\s*(.+)$`, "m"))?.[1].trim().replace("/$()/", "//") ?? "";
const URL_ = pick("SUPABASE_URL");
const KEY = pick("SUPABASE_ANON_KEY");
if (!URL_ || !KEY) throw new Error("SUPABASE_URL / SUPABASE_ANON_KEY missing in ios/Config/Secrets.xcconfig");

let failures = 0;
const check = (ok: boolean, what: string) => {
  console.log(`${ok ? "PASS" : "FAIL"}  ${what}`);
  if (!ok) failures++;
};

async function anonUser(): Promise<string> {
  const r = await fetch(`${URL_}/auth/v1/signup`, {
    method: "POST", headers: { apikey: KEY, "Content-Type": "application/json" }, body: "{}",
  });
  const j = await r.json();
  if (!j.access_token) throw new Error(`anonymous sign-in failed: ${JSON.stringify(j)}`);
  return j.access_token;
}

async function api(token: string | null, body: Record<string, unknown>) {
  const r = await fetch(`${URL_}/functions/v1/api`, {
    method: "POST",
    headers: { apikey: KEY, "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body),
  });
  return { status: r.status, json: await r.json() as any };
}

const profile = (name: string, tz: string, city: string) => ({ name, tz, city, wake: "07:00", bed: "23:00", busy: [["09:00", "17:00"]] });

const noAuth = await api(null, { action: "me" });
check(noAuth.status === 401, `no token → 401 (got ${noAuth.status})`);

const alice = await anonUser(), bob = await anonUser(), carol = await anonUser();

const me0 = await api(alice, { action: "me" });
check(me0.status === 200 && me0.json.account === null, "new account has no family yet");

const a = await api(alice, { action: "create_family", family_name: "Kim family", ...profile("Alice", "America/New_York", "Durham") });
check(a.status === 200 && /^[A-Z2-9]{6}$/.test(a.json.account?.inviteCode ?? ""), `Alice creates a family (code ${a.json.account?.inviteCode})`);
const code = a.json.account.inviteCode;

const again = await api(alice, { action: "create_family", family_name: "Second", ...profile("Alice", "America/New_York", "Durham") });
check(again.status === 409, "Alice can't create a second family");

const bad = await api(bob, { action: "join_family", invite_code: "ZZZZZZ", ...profile("Bob", "Asia/Seoul", "Seoul") });
check(bad.status === 404, "wrong invite code → 404");

const b = await api(bob, { action: "join_family", invite_code: code.toLowerCase(), ...profile("Bob", "Asia/Seoul", "Seoul") });
check(b.status === 200 && b.json.state?.members?.length === 2, "Bob joins with the code (lowercase works); family has 2 members");

const c = await api(carol, { action: "create_family", family_name: "Lee family", ...profile("Carol", "Europe/London", "London") });
check(c.status === 200 && c.json.account.inviteCode !== code, "Carol creates her own family");
check(c.json.state.members.length === 1 && c.json.state.members[0].name === "Carol", "Carol sees only her own family");

const aliceId = a.json.account.memberId, bobId = b.json.account.memberId;
const spy = await api(carol, { action: "log_outcome", member_id: aliceId, kind: "call", answered: true, source: "family_call" });
check(spy.status >= 400, `Carol can't log against Alice's family (got ${spy.status})`);

const label = await api(alice, { action: "log_outcome", member_id: bobId, kind: "label", free: true, source: "widget" });
check(label.status === 403, "Alice can't label Bob as free");

const leak = await api(alice, { action: "log_outcome", member_id: bobId, kind: "text", reply_seconds: 60, source: "shortcut", text: "hi mom" });
check(leak.status === 400, "message text is rejected");

const text = await api(alice, { action: "log_outcome", member_id: bobId, kind: "text", reply_seconds: 60, source: "shortcut" });
check(text.status === 200 && text.json.state.lastChange?.memberId === bobId, "Shortcut text from Bob is logged and shows as the latest change");

const demo = await api(alice, { action: "add_demo_family" });
check(demo.status === 200 && demo.json.state.members.filter((m: any) => m.simulated).length === 3, "demo family adds Mom, Grandpa, Dad");
const mom = demo.json.state.members.find((m: any) => m.simulated && m.name === "Mom");
check(mom && mom.week.length === 96 && mom.insights.length > 0, "Mom has a learned week map and insights");
check(typeof demo.json.state.note === "string" && demo.json.state.note.length > 0, `AI note: "${demo.json.state.note}"`);

const sim = await api(alice, { action: "simulate", member_id: mom.id, event: "answer_call" });
check(sim.status === 200 && sim.json.state.lastChange?.memberId === mom.id, `simulate Mom answers → ${sim.json.state.lastChange?.changed?.length ?? 0} cells changed`);

const notSim = await api(alice, { action: "simulate", member_id: bobId, event: "answer_call" });
check(notSim.status >= 400, "can't simulate a real member");

const bobView = await api(bob, { action: "state" });
check(bobView.json.state.members.length === 5, "Bob sees the same 5-member family");

const s = demo.json.state.suggestion;
if (s) {
  const j1 = await api(alice, { action: "join", start: s.start });
  check(j1.status === 200 && j1.json.state.bookings.some((x: any) => x.status === "open"), "Alice joins the suggested time (waiting on Bob)");
  const j2 = await api(bob, { action: "join", start: s.start });
  check(j2.json.state.bookings.some((x: any) => x.status === "booked"), "Bob joins → call is booked for everyone");
} else {
  check(false, "a suggestion exists");
}

for (const t of [alice, carol]) await api(t, { action: "reset_family" });
console.log(failures ? `\n${failures} check(s) failed` : "\nAll live checks passed");
process.exit(failures ? 1 : 0);
