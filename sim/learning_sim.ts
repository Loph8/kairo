// Does the learning loop actually make the family schedule better?
//
// Every family member starts from what they typed in onboarding (wake, bed, busy hours).
// Each day the scheduler picks tomorrow's family call. Each person really behaves according to a
// hidden "truth" schedule that differs from what they typed. We compare five schedulers:
//   static   - trusts the typed schedule forever (no learning)
//   greedy   - learns from outcomes, always picks the slot that looks best right now
//   thompson - learns, and samples from its uncertainty (tries promising but unproven slots)
//   careful  - learns; samples only among slots that already look nearly as good as the best
//   oracle   - knows the hidden truth (upper bound)
// Metric: the chance everyone picks up for the whole 45-minute call, scored against the hidden truth.
//
// Run: bun sim/learning_sim.ts [--seeds 40] [--days 56]
import { FAMILY, TRUTH_BANDS, DEMO_ANCHOR, DEMO_LEDGER, type Member } from '../supabase/functions/_shared/family.ts';
import { createLearner, observe, type Level, type Learner, type Observation } from '../supabase/functions/_shared/learning.ts';
import { truthGrid } from '../supabase/functions/_shared/seed.ts';
import { optimizePick, chargeLedger, scoreSlot, type Ledger, type PickupAt } from '../supabase/functions/_shared/schedule.ts';
import { carefulPick, greedyPick, thompsonPick, type Person } from '../supabase/functions/_shared/explore.ts';
import { cellIndex, DAY_MS } from '../supabase/functions/_shared/time.ts';
import { mulberry32, type Rng } from '../supabase/functions/_shared/rng.ts';

const TRUE_P: Readonly<Record<Level, number>> = { G: 0.9, Y: 0.5, R: 0.05 };
const PASSIVE_EVENTS_PER_DAY = 5;   // incoming calls/texts per person per day on the family channel
const LIFE_CHANGE_DAY = 28;         // scenario: Dad's work meetings move later in week 5

type Band = readonly [string, string, Level];
const DAD_LATER_MEETINGS: readonly Band[] = [['00:00', '06:00', 'R'], ['06:00', '08:00', 'G'], ['08:00', '08:30', 'Y'],
  ['08:30', '15:30', 'R'], ['15:30', '22:00', 'G'], ['22:00', '23:00', 'Y'], ['23:00', '24:00', 'R']];

const ZERO_LEDGER: Ledger = Object.fromEntries(FAMILY.map((m) => [m.id, 0]));
const POLICIES = ['static', 'greedy', 'thompson', 'careful', 'oracle'] as const;
type Policy = typeof POLICIES[number];

interface Scenario { readonly name: string; readonly passive: boolean; readonly lifeChange: boolean }

const ids = FAMILY.map((m) => m.id);

function truthFor(scn: Scenario, day: number): Record<string, Level[]> {
  return Object.fromEntries(FAMILY.map((m) => {
    const bands = scn.lifeChange && m.id === 'dad' && day >= LIFE_CHANGE_DAY ? DAD_LATER_MEETINGS : TRUTH_BANDS[m.id];
    return [m.id, truthGrid(bands)];
  }));
}

const truthPickup = (truth: Record<string, Level[]>): PickupAt => (id, at) => {
  const m = FAMILY.find((x) => x.id === id)!;
  return TRUE_P[truth[id][cellIndex(m.tz, at)]];
};

function passiveTraffic(m: Member, truth: Level[], dayStart: Date, rng: Rng): Observation[] {
  return Array.from({ length: PASSIVE_EVENTS_PER_DAY }, () => {
    const at = new Date(dayStart.getTime() + Math.floor(rng() * DAY_MS));
    const picked = rng() < TRUE_P[truth[cellIndex(m.tz, at)]];
    const outcome = rng() < 0.5
      ? { kind: 'call' as const, answered: picked }
      : { kind: 'text' as const, replySeconds: picked ? 120 : null };
    return { at, outcome, source: 'channel' as const };
  });
}

interface DayResult { readonly pAll: number; readonly rangAsleep: boolean }

