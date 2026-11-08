// Turns stored rows into what phones show: 48 half-hour levels per person, the best family slot,
// and calendar moves worth suggesting. Pure: no I/O, so it is tested in bun and runs in Deno.
import { blocksToObservations, calendarPick, suggestMoves, withCalendar, type BusyBlock } from './calendar.ts';
import { meanPickup, type Person } from './explore.ts';
import type { Member } from './family.ts';
import { findInsights } from './insights.ts';
import { asleepAt, CELLS, createLearner, learnedLevel, levelOf, observeAll, type Learner, type Level, type Observation } from './learning.ts';
import { CALL_MINUTES, NEVER_RING_BELOW, type Ledger, type PickupAt, type Scored } from './schedule.ts';
import { SLOT_MS } from './time.ts';

export const FORECAST_SLOTS = 48;           // 24 hours of half-hour slots
export const SEARCH_HOURS = 24;             // how far ahead the family slot is searched first
export const WIDE_SEARCH_HOURS = 72;        // searched when the next 24 h have no time that works for everyone

export interface MemberRow extends Member {
  readonly burdenMin: number;
  readonly simulated: boolean;
  readonly persona: string | null;
  /** How the family reaches this person: their number and the call apps they connected. */
  readonly contact?: Contact;
}
export const CONTACT_APPS = ['whatsapp', 'kakaotalk', 'wechat', 'line', 'telegram', 'messenger', 'instagram'] as const;
export type ContactApp = typeof CONTACT_APPS[number];
export interface Contact { readonly phone: string | null; readonly apps: Partial<Record<ContactApp, string>> }
export const NO_CONTACT: Contact = { phone: null, apps: {} };
export interface StoredObservation extends Observation { readonly memberId: string; readonly historical?: boolean }

export interface BookingRow {
  readonly id: string;
  readonly start: Date;
  readonly durationMin: number;
  readonly acceptedBy: readonly string[];
  readonly status: 'proposed' | 'booked' | 'completed';
  readonly levels: Readonly<Record<string, Level>>;
}

export interface FamilyInputs {
  readonly members: readonly MemberRow[];
  readonly observations: readonly StoredObservation[];
  readonly blocks: readonly BusyBlock[];
  readonly bookings: readonly BookingRow[];
}

export interface MemberView {
  id: string; name: string; city: string; tz: string; simulated: boolean;
  phone: string | null;     // for calls: Phone, FaceTime, WhatsApp…
  apps: Partial<Record<ContactApp, string>>;   // call apps they connected in Settings, with their id there
  levels: Level[];          // next 24 h, half-hour slots from forecastStart
  week: string;             // 96 learned levels: 48 weekday slots then 48 weekend slots (local time)
  said: string;             // the same 96 cells as typed in onboarding
  insights: string[];       // where what they said and what the channel shows disagree
  signals: number;          // outcomes in the last 14 days (calls, texts, taps)
}
export interface ChangeView {
  memberId: string; at: string; source: string; kind: string; positive: boolean;
  changed: { cell: number; from: Level; to: Level }[];   // cells of `week` the latest signal flipped
}
export interface SuggestionView {
  start: string; end: string;
  pickup: Record<string, number>;
  levels: Record<string, Level>;
  everyoneLikely: boolean;
}
export interface MoveView { blockId: string; memberId: string; from: string; to: string; frees: string; gain: number }
export interface BookingView { id: string; start: string; end: string; acceptedBy: string[]; status: BookingRow['status'] }

export interface FamilyState {
  now: string;
  forecastStart: string;
  slotMinutes: number;
  isDemo: boolean;
  members: MemberView[];
  suggestion: SuggestionView | null;
  moves: MoveView[];
  bookings: BookingView[];
  lastChange: ChangeView | null;
}

export const floorToSlot = (d: Date): Date => new Date(Math.floor(d.getTime() / SLOT_MS) * SLOT_MS);
const iso = (d: Date) => d.toISOString();
const callEnd = (start: Date) => new Date(start.getTime() + CALL_MINUTES * 60_000);

/** Each person's learner = what they said in onboarding + every outcome since + past calendar blocks. */
export function buildPeople(inputs: FamilyInputs, now: Date): Person[] {
  return inputs.members.map((m) => {
    const own = inputs.observations.filter((o) => o.memberId === m.id && o.at.getTime() <= now.getTime());
    const fromCalendar = blocksToObservations(inputs.blocks.filter((b) => b.memberId === m.id), now);
    const learner = observeAll(createLearner(m.onboarding, now), m.tz, [...own, ...fromCalendar]);
    return { id: m.id, tz: m.tz, learner };
  });
}

const RECENT_MS = 14 * 24 * 3600 * 1000;
const weekOf = (learner: Learner, now: Date) =>
  Array.from({ length: CELLS }, (_, c) => learnedLevel(learner, c, now)).join('');

