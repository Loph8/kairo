import { ANCHOR, CALENDAR_BLOCKS, MEMBERS, PICKUP_LABEL, SLOTS, YOU, countOf, lane, type Context, type Suggestion } from '../lib/demo'
import { dayLabel, formatRange, formatTime } from '../lib/time'
import { MemberAvatar } from './MemberAvatar'

interface Props {
  ctx: Context
  suggestion: Suggestion | null
}

/** Everyone's next 24 hours in half-hour cells, with the suggested window outlined. */
export function InsightsTimeline({ ctx, suggestion }: Props) {
  const lanes = MEMBERS.map((m) => ({ m, cells: lane(m, ctx) }))
  const summary = lanes
    .map(({ m, cells }) => `${m.name}: likely free about ${countOf(cells, 'G') / 2} hours, maybe free about ${countOf(cells, 'Y') / 2} hours.`)
    .join(' ')
  const pick = suggestion
    ? `Suggested ${dayLabel(suggestion.start, ANCHOR, YOU.timeZone)} ${formatRange(suggestion.start, suggestion.end, YOU.timeZone)} in ${YOU.city}.`
    : 'No window works for everyone in the next 24 hours.'

  return (
    <div className="timeline">
      <div className="timeline__body" role="img" aria-label={`Everyone's next 24 hours in half-hour steps, starting at ${formatTime(ANCHOR, YOU.timeZone)} in ${YOU.city}. ${pick} ${summary}`}>
        <div className="timeline__avatars">
          {lanes.map(({ m }) => <MemberAvatar key={m.id} member={m} size={24} />)}
        </div>
        <div className="timeline__lanes">
          {lanes.map(({ m, cells }) => (
            <div className="lane" key={m.id}>
              {cells.map((c, i) => <i key={i} className={`cell cell--${c}`} />)}
            </div>
          ))}
          {suggestion && (
            <span className="timeline__best" style={{ left: `${(suggestion.slot / SLOTS) * 100}%`, width: `${(2 / SLOTS) * 100}%` }} />
          )}
        </div>
      </div>
      <div className="timeline__axis" aria-hidden>
        <span>Now</span>
        <span>+12h</span>
        <span>+24h</span>
      </div>
      <ul className="legend" aria-label="Legend">
        {(['G', 'Y', 'R'] as const).map((l) => (
          <li key={l}><i className={`swatch cell--${l}`} /> {PICKUP_LABEL[l]}</li>
        ))}
        <li><i className="swatch swatch--pick" /> Suggested</li>
      </ul>
      <p className="timeline__note soft">
        Times are in your zone ({YOU.city}). Your sample calendar has {CALENDAR_BLOCKS.length} busy {CALENDAR_BLOCKS.length === 1 ? 'block' : 'blocks'} in this window, which is avoided.
      </p>
    </div>
  )
}
