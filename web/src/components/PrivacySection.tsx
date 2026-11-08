import { CalendarIcon, LockIcon } from './Icons'

const COLUMNS = [
  {
    title: 'What your iPhone reads',
    body: 'Only if you allow it, Kairo asks iOS for Calendar access and reads events from the calendars on your iPhone, such as iCloud or Google accounts you’ve added there. The app copies only start and end times and a few flags from each event.',
  },
  {
    title: 'What leaves your phone',
    body: 'For each busy block: its start and end, an anonymous ID, and whether the event could be moved (meetings with other people can’t). All-day events, events marked “free” and events you declined are left out. Titles, places, notes and attendee names aren’t copied.',
  },
  {
    title: 'What it’s used for',
    body: 'Busy times help Kairo avoid your meetings in the next four days and learn your weekly rhythm from the last four weeks. Your family sees estimates of when you’re likely free, not why.',
  },
]

export function PrivacySection() {
  return (
    <section id="privacy" className="section privacy" aria-labelledby="privacy-title">
      <div className="container">
        <p className="eyebrow">Privacy</p>
        <h2 id="privacy-title" className="h2 section__title">Your schedule matters. The details stay yours.</h2>
        <p className="lede"><LockIcon /> Kairo uses times, not content. It doesn’t store message text, call audio or contacts.</p>
        <div className="privacy__grid">
          {COLUMNS.map((c) => (
            <div key={c.title} className="glass privacy__item">
              <h3 className="card-title">{c.title}</h3>
              <p className="soft">{c.body}</p>
            </div>
          ))}
        </div>
        <div className="glass privacy__control">
          <h3 className="card-title"><CalendarIcon /> You’re in control</h3>
          <ul className="privacy__list soft">
            <li>Calendar access is optional. Without it, Kairo works from check-ins and calls.</li>
            <li>You can turn it off any time in iPhone Settings → Kairo → Calendars.</li>
            <li>“Clear history” in Settings removes your calls and calendar blocks from Kairo.</li>
          </ul>
        </div>
        <p className="soft small privacy__note">
          Not “never accessed”: when you grant calendar access, iOS lets an app read full event details on the phone.
          Kairo’s code only copies the fields above, and that’s what is sent to its server.
        </p>
      </div>
    </section>
  )
}
