// Thompson sampling: the "try, see, adjust" part of the loop.
// Instead of always picking the slot that looks best today, sample a plausible pickup rate for every
// person and half-hour from their Beta posterior, then optimize against that sample. Uncertain slots
// sometimes win, get tried, and the outcome teaches the learner. Confident-bad slots (asleep) never win.
import { beta, type Rng } from './rng.ts';
import { cellIndex } from './time.ts';
import { posterior, type Learner } from './learning.ts';
import { optimizePick, scoreSlot, candidateStarts, NEVER_RING_BELOW, type Ledger, type PickupAt, type Scored } from './schedule.ts';

export interface Person { readonly id: string; readonly tz: string; readonly learner: Learner }

export function meanPickup(people: readonly Person[], now: Date): PickupAt {
  const byId = new Map(people.map((p) => [p.id, p]));
  return (id, at) => {
    const p = byId.get(id)!;
    return posterior(p.learner, cellIndex(p.tz, at), now).mean;
  };
}

export function sampledPickup(people: readonly Person[], now: Date, rng: Rng): PickupAt {
  const byId = new Map(people.map((p) => [p.id, p]));
  const memo = new Map<string, number>();
  return (id, at) => {
    const p = byId.get(id)!;
    const cell = cellIndex(p.tz, at);
    const key = `${id}:${cell}`;
    const hit = memo.get(key);
    if (hit !== undefined) return hit;
    const post = posterior(p.learner, cell, now);
    const draw = post.mean < NEVER_RING_BELOW ? post.mean : beta(rng, post.a, post.b);
    memo.set(key, draw);
    return draw;
  };
}

export function thompsonPick(people: readonly Person[], ledger: Ledger, from: Date, rng: Rng, hours = 24): Scored {
  return optimizePick(people.map((p) => p.id), sampledPickup(people, from, rng), ledger, from, hours);
}

export function greedyPick(people: readonly Person[], ledger: Ledger, from: Date, hours = 24): Scored {
  return optimizePick(people.map((p) => p.id), meanPickup(people, from), ledger, from, hours);
}

/** Score units: log-probability. 0.4 ≈ "within 1.5x of the best-looking slot's chance". */
export const EXPLORE_MARGIN = 0.4;

/**
 * Careful Thompson: only explore among slots that already look nearly as good as the best one.
 * A family call is a costly experiment (four people must pick up), so we never gamble on long shots,
 * but we do re-test close runners-up. That is what lets the schedule move when someone's life changes.
 */
export function carefulPick(people: readonly Person[], ledger: Ledger, from: Date, rng: Rng,
  hours = 24, margin = EXPLORE_MARGIN): Scored {
  const ids = people.map((p) => p.id);
  const mean = meanPickup(people, from);
  const sampled = sampledPickup(people, from, rng);
  const scored = candidateStarts(from, hours).map((t) => ({ m: scoreSlot(ids, mean, ledger, t), s: scoreSlot(ids, sampled, ledger, t) }));
  const safe = scored.filter(({ m }) => Object.values(m.pickup).every((p) => p >= NEVER_RING_BELOW));
  const pool = safe.length ? safe : scored;
  const best = Math.max(...pool.map(({ m }) => m.score));
  const near = pool.filter(({ m }) => m.score >= best - margin);
  const winner = near.reduce((a, b) => (b.s.score > a.s.score ? b : a));
  return winner.m;
}
