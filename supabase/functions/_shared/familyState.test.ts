// The AI has to make sense to a person: never sleep hours, learns from everyone, remembers past meetings.
import { describe, expect, test } from 'bun:test';
import { familyState, type FamilyInputs, type MemberRow, type StoredObservation } from './familyState.ts';
import { localParts } from './time.ts';

const NOW = new Date('2026-11-08T10:10:00Z');   // Sun 5:10 AM in Durham, 7:10 PM in Seoul
const DURHAM = 'America/New_York', SEOUL = 'Asia/Seoul';

const member = (id: string, tz: string): MemberRow => ({
  id, name: id, city: '', tz, userId: id, burdenMin: 0, simulated: false, persona: null,
  onboarding: { wake: '07:00', bed: '23:00', busy: [['09:00', '17:00']] },
});
const family = (observations: StoredObservation[] = [], tzB = SEOUL): FamilyInputs =>
  ({ members: [member('me', DURHAM), member('mom', tzB)], observations, blocks: [], bookings: [] });
const answered = (memberId: string, iso: string): StoredObservation =>
  ({ memberId, at: new Date(iso), outcome: { kind: 'call', answered: true }, source: 'channel' });
const localHour = (iso: string, tz: string) => localParts(tz, new Date(iso)).hour;
const awake = (h: number) => h >= 7 && h < 23;

describe('family suggestion', () => {
  test('lands inside everyone\'s waking hours', () => {
    const s = familyState(family(), NOW, false).suggestion!;
    expect(awake(localHour(s.start, DURHAM))).toBe(true);
    expect(awake(localHour(s.start, SEOUL))).toBe(true);
  });

  test('answered 2 AM test calls never make 2 AM the suggestion', () => {
    // Two phones in the same room, tested all night for three nights: every call answered between 1 and 4 AM.
    const nights = ['2026-11-06', '2026-11-07', '2026-11-08'];
    const obs = nights.flatMap((d) => ['06', '06', '07', '07', '08', '08'].flatMap((h, i) =>
      ['me', 'mom'].map((id) => answered(id, `${d}T${h}:${i % 2 ? '45' : '15'}:00Z`))));
    const s = familyState(family(obs, DURHAM), NOW, false).suggestion!;
    expect(awake(localHour(s.start, DURHAM))).toBe(true);
    const me = familyState(family(obs, DURHAM), NOW, false).members[0];
    const twoAm = me.levels.findIndex((_, i) => localHour(new Date(NOW.getTime() - (NOW.getTime() % 1_800_000) + i * 1_800_000 + 900_000).toISOString(), DURHAM) === 2);
    expect(me.levels[twoAm]).toBe('R');
  });

  test('looks further ahead instead of ringing someone in their sleep', () => {
    const late: MemberRow = { ...member('mom', SEOUL), onboarding: { wake: '11:00', bed: '13:00', busy: [] } };
    const s = familyState({ ...family(), members: [member('me', DURHAM), late] }, NOW, false).suggestion!;
    expect(localHour(s.start, SEOUL)).toBeGreaterThanOrEqual(11);
    expect(localHour(s.start, SEOUL)).toBeLessThan(13);
  });
});
