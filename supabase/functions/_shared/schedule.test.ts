import { describe, expect, test } from 'bun:test';
import { DEMO_ANCHOR, DEMO_LEDGER, FAMILY } from './family.ts';
import { learnedLevel } from './learning.ts';
import { bookable, callLevels, fairPick, openingSlot, type LevelAt } from './schedule.ts';
import { greedyPick, thompsonPick } from './explore.ts';
import { findInsights } from './insights.ts';
import { seededFamily, seededLearner } from './fixtures.ts';
import { cellIndex } from './time.ts';
import { mulberry32 } from './rng.ts';

const ids = FAMILY.map((m) => m.id);
const people = seededFamily();
const learnedAt: LevelAt = (id, at) => {
  const p = people.find((x) => x.id === id)!;
  return learnedLevel(p.learner, cellIndex(p.tz, at), DEMO_ANCHOR);
};

describe('demo schedule on learned levels', () => {
  test('bookable set is exactly 12:00Z and 12:30Z', () => {
    const got = bookable(ids, learnedAt, DEMO_ANCHOR, 24).map((c) => c.start.toISOString());
    expect(got).toEqual(['2026-11-10T12:00:00.000Z', '2026-11-10T12:30:00.000Z']);
  });

  test('fairPick gives the maybe-hour to the person with the lightest ledger', () => {
    const pick = fairPick(ids, learnedAt, DEMO_LEDGER, DEMO_ANCHOR)!;
    expect(pick.start.toISOString()).toBe('2026-11-10T12:00:00.000Z');
    expect(pick.levels.you).toBe('Y');
  });

  test('opening proposal (8 PM Durham tomorrow) is 4 AM for Dad, so he counters', () => {
    const open = openingSlot(DEMO_ANCHOR, 'America/New_York');
    expect(open.toISOString()).toBe('2026-11-11T01:00:00.000Z');
    expect(callLevels(ids, learnedAt, open).dad).toBe('R');
  });

  test('probability optimizer agrees with the demo pick', () => {
    expect(greedyPick(people, DEMO_LEDGER, DEMO_ANCHOR).start.toISOString()).toBe('2026-11-10T12:00:00.000Z');
  });
});

describe('exploration', () => {
  test('Thompson sampling never rings anyone in a known-asleep slot', () => {
    for (let seed = 1; seed <= 200; seed++) {
      const pick = thompsonPick(people, DEMO_LEDGER, DEMO_ANCHOR, mulberry32(seed));
      for (const p of people) {
        expect(learnedAt(p.id, pick.start)).not.toBe('R');
      }
    }
  });
});

describe('insights', () => {
  const texts = FAMILY.flatMap((m) => findInsights(m.id, m.name, seededLearner(m), DEMO_ANCHOR)).map((i) => i.text);

  test('spots where the typed schedule and real pickups disagree', () => {
    expect(texts.some((t) => t.startsWith('Grandpa said weekdays 9:00 AM'))).toBe(true);
    expect(texts.some((t) => t.startsWith('You said weekdays 5:00 PM'))).toBe(true);
    expect(texts.some((t) => t.startsWith('Dad said weekdays 6:00 AM'))).toBe(true);
  });
});
