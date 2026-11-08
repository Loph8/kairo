/**
 * Deterministic, synthetic demo data for the website preview. Nothing here is real.
 *
 * The app's model has three pick-up levels per half-hour (Likely free / Maybe / Unlikely, "G/Y/R" in the
 * server code) and a 45-minute call. This file mirrors that vocabulary with a tiny hand-set scorer so the
 * demo is consistent across tabs. It is NOT the app's learning engine (Beta priors + calendar constraints).
 */
import { isWeekend, localParts } from './time'

/** Fri 13 Nov 2026, 7:30 PM in Chicago (CST) = 1:30 AM Sat in Lisbon = 7:00 AM Sat in Mumbai = 9:30 AM Sat in Singapore. */
export const ANCHOR = new Date('2026-11-14T01:30:00Z')
export const SLOT_MS = 30 * 60_000
export const SLOTS = 48
export const CALL_MINUTES = 45

export type Pickup = 'G' | 'Y' | 'R'
export const PICKUP_LABEL: Record<Pickup, string> = { G: 'Likely free', Y: 'Maybe', R: 'Unlikely' }

export const DEMO_FAMILY_NAME = 'The Rivera family'
export const DEMO_INVITE_CODE = 'SAMPLE'
export const DEMO_EMAIL = 'alex@example.com'

interface Rule {
  /** true = weekends only, false = weekdays only, null = any day */
  weekend: boolean | null
  /** local minutes of the day */
  from: number
  to: number
}

export interface Member {
  id: string
  name: string
  city: string
  timeZone: string
  /** a soft, per-person tint, like the app's member colors */
  color: string
  wake: number
  bed: number
  busy: Rule[]
  likely: Rule[]
}

const h = (hours: number, mins = 0) => hours * 60 + mins

export const YOU: Member = {
  id: 'you',
  name: 'Alex',
  city: 'Chicago',
  timeZone: 'America/Chicago',
  color: '#F5E6A3',
  wake: h(7),
  bed: h(23),
  busy: [{ weekend: false, from: h(9), to: h(17) }],
  likely: [{ weekend: null, from: h(18), to: h(22) }, { weekend: true, from: h(10), to: h(18) }],
}

export const OTHERS: Member[] = [
  {
    id: 'mom', name: 'Mom', city: 'Lisbon', timeZone: 'Europe/Lisbon', color: '#C8BADD',
    wake: h(7), bed: h(22, 30), busy: [],
    likely: [{ weekend: null, from: h(9), to: h(12) }, { weekend: null, from: h(15), to: h(19) }],
  },
  {
    id: 'grandma', name: 'Grandma', city: 'Mumbai', timeZone: 'Asia/Kolkata', color: '#E89AAE',
    wake: h(5, 30), bed: h(21, 30), busy: [],
    likely: [{ weekend: null, from: h(7), to: h(11) }, { weekend: null, from: h(16), to: h(19) }],
  },
  {
    id: 'sam', name: 'Sam', city: 'Singapore', timeZone: 'Asia/Singapore', color: '#A9CBE8',
    wake: h(8), bed: h(23, 30), busy: [{ weekend: false, from: h(9), to: h(18) }],
    likely: [{ weekend: false, from: h(19), to: h(22) }, { weekend: true, from: h(10), to: h(22) }],
  },
]

export const MEMBERS: Member[] = [YOU, ...OTHERS]

export function memberById(id: string): Member {
  const m = MEMBERS.find((x) => x.id === id)
  if (!m) throw new Error(`Unknown demo member: ${id}`)
  return m
}

export const initial = (name: string) => name.trim().slice(0, 1).toUpperCase() || '?'

/** Alex's synthetic calendar: busy blocks that the demo "Calendars" card says were read. */
export interface BusyBlock { start: Date; end: Date }
export const CALENDAR_BLOCKS: BusyBlock[] = [
  // Sat 9:00-10:30 AM in Chicago: a weekend commitment that pushes the suggestion later.
  { start: new Date('2026-11-14T15:00:00Z'), end: new Date('2026-11-14T16:30:00Z') },
]
export const CALENDAR_BLOCK_COUNT = 42 // sample number shown in Settings (4 weeks back + 4 days ahead)

export type CheckIn = 'free' | 'busy' | null

export interface Context {
  checkIn: CheckIn
}

const inRule = (rules: Rule[], weekday: number, minutes: number) =>
  rules.some((r) => (r.weekend === null || r.weekend === isWeekend(weekday)) && minutes >= r.from && minutes < r.to)

/** Pick-up estimate for one member at one instant. Always an estimate, never "asleep". */
export function pickupAt(m: Member, at: Date, ctx: Context = { checkIn: null }): Pickup {
  if (m.id === YOU.id) {
    // A check-in right now is a strong label for the current half-hour only.
    if (ctx.checkIn && at.getTime() >= ANCHOR.getTime() && at.getTime() < ANCHOR.getTime() + SLOT_MS) {
      return ctx.checkIn === 'free' ? 'G' : 'R'
    }
    if (CALENDAR_BLOCKS.some((b) => at >= b.start && at < b.end)) return 'R'
  }
  const { weekday, minutes } = localParts(at, m.timeZone)
  if (minutes < m.wake || minutes >= m.bed) return 'R'
  if (inRule(m.busy, weekday, minutes)) return 'R'
  return inRule(m.likely, weekday, minutes) ? 'G' : 'Y'
}

export const slotStart = (i: number) => new Date(ANCHOR.getTime() + i * SLOT_MS)

/** 48 half-hour levels for the next 24 hours, starting now. */
export function lane(m: Member, ctx: Context): Pickup[] {
  return Array.from({ length: SLOTS }, (_, i) => pickupAt(m, slotStart(i), ctx))
}

export interface Suggestion {
  slot: number
  start: Date
  end: Date
}

const POINTS: Record<Pickup, number> = { G: 2, Y: 1, R: -100 }

/**
 * Best start slot in the next 24 hours: nobody "Unlikely" for the whole call, most "Likely free" overall,
 * earliest on ties. Returns null when no such window exists (the empty state).
 */
export function bestTime(members: Member[], ctx: Context): Suggestion | null {
  const lanes = members.map((m) => lane(m, ctx))
  const span = Math.ceil(CALL_MINUTES / 30)
  let best: { slot: number; score: number } | null = null
  for (let i = 0; i + span <= SLOTS; i++) {
    let score = 0
    for (const l of lanes) for (let k = 0; k < span; k++) score += POINTS[l[i + k]]
    if (score < 0) continue
    if (!best || score > best.score) best = { slot: i, score }
  }
  if (!best) return null
  const start = slotStart(best.slot)
  return { slot: best.slot, start, end: new Date(start.getTime() + CALL_MINUTES * 60_000) }
}

/** Cells of one member's own local calendar day (midnight at the top of the dial) around the anchor. */
export function localDay(m: Member, ctx: Context): { cells: Pickup[]; nowSlot: number } {
  const { minutes } = localParts(ANCHOR, m.timeZone)
  const midnight = ANCHOR.getTime() - minutes * 60_000
  const cells = Array.from({ length: SLOTS }, (_, i) => pickupAt(m, new Date(midnight + i * SLOT_MS + 60_000), ctx))
  return { cells, nowSlot: Math.floor(minutes / 30) }
}

export const countOf = (cells: Pickup[], level: Pickup) => cells.filter((c) => c === level).length