/** The newest live signal, and which week cells it flipped (what "the AI just learned"). */
function latestChange(inputs: FamilyInputs, people: readonly Person[], now: Date): ChangeView | null {
  const live = inputs.observations.filter((o) => !o.historical && o.at.getTime() <= now.getTime());
  const last = live.reduce<StoredObservation | null>((a, o) => (!a || o.at > a.at ? o : a), null);
  if (!last) return null;
  const member = inputs.members.find((m) => m.id === last.memberId);
  const after = people.find((p) => p.id === last.memberId);
  if (!member || !after) return null;
  const before = buildPeople({ ...inputs, members: [member], observations: inputs.observations.filter((o) => o !== last) }, now)[0];
  const was = weekOf(before.learner, now), is = weekOf(after.learner, now);
  const changed = [...is].flatMap((to, cell) => (to === was[cell] ? [] : [{ cell, from: was[cell] as Level, to: to as Level }]));
  const o = last.outcome;
  const positive = o.kind === 'call' ? o.answered : o.kind === 'label' ? o.free : o.replySeconds !== null;
  return { memberId: last.memberId, at: iso(last.at), source: last.source, kind: o.kind, positive, changed };
}

export const ledgerOf = (members: readonly MemberRow[]): Ledger =>
  Object.fromEntries(members.map((m) => [m.id, m.burdenMin]));

/** Sleep hours are a hard rule, like meetings: a few answered 2 AM test calls never make 2 AM a good time. */
export function withSleep(base: PickupAt, members: readonly MemberRow[]): PickupAt {
  const byId = new Map(members.map((m) => [m.id, m]));
  return (id, at) => {
    const m = byId.get(id);
    return m && asleepAt(m.onboarding, m.tz, at) ? 0 : base(id, at);
  };
}

const worksForAll = (s: Scored) => Object.values(s.pickup).every((p) => p >= NEVER_RING_BELOW);

/** Learned rhythm, overridden by calendar blocks (a meeting means "won't pick up"). */
export function familyPickup(inputs: FamilyInputs, now: Date): PickupAt {
  return withCalendar(withSleep(meanPickup(buildPeople(inputs, now), now), inputs.members), inputs.blocks);
}

export function levelsFor(pickupAt: PickupAt, memberId: string, from: Date): Level[] {
  return Array.from({ length: FORECAST_SLOTS }, (_, i) =>
    levelOf(pickupAt(memberId, new Date(from.getTime() + i * SLOT_MS + SLOT_MS / 2))));
}

export function familyState(inputs: FamilyInputs, now: Date, isDemo: boolean): FamilyState {
  const ids = inputs.members.map((m) => m.id);
  const from = floorToSlot(now);
  const searchFrom = new Date(from.getTime() + SLOT_MS);   // never suggest the slot already under way
  const people = buildPeople(inputs, now);
  const mean = withSleep(meanPickup(people, now), inputs.members);   // calendarPick/suggestMoves apply blocks themselves
  const pickupAt = withCalendar(mean, inputs.blocks);
  const ledger = ledgerOf(inputs.members);
  const tzOf = (id: string) => inputs.members.find((m) => m.id === id)?.tz ?? 'UTC';

  const suggestion = ids.length < 2 ? null : (() => {
    const soon = calendarPick(ids, mean, inputs.blocks, ledger, searchFrom, SEARCH_HOURS);
    const best = worksForAll(soon) ? soon : calendarPick(ids, mean, inputs.blocks, ledger, searchFrom, WIDE_SEARCH_HOURS);
    const pickup = Object.fromEntries(Object.entries(best.pickup).map(([k, v]) => [k, round2(v)]));
    return {
      start: iso(best.start), end: iso(callEnd(best.start)), pickup,
      levels: Object.fromEntries(Object.entries(best.pickup).map(([k, v]) => [k, levelOf(v)])),
      everyoneLikely: Object.values(best.pickup).every((p) => levelOf(p) === 'G'),
    };
  })();

  const moves = ids.length < 2 ? [] : suggestMoves(ids, tzOf, mean, inputs.blocks, ledger, searchFrom, SEARCH_HOURS)
    .map((s) => ({ blockId: s.blockId, memberId: s.memberId, from: iso(s.from), to: iso(s.to), frees: iso(s.frees), gain: round2(s.gain) }));

  const bookings = inputs.bookings
    .filter((b) => b.status !== 'completed' && b.start.getTime() + b.durationMin * 60_000 > now.getTime())
    .sort((a, b) => a.start.getTime() - b.start.getTime())
    .map((b) => ({ id: b.id, start: iso(b.start), end: iso(new Date(b.start.getTime() + b.durationMin * 60_000)),
                   acceptedBy: [...b.acceptedBy], status: b.status }));

  return {
    now: iso(now), forecastStart: iso(from), slotMinutes: SLOT_MS / 60_000, isDemo,
    members: inputs.members.map((m, i) => {
      const learner = people[i].learner;
      return {
        id: m.id, name: m.name, city: m.city, tz: m.tz, simulated: m.simulated,
        phone: m.contact?.phone ?? null, apps: m.contact?.apps ?? {},
        levels: levelsFor(pickupAt, m.id, from),
        week: weekOf(learner, now), said: learner.prelim.join(''),
        insights: findInsights(m.id, m.name, learner, now).slice(0, 3).map((x) => x.text),
        signals: inputs.observations.filter((o) => o.memberId === m.id && o.at.getTime() > now.getTime() - RECENT_MS
          && o.at.getTime() <= now.getTime()).length,
      };
    }),
    suggestion, moves, bookings, lastChange: latestChange(inputs, people, now),
  };
}

function round2(x: number): number { return Math.round(x * 100) / 100; }
