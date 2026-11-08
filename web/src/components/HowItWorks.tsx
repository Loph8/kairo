import { DEMO_INVITE_CODE } from '../lib/demo'
import { CalendarIcon, PhoneIcon, SunIcon, PauseCircleIcon } from './Icons'

const STEPS = [
  {
    title: 'Bring your family in',
    body: 'Start a family and share its code. Each person downloads Kairo, signs in with their email, and taps Join.',
    visual: (
      <div className="glass how-visual" aria-hidden>
        <span className="soft small">Invite code</span>
        <span className="invite__code">{DEMO_INVITE_CODE}</span>
      </div>
    ),
  },
  {
    title: 'Add a little context',
    body: 'Tap “I’m free” or “I’m busy” when you want to say how right now is. Optionally let Kairo read busy times from your iPhone’s calendars.',
    visual: (
      <div className="glass how-visual how-visual--row" aria-hidden>
        <span className="btn btn-glass btn-sm"><SunIcon /> I’m free</span>
        <span className="btn btn-glass btn-sm"><PauseCircleIcon /> I’m busy</span>
        <span className="how-chip"><CalendarIcon /> Busy times</span>
      </div>
    ),
  },
  {
    title: 'Find a better moment',
    body: 'Kairo suggests a time that looks good across everyone’s time zones. Tap Call, and Kairo opens the calling app you chose.',
    visual: (
      <div className="glass how-visual" aria-hidden>
        <span className="soft small">Best time to call</span>
        <span className="how-time">Tomorrow, 7:00 AM</span>
        <span className="btn btn-primary btn-sm call-btn"><PhoneIcon /> Call</span>
      </div>
    ),
  },
]

export function HowItWorks() {
  return (
    <section id="how-it-works" className="section" aria-labelledby="how-title">
      <div className="container">
        <p className="eyebrow">How it works</p>
        <h2 id="how-title" className="h2 section__title">Three small steps to a better time to call</h2>
        <ol className="steps">
          {STEPS.map((s, i) => (
            <li className="step" key={s.title}>
              <span className="step__n" aria-hidden>{i + 1}</span>
              <h3 className="step__title">{s.title}</h3>
              <p className="soft">{s.body}</p>
              {s.visual}
            </li>
          ))}
        </ol>
      </div>
    </section>
  )
}
