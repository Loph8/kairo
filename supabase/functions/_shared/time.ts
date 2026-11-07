// Time-zone math with Intl only (works in Deno edge functions and Bun).
export type DayKind = 'weekday' | 'weekend';
export const SLOTS_PER_DAY = 48;
export const SLOT_MS = 30 * 60 * 1000;
export const DAY_MS = 24 * 60 * 60 * 1000;

export interface LocalParts {
  year: number; month: number; day: number; hour: number; minute: number; weekday: number; // 0 = Sunday
}

const WEEKDAYS: Record<string, number> = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
const formatters = new Map<string, Intl.DateTimeFormat>();

function formatterFor(tz: string): Intl.DateTimeFormat {
  const cached = formatters.get(tz);
  if (cached) return cached;
  const f = new Intl.DateTimeFormat('en-US', {
    timeZone: tz, hourCycle: 'h23', year: 'numeric', month: 'numeric', day: 'numeric',
    hour: 'numeric', minute: 'numeric', weekday: 'short',
  });
  formatters.set(tz, f);
  return f;
}

export function localParts(tz: string, at: Date): LocalParts {
  const parts = Object.fromEntries(formatterFor(tz).formatToParts(at).map((p) => [p.type, p.value]));
  return {
    year: +parts.year, month: +parts.month, day: +parts.day,
    hour: +parts.hour % 24, minute: +parts.minute, weekday: WEEKDAYS[parts.weekday],
  };
}

export function dayKindOf(weekday: number): DayKind {
  return weekday === 0 || weekday === 6 ? 'weekend' : 'weekday';
}

/** Index of the learner cell (dayKind x 30-min slot) that `at` falls in for someone in `tz`. */
export function cellIndex(tz: string, at: Date): number {
  const p = localParts(tz, at);
  const slot = Math.floor((p.hour * 60 + p.minute) / 30);
  return (dayKindOf(p.weekday) === 'weekend' ? SLOTS_PER_DAY : 0) + slot;
}

/** UTC instant of a wall-clock time in `tz` (minute precision, DST-safe for non-gap times). */
export function localToUtc(tz: string, y: number, mo: number, d: number, h: number, mi: number): Date {
  const wall = Date.UTC(y, mo - 1, d, h, mi);
  let guess = wall;
  for (let i = 0; i < 3; i++) {
    const p = localParts(tz, new Date(guess));
    const seen = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute);
    guess += wall - seen;
  }
  return new Date(guess);
}

export function toMinutes(hhmm: string): number {
  const m = /^(\d{1,2}):(\d{2})$/.exec(hhmm);
  if (!m) throw new Error(`Expected HH:MM, got "${hhmm}"`);
  const minutes = +m[1] * 60 + +m[2];
  if (minutes > 1440 || +m[2] >= 60) throw new Error(`Time out of range: "${hhmm}"`);
  return minutes;
}

export function fmtLocal(tz: string, at: Date): string {
  const p = localParts(tz, at);
  const day = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][p.weekday];
  const h12 = p.hour % 12 || 12;
  return `${day} ${h12}:${String(p.minute).padStart(2, '0')} ${p.hour < 12 ? 'AM' : 'PM'}`;
}

export function fmtSlot(slot: number): string {
  const minutes = slot * 30;
  const h = Math.floor(minutes / 60) % 24;
  const m = minutes % 60;
  return `${h % 12 || 12}:${String(m).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
}
