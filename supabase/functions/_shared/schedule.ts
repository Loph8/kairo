// Choosing the family call slot.
// fairPick: level-based and deterministic, used for the demo script and the agents' shared facts.
// optimizePick: probability-based objective the learning loop optimizes (see explore.ts for Thompson).
import { SLOT_MS } from './time.ts';
import { GREEN_AT, type Level } from './learning.ts';

export const CALL_MINUTES = 45;
export const RED_PENALTY = 100;
export const FAIRNESS_LAMBDA = 0.3;
export const NEVER_RING_BELOW = 0.2;

export type LevelAt = (memberId: string, at: Date) => Level;
export type PickupAt = (memberId: string, at: Date) => number;
export type Ledger = Readonly<Record<string, number>>;

export interface Candidate { readonly start: Date; readonly levels: Readonly<Record<string, Level>> }

const RANK: Record<Level, number> = { G: 0, Y: 1, R: 2 };
const worse = (a: Level, b: Level): Level => (RANK[a] >= RANK[b] ? a : b);

/** Cells a call starting at `start` touches (45 min → this half hour and the next). */
export function cellsTouched(start: Date): Date[] {
  const n = Math.ceil(CALL_MINUTES / 30);
  return Array.from({ length: n }, (_, i) => new Date(start.getTime() + i * SLOT_MS));
}

export function candidateStarts(from: Date, hours: number): Date[] {
  const first = Math.ceil(from.getTime() / SLOT_MS) * SLOT_MS;
  return Array.from({ length: hours * 2 }, (_, i) => new Date(first + i * SLOT_MS));
}

export function callLevels(members: readonly string[], levelAt: LevelAt, start: Date): Record<string, Level> {
  return Object.fromEntries(members.map((m) =>
    [m, cellsTouched(start).map((t) => levelAt(m, t)).reduce(worse)]));
}

export function candidates(members: readonly string[], levelAt: LevelAt, from: Date, hours: number): Candidate[] {
  return candidateStarts(from, hours).map((start) => ({ start, levels: callLevels(members, levelAt, start) }));
}

export function bookable(members: readonly string[], levelAt: LevelAt, from: Date, hours: number): Candidate[] {
  return candidates(members, levelAt, from, hours).filter((c) => !Object.values(c.levels).includes('R'));
}

/** Who has already taken the awkward hours pays more to take another one. */
export function levelPenalty(levels: Readonly<Record<string, Level>>, ledger: Ledger): number {
  return Object.entries(levels).reduce((sum, [m, l]) =>
    sum + (l === 'R' ? RED_PENALTY : l === 'Y' ? 1 + (ledger[m] ?? 0) / 30 : 0), 0);
}

const byPenalty = (ledger: Ledger) => (a: Candidate, b: Candidate) =>
  levelPenalty(a.levels, ledger) - levelPenalty(b.levels, ledger) || a.start.getTime() - b.start.getTime();

export function fairPick(members: readonly string[], levelAt: LevelAt, ledger: Ledger, from: Date, hours = 24): Candidate | null {
  return [...bookable(members, levelAt, from, hours)].sort(byPenalty(ledger))[0] ?? null;
}

export function leastBadPick(members: readonly string[], levelAt: LevelAt, ledger: Ledger, from: Date, hours = 24): Candidate {
  return [...candidates(members, levelAt, from, hours)].sort(byPenalty(ledger))[0];
}

/** "Same time tomorrow" in the organizer's zone: the naive slot a human would propose first. */
export function openingSlot(anchor: Date, organizerTz: string, localHour = 20): Date {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: organizerTz, year: 'numeric', month: '2-digit', day: '2-digit' })
    .format(new Date(anchor.getTime() + 24 * 3600 * 1000));
  const [y, m, d] = parts.split('-').map(Number);
  const wall = Date.UTC(y, m - 1, d, localHour);
  const probe = new Intl.DateTimeFormat('en-US', { timeZone: organizerTz, hourCycle: 'h23', hour: 'numeric', day: 'numeric' })
    .formatToParts(new Date(wall));
  const h = +probe.find((p) => p.type === 'hour')!.value;
  const dd = +probe.find((p) => p.type === 'day')!.value;
  const offsetH = (dd - d) * 24 + h - localHour;
  return new Date(wall - offsetH * 3600 * 1000);
}

export interface Scored { readonly start: Date; readonly score: number; readonly pickup: Readonly<Record<string, number>> }

/**
 * Expected-success objective with fairness:
 *   score = Σ log p(member picks up) − λ Σ_{inconvenient} (1 + ledger/60)
 * Slots where anyone is below NEVER_RING_BELOW are skipped unless nothing else exists.
 */
export function scoreSlot(members: readonly string[], pickupAt: PickupAt, ledger: Ledger, start: Date): Scored {
  const pickup = Object.fromEntries(members.map((m) =>
    [m, Math.min(...cellsTouched(start).map((t) => pickupAt(m, t)))]));
  const score = members.reduce((s, m) => {
    const p = Math.max(pickup[m], 1e-6);
    const awkward = p < GREEN_AT ? FAIRNESS_LAMBDA * (1 + (ledger[m] ?? 0) / 60) : 0;
    return s + Math.log(p) - awkward;
  }, 0);
  return { start, score, pickup };
}

export function optimizePick(members: readonly string[], pickupAt: PickupAt, ledger: Ledger, from: Date, hours = 24): Scored {
  const all = candidateStarts(from, hours).map((t) => scoreSlot(members, pickupAt, ledger, t));
  const safe = all.filter((s) => Object.values(s.pickup).every((p) => p >= NEVER_RING_BELOW));
  const pool = safe.length ? safe : all;
  return pool.reduce((best, s) => (s.score > best.score ? s : best));
}

export function chargeLedger(ledger: Ledger, levels: Readonly<Record<string, Level>>): Ledger {
  return Object.fromEntries(Object.entries(ledger).map(([m, v]) =>
    [m, v + (levels[m] && levels[m] !== 'G' ? CALL_MINUTES : 0)]));
}
