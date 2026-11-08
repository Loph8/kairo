import { describe, expect, it } from 'vitest'
import { ANCHOR, CALENDAR_BLOCKS, MEMBERS, OTHERS, YOU, bestTime, countOf, lane, localDay, pickupAt } from './demo'
import { initialState, reducer } from './demoState'
import { dayLabel, formatRange, formatTime, localParts } from './time'

const norm = (s: string) => s.replace(/\s/g, ' ')
const none = { checkIn: null } as const

describe('time zones', () => {
  it('shows one instant in four zones, including a half-hour offset', () => {
    expect(MEMBERS.map((m) => norm(formatTime(ANCHOR, m.timeZone, 'en-US')))).toEqual(['7:30 PM', '1:30 AM', '7:00 AM', '9:30 AM'])
  })
  it('uses IANA zones, so the offsets are not hardcoded', () => {
    expect(localParts(ANCHOR, 'America/Chicago').minutes).toBe(19 * 60 + 30)
    expect(localParts(new Date('2026-07-14T01:30:00Z'), 'America/Chicago').minutes).toBe(20 * 60 + 30) // daylight time
  })
  it('judges Today/Tomorrow in each person’s own zone', () => {
    const b = bestTime(MEMBERS, none)!
    expect(dayLabel(b.start, ANCHOR, YOU.timeZone, 'en-US')).toBe('Tomorrow')
    expect(dayLabel(b.start, ANCHOR, 'Europe/Lisbon', 'en-US')).toBe('Today')
  })
})

describe('best time', () => {
  it('is deterministic and keeps everyone out of "Unlikely" for the whole call', () => {
    const b = bestTime(MEMBERS, none)!
    expect(b.start.toISOString()).toBe('2026-11-14T13:00:00.000Z')
    expect(norm(formatRange(b.start, b.end, YOU.timeZone, 'en-US'))).toBe('7:00 – 7:45 AM')
    for (const m of MEMBERS) {
      expect(pickupAt(m, b.start, none)).not.toBe('R')
      expect(pickupAt(m, new Date(b.end.getTime() - 60_000), none)).not.toBe('R')
    }
  })
  it('returns null (the empty state) when nobody can be reached', () => {
    const allAsleep = { ...OTHERS[0], wake: 0, bed: 0 } // quiet around the clock
    expect(bestTime([YOU, allAsleep], none)).toBeNull()
  })
  it('respects Alex’s calendar block', () => {
    const block = CALENDAR_BLOCKS[0]
    expect(pickupAt(YOU, new Date(block.start.getTime() + 60_000), none)).toBe('R')
    expect(lane(YOU, none).filter((c) => c === 'R').length).toBeGreaterThan(3)
  })
  it('a check-in changes only the current half-hour', () => {
    const base = lane(YOU, none)
    const busy = lane(YOU, { checkIn: 'busy' })
    const free = lane(YOU, { checkIn: 'free' })
    expect(busy[0]).toBe('R')
    expect(free[0]).toBe('G')
    expect(busy.slice(1)).toEqual(base.slice(1))
  })
  it('the dial covers one local day of 48 cells', () => {
    const { cells, nowSlot } = localDay(OTHERS[1], none) // Grandma, Mumbai, 7:00 AM
    expect(cells).toHaveLength(48)
    expect(nowSlot).toBe(14)
    expect(countOf(cells, 'G') + countOf(cells, 'Y') + countOf(cells, 'R')).toBe(48)
  })
})

describe('demo reducer', () => {
  it('switches tabs and keeps the check-in across them', () => {
    let s = reducer(initialState(), { type: 'checkIn', value: 'busy' })
    s = reducer(s, { type: 'tab', tab: 'insights' })
    s = reducer(s, { type: 'tab', tab: 'settings' })
    expect(s.tab).toBe('settings')
    expect(s.checkIn).toBe('busy')
  })
  it('toggles a check-in off when chosen twice', () => {
    let s = reducer(initialState(), { type: 'checkIn', value: 'free' })
    s = reducer(s, { type: 'checkIn', value: 'free' })
    expect(s.checkIn).toBeNull()
  })
  it('sync runs idle -> syncing -> done and ignores repeats', () => {
    let s = reducer(initialState(), { type: 'syncStart' })
    expect(s.sync).toBe('syncing')
    expect(reducer(s, { type: 'syncStart' })).toBe(s)
    s = reducer(s, { type: 'syncDone' })
    expect(s.sync).toBe('done')
    expect(reducer(s, { type: 'syncDone' })).toBe(s)
  })
  it('call preview records only a local follow-up answer', () => {
    let s = reducer(initialState(), { type: 'openCall' })
    s = reducer(s, { type: 'callOutcome', value: 'no' })
    expect(s.callOutcome).toBe('no')
    s = reducer(s, { type: 'callTarget', id: 'sam' })
    expect(s.callOutcome).toBeNull()
  })
})
