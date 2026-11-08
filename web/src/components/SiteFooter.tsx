import { REPO_URL } from '../lib/site'
import { Wordmark } from './Logo'

export function SiteFooter() {
  return (
    <footer className="site-footer">
      <div className="container site-footer__inner">
        <div className="stack">
          <Wordmark />
          <p className="soft site-footer__desc">Helps families find a good time to call across busy schedules and time zones. An iPhone app in development.</p>
        </div>
        <nav aria-label="Footer">
          <ul className="site-footer__links">
            <li><a href="#how-it-works">How it works</a></li>
            <li><a href="#privacy">Privacy</a></li>
            <li><a href="#faq">FAQ</a></li>
            <li><a href={REPO_URL} rel="noopener">GitHub</a></li>
          </ul>
        </nav>
      </div>
      <div className="container"><p className="site-footer__copy soft">© {new Date().getFullYear()} Kairo. The family on this page is made up.</p></div>
    </footer>
  )
}
