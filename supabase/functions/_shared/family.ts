// The demo family: what each person typed in onboarding, and (for seeding/sim only) how they really behave.
import type { Onboarding } from './learning.ts';

export interface Member {
  readonly id: string;
  readonly name: string;
  readonly tz: string;
  readonly city: string;
  readonly onboarding: Onboarding;
}

export const FAMILY: readonly Member[] = [
  { id: 'you', name: 'You', tz: 'America/New_York', city: 'Durham',
    onboarding: { wake: '07:00', bed: '24:00', busy: [['09:30', '17:00']] } },
  { id: 'mom', name: 'Mom', tz: 'Asia/Seoul', city: 'Seoul',
    onboarding: { wake: '07:00', bed: '23:30', busy: [['10:30', '19:00']] } },
  { id: 'grandpa', name: 'Grandpa', tz: 'Asia/Seoul', city: 'Seoul',
    onboarding: { wake: '04:30', bed: '22:30', busy: [['11:00', '14:00']] } },
  { id: 'dad', name: 'Dad', tz: 'Africa/Addis_Ababa', city: 'Addis Ababa',
    onboarding: { wake: '06:00', bed: '23:00', busy: [['08:00', '14:30']] } },
];

/** Demo "now": Mon Nov 9, 8:12 PM in Durham. */
export const DEMO_ANCHOR = new Date('2026-11-10T01:12:00Z');

/** Minutes of inconvenient-hour calls each person has already absorbed. */
export const DEMO_LEDGER: Readonly<Record<string, number>> = { you: 0, mom: 45, grandpa: 45, dad: 120 };

type Band = readonly [from: string, to: string, level: 'G' | 'Y' | 'R'];

/** Real weekday behavior (local time). Weekends: busy blocks turn into "maybe". Never shown to the learner. */
export const TRUTH_BANDS: Readonly<Record<string, readonly Band[]>> = {
  you: [['00:00', '07:00', 'R'], ['07:00', '07:30', 'Y'], ['07:30', '09:30', 'G'], ['09:30', '17:00', 'R'],
    ['17:00', '18:00', 'Y'], ['18:00', '23:00', 'G'], ['23:00', '24:00', 'Y']],
  mom: [['00:00', '07:00', 'R'], ['07:00', '08:00', 'Y'], ['08:00', '10:30', 'G'], ['10:30', '19:00', 'R'],
    ['19:00', '19:30', 'Y'], ['19:30', '22:30', 'G'], ['22:30', '23:30', 'Y'], ['23:30', '24:00', 'R']],
  grandpa: [['00:00', '04:30', 'R'], ['04:30', '05:00', 'Y'], ['05:00', '09:00', 'G'], ['09:00', '11:00', 'Y'],
    ['11:00', '14:00', 'R'], ['14:00', '15:00', 'Y'], ['15:00', '22:00', 'G'], ['22:00', '22:30', 'Y'], ['22:30', '24:00', 'R']],
  dad: [['00:00', '06:00', 'R'], ['06:00', '08:00', 'G'], ['08:00', '08:30', 'Y'], ['08:30', '14:30', 'R'],
    ['14:30', '15:00', 'Y'], ['15:00', '22:00', 'G'], ['22:00', '23:00', 'Y'], ['23:00', '24:00', 'R']],
};
