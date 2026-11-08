import { primaryCta, REPO_URL, waitlistEnabled } from '../lib/site'
import { Waitlist } from './Waitlist'
import { ArrowIcon, GitHubIcon } from './Icons'
import { Logo } from './Logo'

export function FinalCTA() {
  const cta = primaryCta()
  const rel = cta.external ? { rel: 'noopener' } : {}
  const waitlist = waitlistEnabled()
  return (
    <section id="waitlist" className="final" aria-labelledby="final-title">
      <div className="container final__inner">
        <Logo size={64} />
        <h2 id="final-title" className="h2">A better moment to catch up.</h2>
        <p className="lede">Try the demo and see how Kairo suggests a time that works on both sides of the clock.</p>
        {waitlist && <Waitlist />}
        <div className="hero__actions">
          {!waitlist && <a className="btn btn-primary" href={cta.href} {...rel}>{cta.label} <ArrowIcon /></a>}
          {waitlist && <a className="btn btn-glass" href="#demo">Try the demo <ArrowIcon /></a>}
          <a className="btn btn-glass" href={REPO_URL} rel="noopener"><GitHubIcon /> Follow along on GitHub</a>
        </div>
      </div>
    </section>
  )
}
