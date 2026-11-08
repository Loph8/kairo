import { CALENDAR_BLOCK_COUNT } from '../lib/demo'
import type { SyncStatus } from '../lib/demoState'
import { CalendarIcon, CheckCircleIcon, SyncIcon } from './Icons'

interface Props {
  sync: SyncStatus
  onSync: () => void
}

export function CalendarCard({ sync, onSync }: Props) {
  return (
    <section className="glass calendar" aria-labelledby="cal-title">
      <h3 id="cal-title" className="card-title"><CalendarIcon /> Calendars</h3>
      <p className="calendar__status">
        <CheckCircleIcon />
        <span>Connected · {CALENDAR_BLOCK_COUNT} busy blocks in the last 4 weeks and next 4 days <span className="soft">(sample)</span></span>
      </p>
      <p className="soft small">Reading: iCloud, Google (sample accounts)</p>
      <p className="soft">
        Kairo learns your weekly rhythm from the last 4 weeks and avoids meetings in the next 4 days. Only busy times are
        shared, never titles or attendees.
      </p>
      <p className="soft small" role="status">
        {sync === 'syncing' && 'Refreshing the demo calendar…'}
        {sync === 'done' && 'Demo calendar refreshed. No real calendar was read.'}
        {sync === 'idle' && 'Last synced 2 min ago (sample)'}
      </p>
      <button type="button" className="btn btn-glass" onClick={onSync} disabled={sync === 'syncing'}>
        <SyncIcon /> {sync === 'syncing' ? 'Syncing…' : 'Sync now'}
      </button>
    </section>
  )
}
