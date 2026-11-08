import { ANCHOR, MEMBERS, YOU, memberById, type Context, type Suggestion } from '../lib/demo'
import { dayLabel, formatRange } from '../lib/time'
import { AvailabilityClock } from './AvailabilityClock'
import { CheckCircleIcon, SparklesIcon, StarCircleIcon } from './Icons'
import { InsightsTimeline } from './InsightsTimeline'
import { MemberAvatar } from './MemberAvatar'

interface Props {
  ctx: Context
  finding: boolean
  suggestion: Suggestion | null
  memberId: string
  onMember: (id: string) => void
}

export function InsightsScreen({ ctx, finding, suggestion, memberId, onMember }: Props) {
  const member = memberById(memberId)
  const zones = new Set(MEMBERS.map((m) => m.timeZone)).size
  const steps = [
    `Aligned ${zones} time zones`,
    'Checked busy windows and calendar blocks',
    `Compared 48 half-hour slots for ${MEMBERS.length} people`,
    suggestion ? `Highlighted ${dayLabel(suggestion.start, ANCHOR, YOU.timeZone)} ${formatRange(suggestion.start, suggestion.end, YOU.timeZone)}` : 'No window works for everyone yet',
  ]
  return (
    <div className="screen">
      <h2 className="screen__title">Insights</h2>

      <section className="glass insight-card" aria-labelledby="insight-title" aria-busy={finding}>
        <div className="insight-card__head">
          <span className="insight-card__icon"><SparklesIcon /></span>
          <div>
            <h3 id="insight-title" className="card-title">Kairo insights</h3>
            <p className="soft">Finding the hour everyone can pick up</p>
          </div>
          <span className={`status ${finding ? '' : 'status--done'}`} role="status">
            {finding ? 'Finding…' : suggestion ? 'Suggested' : 'No window'}
          </span>
        </div>
        <InsightsTimeline ctx={ctx} suggestion={suggestion} />
        {!finding && (
          <>
            <ul className="steps-list">
              {steps.map((s, i) => (
                <li key={s} style={{ animationDelay: `${i * 120}ms` }} className={i === steps.length - 1 && suggestion ? 'steps-list__last' : ''}>
                  {i === steps.length - 1 && suggestion ? <StarCircleIcon /> : <CheckCircleIcon />} {s}
                </li>
              ))}
            </ul>
            <p className="soft small">Illustrative steps from sample data. This page doesn’t run the app’s scheduler.</p>
          </>
        )}
      </section>

      <div className="chips" role="group" aria-label="Choose a family member">
        {MEMBERS.map((m) => (
          <button key={m.id} type="button" className="chip" aria-pressed={m.id === memberId} onClick={() => onMember(m.id)}>
            <MemberAvatar member={m} size={26} /> {m.id === YOU.id ? 'You' : m.name}
          </button>
        ))}
      </div>

      <section className="glass dial-card" aria-labelledby="dial-title">
        <h3 id="dial-title" className="dial-card__title">{member.id === YOU.id ? 'When you pick up' : `When ${member.name} picks up`}</h3>
        <p className="soft">{member.city} time · an estimate</p>
        <AvailabilityClock member={member} ctx={ctx} suggestion={suggestion} />
      </section>
    </div>
  )
}