function runOne(policy: Policy, scn: Scenario, seed: number, days: number): DayResult[] {
  const world = mulberry32(seed);           // same world events for every policy with this seed
  const explore = mulberry32(seed ^ 0x9e3779b9);
  let people: Person[] = FAMILY.map((m) => ({ id: m.id, tz: m.tz, learner: createLearner(m.onboarding, DEMO_ANCHOR) }));
  let ledger: Ledger = DEMO_LEDGER;
  const out: DayResult[] = [];

  for (let day = 0; day < days; day++) {
    const now = new Date(DEMO_ANCHOR.getTime() + day * DAY_MS);
    const truth = truthFor(scn, day);
    const truthP = truthPickup(truth);

    const pick = policy === 'oracle' ? optimizePick(ids, truthP, ledger, now)
      : policy === 'thompson' ? thompsonPick(people, ledger, now, explore)
      : policy === 'careful' ? carefulPick(people, ledger, now, explore)
      : greedyPick(people, ledger, now);

    const truthAtPick = scoreSlot(ids, truthP, ZERO_LEDGER, pick.start).pickup; // worst half-hour of the call
    const ps = ids.map((id) => truthAtPick[id]);
    out.push({ pAll: ps.reduce((a, b) => a * b, 1), rangAsleep: ps.some((p) => p === TRUE_P.R) });

    const answered = Object.fromEntries(ids.map((id) => [id, world() < truthAtPick[id]]));
    const levels = Object.fromEntries(FAMILY.map((m) => [m.id, truth[m.id][cellIndex(m.tz, pick.start)]]));
    ledger = chargeLedger(ledger, levels);

    const passive = scn.passive
      ? Object.fromEntries(FAMILY.map((m) => [m.id, passiveTraffic(m, truth[m.id], now, world)]))
      : {};
    if (policy === 'static' || policy === 'oracle') continue;

    people = people.map((p) => {
      const events: Observation[] = [
        ...(passive[p.id] ?? []),
        { at: pick.start, outcome: { kind: 'call', answered: answered[p.id] }, source: 'family_call' },
      ].sort((a, b) => a.at.getTime() - b.at.getTime());
      const learner: Learner = events.reduce((l, o) => observe(l, p.tz, o), p.learner);
      return { ...p, learner };
    });
  }
  return out;
}

function arg(name: string, fallback: number): number {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? Number(process.argv[i + 1]) : fallback;
}

const SEEDS = arg('seeds', 40);
const DAYS = arg('days', 56);
const SCENARIOS: Scenario[] = [
  { name: 'Busy family channel (5 calls/texts per person per day)', passive: true, lifeChange: false },
  { name: 'Quiet channel (only the family call teaches)', passive: false, lifeChange: false },
  { name: "Dad's meetings run to 3:30 PM from week 5 (busy channel)", passive: true, lifeChange: true },
  { name: "Dad's meetings run to 3:30 PM from week 5 (quiet channel)", passive: false, lifeChange: true },
];
const pct = (x: number) => `${(x * 100).toFixed(0).padStart(3)}%`;

for (const scn of SCENARIOS) {
  const weeks = Math.ceil(DAYS / 7);
  const table: Record<Policy, { p: number[]; asleep: number[] }> = Object.fromEntries(POLICIES.map((pol) =>
    [pol, { p: new Array(weeks).fill(0), asleep: new Array(weeks).fill(0) }])) as never;
  for (const pol of POLICIES) {
    for (let s = 1; s <= SEEDS; s++) {
      runOne(pol, scn, s, DAYS).forEach((r, d) => {
        table[pol].p[Math.floor(d / 7)] += r.pAll / (7 * SEEDS);
        table[pol].asleep[Math.floor(d / 7)] += (r.rangAsleep ? 1 : 0) / SEEDS;
      });
    }
  }
  console.log(`\n## ${scn.name}  (${SEEDS} seeds)`);
  console.log('Chance everyone picks up, by week:');
  console.log(`${'policy'.padEnd(10)}${Array.from({ length: weeks }, (_, w) => `  wk${w + 1}`).join('')}`);
  for (const pol of POLICIES) console.log(`${pol.padEnd(10)}${table[pol].p.map((x) => ` ${pct(x)}`).join('')}`);
  console.log('Calls per week that rang someone who was really asleep/busy:');
  for (const pol of POLICIES) console.log(`${pol.padEnd(10)}${table[pol].asleep.map((x) => x.toFixed(1).padStart(5)).join('')}`);
}
