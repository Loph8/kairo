// Per-person reachability learner.
// Each (weekday|weekend) x 30-min cell is a Beta posterior over "will they pick up / reply fast here?".
// The typed onboarding schedule is the prior; every call, text and widget tap in the app's own channel
// is evidence; old evidence fades (28-day half-life) so the model follows life changes.
import { cellIndex, localParts, dayKindOf, SLOTS_PER_DAY, toMinutes, type DayKind } from './time.ts';

export type Level = 'G' | 'Y' | 'R';
export const CELLS = SLOTS_PER_DAY * 2;
export const PRIOR_STRENGTH = 2;
export const HALF_LIFE_MS = 28 * 24 * 60 * 60 * 1000;
export const PRIOR_MEAN: Readonly<Record<Level, number>> = { G: 0.75, Y: 0.5, R: 0.125 };
export const GREEN_AT = 0.65;
export const RED_BELOW = 0.35;
export const FAST_REPLY_S = 600;
export const SLOW_REPLY_S = 3600;
export const LABEL_WEIGHT = 2;

export interface Onboarding {
  readonly wake: string;
  readonly bed: string;
  readonly busy: ReadonlyArray<readonly [string, string]>;
}

export type Outcome =
  | { readonly kind: 'call'; readonly answered: boolean }
  | { readonly kind: 'text'; readonly replySeconds: number | null }
  | { readonly kind: 'label'; readonly free: boolean }; // widget "Busy" tap or "Connected? 👍/👎"

export interface Observation {
  readonly at: Date;
  readonly outcome: Outcome;
  readonly source: 'channel' | 'family_call' | 'widget' | 'calendar' | 'shortcut' | 'sim';
}

export interface Learner {
  readonly prelim: readonly Level[];   // what the person told us (or approved later)
  readonly alpha: readonly number[];   // decayed success evidence
  readonly beta: readonly number[];    // decayed failure evidence
  readonly hits: readonly number[];    // raw counts, for plain-language insights
  readonly seen: readonly number[];
  readonly updatedAt: number;          // ms; evidence is decayed to this instant
}

export interface Posterior { readonly a: number; readonly b: number; readonly mean: number; readonly evidence: number }

function inRange(m: number, from: number, to: number): boolean {
  return from <= to ? m >= from && m < to : m >= from || m < to; // ranges may wrap midnight
}

/** True while the person said they sleep (outside wake→bed, local time). A hard rule: no amount of learning makes it a good time. */
export function asleepAt(onb: Onboarding, tz: string, at: Date): boolean {
  const p = localParts(tz, at);
  return !inRange(p.hour * 60 + p.minute, toMinutes(onb.wake), toMinutes(onb.bed) % 1440);
}

/** Turn the 30-second onboarding answers into a G/Y/R grid for weekdays and weekends. */
export function prelimGrid(onb: Onboarding): Level[] {
  const wake = toMinutes(onb.wake);
  const bed = toMinutes(onb.bed) % 1440;
  const busy = onb.busy.map(([f, t]) => [toMinutes(f), toMinutes(t)] as const);
  const levelFor = (kind: DayKind, slot: number): Level => {
    const m = slot * 30;
    if (!inRange(m, wake, bed)) return 'R';
    if (kind === 'weekday' && busy.some(([f, t]) => inRange(m, f, t))) return 'R';
    if (inRange(m, wake, wake + 30) || inRange(m, (bed + 1410) % 1440, bed)) return 'Y';
    return 'G';
  };
  return Array.from({ length: CELLS }, (_, i) =>
    levelFor(i < SLOTS_PER_DAY ? 'weekday' : 'weekend', i % SLOTS_PER_DAY));
}

export function createLearner(onb: Onboarding, now: Date): Learner {
  const zeros = new Array<number>(CELLS).fill(0);
  return { prelim: prelimGrid(onb), alpha: zeros, beta: zeros, hits: zeros, seen: zeros, updatedAt: now.getTime() };
}

/** Reward in [0,1] and how much it counts. */
export function reward(outcome: Outcome): { r: number; weight: number } {
  switch (outcome.kind) {
    case 'call': return { r: outcome.answered ? 1 : 0, weight: 1 };
    case 'label': return { r: outcome.free ? 1 : 0, weight: LABEL_WEIGHT };
    case 'text': {
      const s = outcome.replySeconds;
      if (s === null) return { r: 0, weight: 1 };
      return { r: s <= FAST_REPLY_S ? 1 : s <= SLOW_REPLY_S ? 0.5 : 0, weight: 1 };
    }
  }
}

const decayFactor = (ms: number) => Math.pow(2, -ms / HALF_LIFE_MS);

/** Pure update: returns a new learner with the observation folded in. */
export function observe(learner: Learner, tz: string, obs: Observation): Learner {
  const t = obs.at.getTime();
  const later = Math.max(t, learner.updatedAt);
  const fade = decayFactor(later - learner.updatedAt);           // age existing evidence to `later`
  const w = decayFactor(later - t) * reward(obs.outcome).weight; // late-arriving events count less
  const { r } = reward(obs.outcome);
  const i = cellIndex(tz, obs.at);
  const bump = (arr: readonly number[], add: number) => arr.map((v, j) => v * fade + (j === i ? add : 0));
  return {
    prelim: learner.prelim,
    alpha: bump(learner.alpha, w * r),
    beta: bump(learner.beta, w * (1 - r)),
    hits: learner.hits.map((v, j) => v + (j === i && r >= 0.5 ? 1 : 0)),
    seen: learner.seen.map((v, j) => v + (j === i ? 1 : 0)),
    updatedAt: later,
  };
}

export function observeAll(learner: Learner, tz: string, observations: readonly Observation[]): Learner {
  return [...observations].sort((x, y) => x.at.getTime() - y.at.getTime())
    .reduce((acc, o) => observe(acc, tz, o), learner);
}

export function posterior(learner: Learner, cell: number, now: Date): Posterior {
  const fade = decayFactor(Math.max(0, now.getTime() - learner.updatedAt));
  const m = PRIOR_MEAN[learner.prelim[cell]];
  const a = PRIOR_STRENGTH * m + learner.alpha[cell] * fade;
  const b = PRIOR_STRENGTH * (1 - m) + learner.beta[cell] * fade;
  return { a, b, mean: a / (a + b), evidence: (learner.alpha[cell] + learner.beta[cell]) * fade };
}

export function levelOf(p: number): Level {
  return p >= GREEN_AT ? 'G' : p < RED_BELOW ? 'R' : 'Y';
}

export function learnedLevel(learner: Learner, cell: number, now: Date): Level {
  return levelOf(posterior(learner, cell, now).mean);
}

/** Probability-of-pickup the scheduler should use for someone in `tz` at instant `at`. */
export function pickupAt(learner: Learner, tz: string, at: Date, now: Date): number {
  return posterior(learner, cellIndex(tz, at), now).mean;
}

/** The person approved a suggested change: the learned level becomes their stated schedule. */
export function adoptLevels(learner: Learner, cells: readonly number[], level: Level): Learner {
  const set = new Set(cells);
  return { ...learner, prelim: learner.prelim.map((l, i) => (set.has(i) ? level : l)) };
}

export function dayKindAt(tz: string, at: Date): DayKind {
  return dayKindOf(localParts(tz, at).weekday);
}
