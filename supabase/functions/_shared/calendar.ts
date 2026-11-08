// Calendar signal: busy blocks from the phone's calendars (EventKit) — times only, never titles.
// Past blocks teach the learner ("busy" labels). Upcoming blocks are hard constraints.
// Movable blocks (your own events, no other attendees) can be suggested for a move.
import { SLOT_MS, localParts } from './time.ts';
import type { Observation } from './learning.ts';
import { CALL_MINUTES, optimizePick, type Ledger, type PickupAt, type Scored } from './schedule.ts';

export interface BusyBlock {
  readonly id: string;
  readonly memberId: string;
  readonly start: Date;
  readonly end: Date;
  readonly movable: boolean;
}

export interface MoveSuggestion {
  readonly blockId: string;
  readonly memberId: string;
  readonly from: Date; // block's current start
  readonly to: Date; // suggested new start
  readonly frees: Date; // family-time start this move unlocks
  readonly gain: number; // score improvement over the best slot without the move
}

/** Pickup probability inside a calendar event: effectively never. */
export const BUSY_PICKUP = 0.02;
/** A move must beat the current best by this much (log-prob units) to be worth asking. */
export const MIN_MOVE_GAIN = 0.5;
export const MAX_SUGGESTIONS = 3;
/** Moved events stay inside these local hours. */
const MOVE_EARLIEST_HOUR = 7;
const MOVE_LATEST_HOUR = 22;
/** How far (either direction, same local day) we look for a new home for a moved event. */
const MOVE_SEARCH_HOURS = 8;
const CALL_MS = CALL_MINUTES * 60_000;

const overlaps = (aStart: number, aEnd: number, bStart: number, bEnd: number) => aStart < bEnd && bStart < aEnd;

/** One "busy" label per half-hour cell a past block covers (at the cell midpoint). */
export function blocksToObservations(blocks: readonly BusyBlock[], now: Date): Observation[] {
  return blocks
    .filter((b) => b.end.getTime() <= now.getTime())
    .flatMap((b) => {
      const first = Math.floor(b.start.getTime() / SLOT_MS) * SLOT_MS;
      const cells: Observation[] = [];
      for (let t = first; t < b.end.getTime(); t += SLOT_MS) {
        cells.push({ at: new Date(t + SLOT_MS / 2), outcome: { kind: 'label', free: false }, source: 'calendar' });
      }
      return cells;
    });
}

/** Wrap a learned pickup model with hard calendar constraints. `ignore` drops blocks (for what-if moves). */
export function withCalendar(base: PickupAt, blocks: readonly BusyBlock[], ignore: ReadonlySet<string> = new Set()): PickupAt {
  const byMember = new Map<string, BusyBlock[]>();
  for (const b of blocks) {
    if (ignore.has(b.id)) continue;
    byMember.set(b.memberId, [...(byMember.get(b.memberId) ?? []), b]);
  }
  return (memberId, at) => {
    const t = at.getTime();
    const busy = (byMember.get(memberId) ?? []).some((b) => overlaps(t, t + SLOT_MS, b.start.getTime(), b.end.getTime()));
    return busy ? BUSY_PICKUP : base(memberId, at);
  };
}

/** Best family slot given learned rhythms + everyone's calendars. */
export function calendarPick(
  members: readonly string[], pickupAt: PickupAt, blocks: readonly BusyBlock[], ledger: Ledger, from: Date, hours = 24,
): Scored {
  return optimizePick(members, withCalendar(pickupAt, blocks), ledger, from, hours);
}

/** Nearest same-day start for `block` that avoids the member's other blocks and the family call. */
export function findNewHome(
  block: BusyBlock, otherBlocks: readonly BusyBlock[], callStart: Date, tz: string,
): Date | null {
  const dur = block.end.getTime() - block.start.getTime();
  const day = localParts(tz, block.start);
  const sameDay = (d: Date) => {
    const p = localParts(tz, d);
    return p.year === day.year && p.month === day.month && p.day === day.day;
  };
  const inHours = (s: number) => {
    const startHour = localParts(tz, new Date(s)).hour;
    const end = localParts(tz, new Date(s + dur - 1));
    return startHour >= MOVE_EARLIEST_HOUR && end.hour < MOVE_LATEST_HOUR && sameDay(new Date(s + dur - 1));
  };
  const free = (s: number) =>
    !overlaps(s, s + dur, callStart.getTime(), callStart.getTime() + CALL_MS) &&
    otherBlocks.every((o) => o.memberId !== block.memberId || o.id === block.id ||
      !overlaps(s, s + dur, o.start.getTime(), o.end.getTime()));

  const steps = (MOVE_SEARCH_HOURS * 60 * 60_000) / SLOT_MS;
  for (let k = 1; k <= steps; k++) {
    for (const s of [block.start.getTime() - k * SLOT_MS, block.start.getTime() + k * SLOT_MS]) {
      if (sameDay(new Date(s)) && inHours(s) && free(s)) return new Date(s);
    }
  }
  return null;
}

/**
 * "Move Gym to 6 PM → frees 8 PM with Mom."
 * For each upcoming movable block: would the family's best slot get clearly better without it,
 * does that better slot actually collide with the block, and is there somewhere else to put it?
 */
export function suggestMoves(
  members: readonly string[], tzOf: (memberId: string) => string, pickupAt: PickupAt,
  blocks: readonly BusyBlock[], ledger: Ledger, from: Date, hours = 24,
): MoveSuggestion[] {
  const base = calendarPick(members, pickupAt, blocks, ledger, from, hours);
  const horizon = from.getTime() + hours * 60 * 60_000;
  const movable = blocks.filter((b) =>
    b.movable && members.includes(b.memberId) && b.start.getTime() >= from.getTime() && b.start.getTime() < horizon);

  const suggestions = movable.flatMap((b): MoveSuggestion[] => {
    const alt = optimizePick(members, withCalendar(pickupAt, blocks, new Set([b.id])), ledger, from, hours);
    const gain = alt.score - base.score;
    const collides = overlaps(alt.start.getTime(), alt.start.getTime() + CALL_MS, b.start.getTime(), b.end.getTime());
    if (gain < MIN_MOVE_GAIN || !collides) return [];
    const to = findNewHome(b, blocks, alt.start, tzOf(b.memberId));
    return to ? [{ blockId: b.id, memberId: b.memberId, from: b.start, to, frees: alt.start, gain }] : [];
  });

  return [...suggestions].sort((a, b) => b.gain - a.gain).slice(0, MAX_SUGGESTIONS);
}
