import { REPO_URL } from '../lib/site'

const ITEMS = [
  {
    q: 'How does Kairo suggest a time to call?',
    a: 'It estimates when each person is likely to pick up, for every half-hour, from their own preferences, past calls and check-ins, and calendar busy times. Then it looks for a 45-minute window across everyone’s time zones where nobody is likely to miss it. It’s a learning scheduler, not a chat model, and a suggestion is an estimate, not a promise that someone will answer.',
  },
  {
    q: 'How do I invite my family?',
    a: 'Start a family in the app and share its invite code. Each person downloads Kairo, signs in with their email (the app sends a one-time code), and taps Join.',
  },
  {
    q: 'What do “I’m free” and “I’m busy” do?',
    a: 'They’re quick check-ins about right now. The app counts them as a signal it learns from, so over time its estimates follow your real routine.',
  },
  {
    q: 'What calendar information is shared?',
    a: 'Only busy times: start, end, an anonymous ID and a “can it move” flag. Event titles, places, notes and attendee names aren’t copied from your phone. Calendar access is optional and uses your iPhone’s calendar accounts.',
  },
  {
    q: 'How does Kairo handle different time zones?',
    a: 'Every person keeps their own time zone, and every suggestion is one exact moment shown on each person’s clock, with the right day. A call that’s tomorrow morning for you may be this evening for someone else.',
  },
  {
    q: 'Is Kairo available to download?',
    a: 'Not yet. There’s no App Store or TestFlight link, so the demo on this page is the best way to see it. You can follow the project on GitHub.',
    link: true,
  },
]

export function FAQ() {
  return (
    <section id="faq" className="section" aria-labelledby="faq-title">
      <div className="container faq">
        <div>
          <p className="eyebrow">Questions</p>
          <h2 id="faq-title" className="h2">Good to know</h2>
        </div>
        <div className="faq__list">
          {ITEMS.map((i) => (
            <details key={i.q} className="faq__item" name="faq">
              <summary>{i.q}</summary>
              <p className="soft">
                {i.a}
                {i.link && <> <a href={REPO_URL} rel="noopener">github.com/Loph8/kairo</a></>}
              </p>
            </details>
          ))}
        </div>
      </div>
    </section>
  )
}
