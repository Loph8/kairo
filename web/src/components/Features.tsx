import { useMemo, useState, type ReactNode } from 'react'
import { MEMBERS, OTHERS, bestTime, type CheckIn as Value } from '../lib/demo'
import type { SyncStatus } from '../lib/demoState'
import { AvailabilityClock } from './AvailabilityClock'
import { CalendarCard } from './CalendarCard'
import { CheckIn } from './CheckIn'
import { InsightsTimeline } from './InsightsTimeline'
import { InviteCard } from './InviteCard'
import { MemberRow } from './MemberRow'
import { useEffect } from 'react'

const ctx = { checkIn: null } as const

interface FeatureProps {
  id: string
  eyebrow: string
  title: string
  children: ReactNode
  visual: ReactNode
  flip?: boolean
}

function FeatureSection({ id, eyebrow, title, children, visual, flip }: FeatureProps) {
  return (
    <article className={`feature ${flip ? 'feature--flip' : ''}`} aria-labelledby={id}>
      <div className="feature__copy stack">
        <p className="eyebrow">{eyebrow}</p>
        <h3 id={id} className="feature__title">{title}</h3>
        {children}
      </div>
      <div className="feature__visual">{visual}</div>
    </article>
  )
}

function InviteVisual() {
  const [copy, setCopy] = useState<'idle' | 'copied' | 'failed'>('idle')
  return (
    <div className="stack">
      <InviteCard status={copy} onCopy={(ok) => setCopy(ok ? 'copied' : 'failed')} />
      <ul className="member-list">
        {OTHERS.slice(0, 2).map((m) => <li key={m.id}><MemberRow member={m} ctx={ctx} /></li>)}
      </ul>
    </div>
  )
}

function CheckInVisual() {
  const [v, setV] = useState<Value>(null)
  return <CheckIn value={v} onChange={(n) => setV((p) => (p === n ? null : n))} />
}

function CalendarVisual() {
  const [sync, setSync] = useState<SyncStatus>('idle')
  useEffect(() => {
    if (sync !== 'syncing') return
    const t = window.setTimeout(() => setSync('done'), 900)
    return () => window.clearTimeout(t)
  }, [sync])
  return <CalendarCard sync={sync} onSync={() => setSync('syncing')} />
}

function WhyVisual() {
  const suggestion = useMemo(() => bestTime(MEMBERS, ctx), [])
  return (
    <div className="stack">
      <div className="glass insight-card"><InsightsTimeline ctx={ctx} suggestion={suggestion} /></div>
      <div className="glass dial-card">
        <h4 className="dial-card__title">When {OTHERS[1].name} picks up</h4>
        <p className="soft">{OTHERS[1].city} time · an estimate</p>
        <AvailabilityClock member={OTHERS[1]} ctx={ctx} suggestion={suggestion} />
      </div>
    </div>
  )
}

export function Features() {
  return (
    <section id="features" className="section features" aria-labelledby="features-title">
      <div className="container">
        <p className="eyebrow">Features</p>
        <h2 id="features-title" className="h2 section__title">Made for families on different clocks</h2>

        <FeatureSection id="f-family" eyebrow="Family" title="Your family, in one place" visual={<InviteVisual />}>
          <p className="lede">
            Start a family, share a short code, and everyone joins from their own phone. You see each person’s local time
            and a quick estimate of whether they’re likely free.
          </p>
        </FeatureSection>

        <FeatureSection id="f-checkin" eyebrow="Check-ins" title="A quick way to say how right now is" flip visual={<CheckInVisual />}>
          <p className="lede">
            Two buttons: “I’m free” and “I’m busy”. They take a second, and the app counts them as one of the signals it
            learns from. The selected state is always clear, and you can tap again to undo it here in the demo.
          </p>
        </FeatureSection>

        <FeatureSection id="f-calendar" eyebrow="Calendars" title="Suggestions that consider your schedule" visual={<CalendarVisual />}>
          <p className="lede">
            If you allow it, Kairo reads busy times from the calendars on your iPhone. It learns your weekly rhythm from
            the last four weeks and steers clear of your meetings over the next four days. “Sync now” refreshes it on
            demand.
          </p>
        </FeatureSection>

        <FeatureSection id="f-why" eyebrow="Insights" title="See why a time was suggested" flip visual={<WhyVisual />}>
          <p className="lede">
            The Insights tab lays out everyone’s next 24 hours in half-hour steps and highlights the suggested window. A
            24-hour dial shows when each person tends to pick up, in their own time zone.
          </p>
        </FeatureSection>
      </div>
    </section>
  )
}
