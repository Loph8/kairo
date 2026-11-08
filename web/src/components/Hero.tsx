import { ANCHOR, DEMO_FAMILY_NAME, OTHERS, YOU, bestTime, MEMBERS } from '../lib/demo'
import { dayLabel, formatRange } from '../lib/time'
import { primaryCta, REPO_URL } from '../lib/site'
import { BestTimeCard } from './BestTimeCard'
import { CheckIn } from './CheckIn'
import { ArrowIcon, GitHubIcon } from './Icons'
import { MemberRow } from './MemberRow'

const ctx = { checkIn: null } as const

export function Hero() {
  const cta = primaryCta()
  const rel = cta.external ? { rel: 'noopener' } : {}
  const suggestion = bestTime(MEMBERS, ctx)!
  return (
    <section className="hero" aria-labelledby="hero-title">
      <div className="container hero__grid">
        <div className="hero__copy">
          <p className="tag rise">Kairo is in development · iPhone</p>
          <h1 id="hero-title" className="hero__title rise rise-2">Different schedules. A little time together.</h1>
          <p className="lede rise rise-3">
            Kairo brings your family’s availability into view, so you can find a better moment to call across busy
            schedules and different time zones.
          </p>
          <div className="hero__actions rise rise-3">
            <a className="btn btn-primary" href={cta.href} {...rel}>{cta.label} <ArrowIcon /></a>
            <a className="btn btn-glass" href={REPO_URL} rel="noopener"><GitHubIcon /> View on GitHub</a>
          </div>
        </div>

        <figure className="hero__visual rise rise-2">
          <div className="hero-phone" aria-hidden>
            <h2 className="screen__title">{DEMO_FAMILY_NAME}</h2>
            <BestTimeCard status="ready" suggestion={suggestion} />
            <ul className="member-list">
              {OTHERS.slice(0, 2).map((m) => <li key={m.id}><MemberRow member={m} ctx={ctx} /></li>)}
            </ul>
            <CheckIn value="free" />
          </div>
          <figcaption>
            Demo with a made-up family. Suggested call: {dayLabel(suggestion.start, ANCHOR, YOU.timeZone)},{' '}
            {formatRange(suggestion.start, suggestion.end, YOU.timeZone)} in {YOU.city}. An estimate, not a guarantee.
          </figcaption>
        </figure>
      </div>
    </section>
  )
}
