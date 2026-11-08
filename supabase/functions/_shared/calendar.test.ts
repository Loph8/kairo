import { describe, expect, test } from 'bun:test';
import {
  BUSY_PICKUP, blocksToObservations, calendarPick, findNewHome, suggestMoves, withCalendar, type BusyBlock,
} from './calendar.ts';
import type { PickupAt } from './schedule.ts';

const at = (hhmm: string, day = '2026-11-10') => new Date(`${day}T${hhmm}:00Z`);
const block = (id: string, memberId: string, from: string, to: string, movable = true): BusyBlock =>
  ({ id, memberId, start: at(from), end: at(to), movable });

/** Everyone is great 20:00–21:00 UTC, so-so otherwise. */
const eveningPeak: PickupAt = (_m, t) => (t.getUTCHours() === 20 ? 0.95 : 0.4);
const utc = () => 'UTC';
const FROM = at('08:00');

describe('blocksToObservations', () => {
  test('past blocks become one busy label per half-hour cell; future blocks are ignored', () => {
    const obs = blocksToObservations(
      [block('a', 'you', '09:00', '10:00'), block('b', 'you', '15:00', '16:00')], at('12:00'));
    expect(obs).toHaveLength(2);
    expect(obs.every((o) => o.source === 'calendar' && o.outcome.kind === 'label' && !o.outcome.free)).toBe(true);
    expect(obs.map((o) => o.at.toISOString())).toEqual([at('09:15').toISOString(), at('09:45').toISOString()]);
  });
});

describe('withCalendar', () => {
  const blocks = [block('gym', 'you', '20:00', '21:00')];
  test('a cell inside an event is effectively never', () => {
    expect(withCalendar(eveningPeak, blocks)('you', at('20:30'))).toBe(BUSY_PICKUP);
    expect(withCalendar(eveningPeak, blocks)('mom', at('20:30'))).toBe(0.95);
  });
  test('ignored blocks fall back to the learned model', () => {
    expect(withCalendar(eveningPeak, blocks, new Set(['gym']))('you', at('20:30'))).toBe(0.95);
  });
});

describe('calendarPick', () => {
  test('never lands on a calendar event', () => {
    const pick = calendarPick(['you', 'mom'], eveningPeak, [block('gym', 'you', '20:00', '21:00')], {}, FROM, 24);
    const s = pick.start.getTime();
    expect(s + 45 * 60_000 <= at('20:00').getTime() || s >= at('21:00').getTime()).toBe(true);
  });
});

describe('suggestMoves', () => {
  test('suggests moving a movable event that blocks the golden hour', () => {
    const blocks = [block('gym', 'you', '20:00', '21:00')];
    const [s, ...rest] = suggestMoves(['you', 'mom'], utc, eveningPeak, blocks, {}, FROM, 24);
    expect(rest).toHaveLength(0);
    expect(s.blockId).toBe('gym');
    expect(s.frees.getUTCHours()).toBe(20);
    expect(s.to.toISOString()).toBe(at('19:00').toISOString()); // nearest spot that clears the call
    expect(s.gain).toBeGreaterThan(0.5);
  });

  test('never suggests moving an event you do not own', () => {
    const blocks = [block('standup', 'you', '20:00', '21:00', false)];
    expect(suggestMoves(['you', 'mom'], utc, eveningPeak, blocks, {}, FROM, 24)).toEqual([]);
  });

  test('no suggestion when the event is not in the way', () => {
    const blocks = [block('dentist', 'you', '10:00', '11:00')];
    expect(suggestMoves(['you', 'mom'], utc, eveningPeak, blocks, {}, FROM, 24)).toEqual([]);
  });

  test('no suggestion when the moved event has nowhere to go', () => {
    const wall = [block('am', 'you', '07:00', '20:00', false), block('pm', 'you', '21:00', '22:00', false)];
    const blocks = [...wall, block('gym', 'you', '20:00', '21:00')];
    expect(suggestMoves(['you', 'mom'], utc, eveningPeak, blocks, {}, FROM, 24)).toEqual([]);
  });
});

describe('findNewHome', () => {
  test('stays inside waking hours on the same day', () => {
    const gym = block('gym', 'you', '07:00', '08:00');
    const to = findNewHome(gym, [gym], at('07:00'), 'UTC');
    expect(to?.toISOString()).toBe(at('08:00').toISOString());
  });
});
