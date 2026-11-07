import { describe, expect, test } from 'bun:test';
import { DEMO_ANCHOR, FAMILY, TRUTH_BANDS } from './family.ts';
import { createLearner, learnedLevel, observe, posterior, prelimGrid, reward, CELLS } from './learning.ts';
import { truthGrid } from './seed.ts';
import { seededLearner } from './fixtures.ts';
import { fmtSlot, SLOTS_PER_DAY } from './time.ts';

const you = FAMILY.find((m) => m.id === 'you')!;

describe('prelimGrid', () => {
  test('turns typed wake/bed/busy into levels', () => {
    const g = prelimGrid(you.onboarding);
    expect(g[13]).toBe('R'); // 6:30 asleep
    expect(g[14]).toBe('Y'); // 7:00 just woke
    expect(g[15]).toBe('G'); // 7:30
    expect(g[20]).toBe('R'); // 10:00 weekday busy
    expect(g[SLOTS_PER_DAY + 20]).toBe('G'); // 10:00 weekend: busy hours are weekday-only
    expect(g[47]).toBe('Y'); // 23:30, last half hour before bed
  });
});

describe('reward', () => {
  test('maps channel outcomes to pickup evidence', () => {
    expect(reward({ kind: 'call', answered: true }).r).toBe(1);
    expect(reward({ kind: 'call', answered: false }).r).toBe(0);
    expect(reward({ kind: 'text', replySeconds: 120 }).r).toBe(1);
    expect(reward({ kind: 'text', replySeconds: 1800 }).r).toBe(0.5);
    expect(reward({ kind: 'text', replySeconds: null }).r).toBe(0);
  });
});

describe('observe', () => {
  test('is pure and moves the right cell toward the outcome', () => {
    const l0 = createLearner(you.onboarding, DEMO_ANCHOR);
    const at = new Date('2026-11-09T22:10:00Z'); // Mon 5:10 PM Durham, weekday cell 34
    const l1 = observe(l0, you.tz, { at, outcome: { kind: 'call', answered: false }, source: 'channel' });
    expect(l0.beta[34]).toBe(0);
    expect(l1.beta[34]).toBeGreaterThan(0);
    expect(posterior(l1, 34, at).mean).toBeLessThan(posterior(l0, 34, at).mean);
  });

  test('old evidence fades back toward the typed schedule', () => {
    let l = createLearner(you.onboarding, DEMO_ANCHOR);
    const at = new Date('2026-11-09T22:10:00Z');
    for (let i = 0; i < 6; i++) l = observe(l, you.tz, { at, outcome: { kind: 'call', answered: false }, source: 'channel' });
    const soon = posterior(l, 34, at).mean;
    const later = posterior(l, 34, new Date(at.getTime() + 120 * 864e5)).mean;
    expect(later).toBeGreaterThan(soon);
  });
});

describe('seeded history', () => {
  for (const m of FAMILY) {
    test(`${m.name}: learned levels match the true rhythm in every cell`, () => {
      const learner = seededLearner(m);
      const truth = truthGrid(TRUTH_BANDS[m.id]);
      const wrong: string[] = [];
      for (let c = 0; c < CELLS; c++) {
        const got = learnedLevel(learner, c, DEMO_ANCHOR);
        if (got !== truth[c]) wrong.push(`${c < SLOTS_PER_DAY ? 'wd' : 'we'} ${fmtSlot(c % SLOTS_PER_DAY)} want ${truth[c]} got ${got}`);
      }
      expect(wrong).toEqual([]);
    });
  }
});
