import { ANCHOR, OTHERS, YOU, type Suggestion } from '../lib/demo'
import { dayLabel, formatRange, formatTime } from '../lib/time'
import { PhoneIcon, SunHorizonIcon } from './Icons'

export type SuggestionStatus = 'loading' | 'ready' | 'empty'

interface Props {
  status: SuggestionStatus
  suggestion: Suggestion | null
  /** Omit for the decorative (hero) version. */
  onCall?: () => void
}

export function BestTimeCard({ status, suggestion, onCall }: Props) {
  return (
    <section className="glass best" aria-labelledby="best-title" aria-busy={status === 'loading'}>
      <h3 id="best-title" className="best__label">
        <SunHorizonIcon /> Best time to call
      </h3>

      {status === 'loading' && <p className="best__time" role="status">Finding the best time…</p>}

      {status === 'empty' && (
        <>
          <p className="best__time">No good time in the next 24 hours</p>
          <p className="soft">Someone is likely unavailable for the whole call. Kairo will look again as plans and check-ins change.</p>
        </>
      )}

      {status === 'ready' && suggestion && (
        <>
          <p className="best__time">
            {dayLabel(suggestion.start, ANCHOR, YOU.timeZone)}, {formatRange(suggestion.start, suggestion.end, YOU.timeZone)}
          </p>
          <p className="best__sub">Your time in {YOU.city}. A suggestion based on estimates.</p>
          <ul className="best__zones" aria-label="The same moment for everyone else">
            {OTHERS.map((m) => (
              <li key={m.id}>
                <span>{m.name}</span>
                <span>
                  {dayLabel(suggestion.start, ANCHOR, m.timeZone)} {formatTime(suggestion.start, m.timeZone)} · {m.city}
                </span>
              </li>
            ))}
          </ul>
        </>
      )}

      {onCall ? (
        <button type="button" className="btn btn-primary call-btn" disabled={status !== 'ready'} onClick={onCall}>
          <PhoneIcon /> Call
        </button>
      ) : (
        <span className="btn btn-primary call-btn" aria-hidden>
          <PhoneIcon /> Call
        </span>
      )}
    </section>
  )
}
