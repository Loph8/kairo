import { AppPreview } from './AppPreview'

export function DemoSection() {
  return (
    <section id="demo" className="section demo" aria-labelledby="demo-title">
      <div className="container demo__grid">
        <div className="stack demo__copy">
          <p className="eyebrow">Interactive demo</p>
          <h2 id="demo-title" className="h2">Try Kairo’s three screens</h2>
          <p className="lede">A made-up family, a fixed moment in time, and sample data. Nothing is saved, sent or dialed.</p>
          <ul className="demo__tips">
            <li><strong>Family.</strong> See a suggested time, copy the sample invite code, and tap “I’m free” or “I’m busy”.</li>
            <li><strong>Insights.</strong> See everyone’s next 24 hours and the highlighted window. Pick a person to see their day.</li>
            <li><strong>Settings.</strong> Look at the calendar card and press “Sync now”. It only refreshes demo data.</li>
          </ul>
          <p className="soft small">
            The demo uses a small stand-in for the scheduling idea. It doesn’t run the app’s own scheduler, and every
            suggestion is an estimate.
          </p>
        </div>
        <AppPreview />
      </div>
    </section>
  )
}
