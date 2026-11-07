// Deterministic two-week history so the demo heatmaps and insights show up on first launch.
// Generated from TRUTH_BANDS; labeled "demo data" in the app.
import { localParts, localToUtc, dayKindOf, SLOTS_PER_DAY, DAY_MS, toMinutes, type DayKind } from './time.ts';
import { CELLS, type Level, type Observation } from './learning.ts';
import type { Member } from './family.ts';

export const SEED_DAYS = 14;
type Band = readonly [string, string, Level];

/** Truth grid: weekday bands as given; on weekends interior busy blocks soften to Y, sleep stays R. */
export function truthGrid(bands: readonly Band[]): Level[] {
  const weekday: Level[] = new Array(SLOTS_PER_DAY).fill('R');
  const weekend: Level[] = new Array(SLOTS_PER_DAY).fill('R');
  bands.forEach(([f, t, level], idx) => {
    const isSleep = level === 'R' && (idx === 0 || idx === bands.length - 1);
    for (let s = toMinutes(f) / 30; s < toMinutes(t) / 30; s++) {
      weekday[s] = level;
      weekend[s] = level === 'R' && !isSleep ? 'Y' : level;
    }
  });
  return [...weekday, ...weekend];
}

/** [events, successes] per cell over the two weeks, by true level and day kind. */
const COUNTS: Record<DayKind, Record<Level, readonly [number, number]>> = {
  weekday: { G: [8, 7], Y: [8, 4], R: [4, 0] },
  weekend: { G: [4, 4], Y: [4, 2], R: [1, 0] },
};
const ASLEEP_COUNT: readonly [number, number] = [1, 0];

/** Successes spread evenly, slightly favoring recent days (Bresenham over oldest→newest). */
function isSuccess(i: number, n: number, k: number): boolean {
  return Math.floor(((i + 1) * k) / n) > Math.floor((i * k) / n);
}

export function seedObservations(member: Member, bands: readonly Band[], anchor: Date): Observation[] {
  const truth = truthGrid(bands);
  const today = localParts(member.tz, anchor);
  const days = Array.from({ length: SEED_DAYS }, (_, back) => {
    const noon = new Date(Date.UTC(today.year, today.month - 1, today.day, 12) - (back + 1) * DAY_MS);
    return { y: noon.getUTCFullYear(), m: noon.getUTCMonth() + 1, d: noon.getUTCDate(), kind: dayKindOf(noon.getUTCDay()) };
  }).reverse(); // oldest first

  const out: Observation[] = [];
  for (let cell = 0; cell < CELLS; cell++) {
    const kind: DayKind = cell < SLOTS_PER_DAY ? 'weekday' : 'weekend';
    const slot = cell % SLOTS_PER_DAY;
    const level = truth[cell];
    const sleeping = level === 'R' && truth[slot] === 'R' && truth[SLOTS_PER_DAY + slot] === 'R';
    const [n, k] = sleeping ? ASLEEP_COUNT : COUNTS[kind][level];
    const matching = days.filter((d) => d.kind === kind).slice(-n);
    matching.forEach((d, i) => {
      const ok = isSuccess(i, matching.length, Math.min(k, matching.length));
      const at = localToUtc(member.tz, d.y, d.m, d.d, Math.floor(slot / 2), (slot % 2) * 30 + 10);
      out.push({
        at, source: 'channel',
        outcome: i % 2 === 0 ? { kind: 'call', answered: ok } : { kind: 'text', replySeconds: ok ? 240 : null },
      });
    });
  }
  return out.sort((a, b) => a.at.getTime() - b.at.getTime());
}
