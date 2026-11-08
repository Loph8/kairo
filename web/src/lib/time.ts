/** Locale-aware, IANA-zone time helpers. Every display derives from one Date (a shared instant). */

export interface LocalParts {
  /** 0 = Sunday … 6 = Saturday */
  weekday: number
  minutes: number
  year: number
  month: number
  day: number
}

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

export function localParts(d: Date, timeZone: string): LocalParts {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hourCycle: 'h23',
    weekday: 'short',
    year: 'numeric',
    month: 'numeric',
    day: 'numeric',
    hour: 'numeric',
    minute: 'numeric',
  }).formatToParts(d)
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? ''
  return {
    weekday: WEEKDAYS.indexOf(get('weekday')),
    minutes: Number(get('hour')) * 60 + Number(get('minute')),
    year: Number(get('year')),
    month: Number(get('month')),
    day: Number(get('day')),
  }
}

export function isWeekend(weekday: number): boolean {
  return weekday === 0 || weekday === 6
}

export function formatTime(d: Date, timeZone: string, locale?: string): string {
  return new Intl.DateTimeFormat(locale, { hour: 'numeric', minute: '2-digit', timeZone }).format(d)
}

export function formatRange(start: Date, end: Date, timeZone: string, locale?: string): string {
  return new Intl.DateTimeFormat(locale, { hour: 'numeric', minute: '2-digit', timeZone }).formatRange(start, end)
}

/** Whole calendar days between `d` and `reference`, judged on the wall clock of `timeZone`. */
export function dayOffset(d: Date, reference: Date, timeZone: string): number {
  const a = localParts(d, timeZone)
  const b = localParts(reference, timeZone)
  return Math.round((Date.UTC(a.year, a.month - 1, a.day) - Date.UTC(b.year, b.month - 1, b.day)) / 86_400_000)
}

/** "Today", "Tomorrow", "Yesterday" or a short weekday: the day as seen in `timeZone`. */
export function dayLabel(d: Date, reference: Date, timeZone: string, locale?: string): string {
  switch (dayOffset(d, reference, timeZone)) {
    case 0:
      return 'Today'
    case 1:
      return 'Tomorrow'
    case -1:
      return 'Yesterday'
    default:
      return new Intl.DateTimeFormat(locale, { weekday: 'short', timeZone }).format(d)
  }
}

export function formatDate(d: Date, timeZone: string, locale?: string): string {
  return new Intl.DateTimeFormat(locale, { weekday: 'short', month: 'short', day: 'numeric', timeZone }).format(d)
}
