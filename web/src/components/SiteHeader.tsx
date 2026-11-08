import { useEffect, useRef, useState } from 'react'
import { primaryCta } from '../lib/site'
import { MenuIcon } from './Icons'
import { Wordmark } from './Logo'

const LINKS = [
  { href: '#how-it-works', label: 'How it works' },
  { href: '#features', label: 'Features' },
  { href: '#privacy', label: 'Privacy' },
]

export function SiteHeader() {
  const [open, setOpen] = useState(false)
  const btn = useRef<HTMLButtonElement>(null)
  const cta = primaryCta()
  const rel = cta.external ? { rel: 'noopener' } : {}

  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setOpen(false)
        btn.current?.focus()
      }
    }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [open])

  return (
    <header className="site-header">
      <div className="container site-header__bar">
        <a href="#top" className="site-header__brand" aria-label="Kairo, back to top">
          <Wordmark />
        </a>
        <nav aria-label="Main" className="site-nav">
          <ul id="site-menu" className="site-nav__list" data-open={open}>
            {LINKS.map((l) => (
              <li key={l.href}>
                <a href={l.href} onClick={() => setOpen(false)}>{l.label}</a>
              </li>
            ))}
            <li className="site-nav__cta-mobile">
              <a className="btn btn-primary" href={cta.href} onClick={() => setOpen(false)} {...rel}>{cta.label}</a>
            </li>
          </ul>
        </nav>
        <a className="btn btn-primary btn-sm site-header__cta" href={cta.href} {...rel}>{cta.label}</a>
        <button ref={btn} type="button" className="menu-btn" aria-expanded={open} aria-controls="site-menu" onClick={() => setOpen((o) => !o)}>
          <span className="sr-only">{open ? 'Close menu' : 'Open menu'}</span>
          <MenuIcon open={open} />
        </button>
      </div>
    </header>
  )
}
