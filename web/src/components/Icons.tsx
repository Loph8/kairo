import type { Pickup } from '../lib/demo'

const base = { viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 1.9, strokeLinecap: 'round', strokeLinejoin: 'round', 'aria-hidden': true, focusable: false } as const

/** Line icons in the spirit of the app's SF Symbols. */
export const SunHorizonIcon = () => (<svg {...base}><path d="M7 17a5 5 0 0 1 10 0M12 5v2.5M4.5 9.5 6.3 11.3M19.5 9.5l-1.8 1.8M2.5 17H4.5M19.5 17h2M3.5 20.5h17" /></svg>)
export const PhoneIcon = () => (<svg {...base}><path d="M5 4h3.5l1.8 4.5-2.2 1.4a11 11 0 0 0 5 5l1.4-2.2L19 14.5V18a2 2 0 0 1-2 2A14 14 0 0 1 3 6a2 2 0 0 1 2-2z" fill="currentColor" stroke="none" /></svg>)
export const SunIcon = () => (<svg {...base}><circle cx="12" cy="12" r="4" fill="currentColor" stroke="none" /><path d="M12 2.5v2.2M12 19.3v2.2M2.5 12h2.2M19.3 12h2.2M5.3 5.3l1.6 1.6M17.1 17.1l1.6 1.6M5.3 18.7l1.6-1.6M17.1 6.9l1.6-1.6" /></svg>)
export const PauseCircleIcon = () => (<svg {...base}><circle cx="12" cy="12" r="9.5" fill="currentColor" stroke="none" /><path d="M10 8.8v6.4M14 8.8v6.4" stroke="var(--night)" strokeWidth="2.2" /></svg>)
export const SparklesIcon = () => (<svg {...base}><path d="M10 4l1.6 4.4L16 10l-4.4 1.6L10 16l-1.6-4.4L4 10l4.4-1.6zM18 14l.8 2.2L21 17l-2.2.8L18 20l-.8-2.2L15 17l2.2-.8z" fill="currentColor" stroke="none" /></svg>)
export const CheckCircleIcon = () => (<svg {...base}><circle cx="12" cy="12" r="9.5" fill="currentColor" stroke="none" /><path d="m8 12.4 2.8 2.8L16.2 9.6" stroke="var(--night)" strokeWidth="2.2" /></svg>)
export const StarCircleIcon = () => (<svg {...base}><circle cx="12" cy="12" r="9.5" fill="currentColor" stroke="none" /><path d="m12 7.2 1.5 3.1 3.4.5-2.5 2.4.6 3.4-3-1.6-3 1.6.6-3.4-2.5-2.4 3.4-.5z" fill="var(--night)" stroke="none" /></svg>)
export const CopyIcon = () => (<svg {...base}><rect x="8.5" y="8.5" width="11" height="11" rx="3" /><path d="M15.5 8.5V7a2.5 2.5 0 0 0-2.5-2.5H7A2.5 2.5 0 0 0 4.5 7v6A2.5 2.5 0 0 0 7 15.5h1.5" /></svg>)
export const PeopleIcon = () => (<svg {...base}><circle cx="9" cy="8.5" r="3.2" fill="currentColor" stroke="none" /><path d="M2.8 19a6.2 6.2 0 0 1 12.4 0z" fill="currentColor" stroke="none" /><circle cx="17" cy="9.5" r="2.5" fill="currentColor" stroke="none" opacity=".7" /><path d="M16.5 14.2a5 5 0 0 1 4.7 4.8h-4" fill="currentColor" stroke="none" opacity=".7" /></svg>)
export const CalendarIcon = () => (<svg {...base}><rect x="3.5" y="5" width="17" height="15" rx="3.5" /><path d="M3.5 10h17M8 3v4M16 3v4" /></svg>)
export const SyncIcon = () => (<svg {...base}><path d="M19.5 12a7.5 7.5 0 0 0-13-5L4.5 9M4.5 12a7.5 7.5 0 0 0 13 5l2-2M4.5 4.5V9H9M19.5 19.5V15H15" /></svg>)
export const GearIcon = () => (<svg {...base}><circle cx="12" cy="12" r="3" /><path d="M12 2.8l1.3 2.2 2.5-.6.8 2.4 2.4.8-.6 2.5 2.2 1.3-2.2 1.3.6 2.5-2.4.8-.8 2.4-2.5-.6L12 21.2l-1.3-2.2-2.5.6-.8-2.4-2.4-.8.6-2.5L3.4 12.6l2.2-1.3-.6-2.5 2.4-.8.8-2.4 2.5.6z" /></svg>)
export const PulseIcon = () => (<svg {...base}><path d="M2.5 12.5h4l2-6 3.5 12 3-9 1.5 3h5" /></svg>)
export const LockIcon = () => (<svg {...base}><rect x="5" y="10.5" width="14" height="10" rx="3" fill="currentColor" stroke="none" /><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5" /></svg>)
export const ArrowIcon = () => (<svg {...base}><path d="M5 12h14M13 6l6 6-6 6" /></svg>)
export const MenuIcon = ({ open }: { open: boolean }) => (<svg {...base}>{open ? <path d="M6 6l12 12M18 6 6 18" /> : <path d="M4 8h16M4 16h16" />}</svg>)
export const GitHubIcon = () => (<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden focusable="false"><path d="M12 .5a11.5 11.5 0 0 0-3.64 22.41c.58.1.79-.25.79-.56v-2c-3.2.7-3.88-1.37-3.88-1.37-.52-1.33-1.28-1.69-1.28-1.69-1.05-.71.08-.7.08-.7 1.15.08 1.76 1.19 1.76 1.19 1.03 1.76 2.7 1.25 3.36.96.1-.75.4-1.25.73-1.54-2.55-.29-5.24-1.28-5.24-5.69 0-1.26.45-2.28 1.18-3.09-.12-.29-.51-1.46.11-3.05 0 0 .97-.31 3.17 1.18a11 11 0 0 1 5.77 0c2.2-1.49 3.17-1.18 3.17-1.18.63 1.59.23 2.76.11 3.05.74.81 1.18 1.83 1.18 3.09 0 4.42-2.69 5.39-5.25 5.68.41.36.78 1.06.78 2.14v3.17c0 .31.21.67.8.56A11.5 11.5 0 0 0 12 .5z" /></svg>)

/** Three pick-up levels with a symbol AND a word (never color alone), like the app. */
export function PickupIcon({ level }: { level: Pickup }) {
  if (level === 'G') return <CheckCircleIcon />
  if (level === 'Y') return (<svg {...base}><circle cx="12" cy="12" r="9.5" fill="currentColor" stroke="none" /><path d="M9.6 9.6a2.5 2.5 0 1 1 3.6 2.2c-.8.4-1.2.9-1.2 1.8M12 16.6v.1" stroke="var(--night)" strokeWidth="2.2" /></svg>)
  return (<svg {...base}><path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z" fill="currentColor" stroke="none" /></svg>)
}
