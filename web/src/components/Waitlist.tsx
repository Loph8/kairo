import { useState, type FormEvent } from 'react'

type Status = 'idle' | 'sending' | 'done' | 'error'

/** Posts to this site's own /api/waitlist. Only rendered when the Node server provides it. */
export function Waitlist() {
  const [status, setStatus] = useState<Status>('idle')
  const [message, setMessage] = useState('')

  const submit = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    const form = e.currentTarget
    const data = new FormData(form)
    setStatus('sending')
    setMessage('')
    try {
      const res = await fetch('/api/waitlist', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: data.get('email'), website: data.get('website') }),
      })
      const out = (await res.json()) as { ok: boolean; error?: string }
      if (res.ok && out.ok) {
        setStatus('done')
        setMessage('Thanks. You’re on the list.')
        form.reset()
      } else {
        setStatus('error')
        setMessage(out.error ?? 'Something went wrong. Please try again.')
      }
    } catch {
      setStatus('error')
      setMessage('Couldn’t reach the server. Please try again.')
    }
  }

  return (
    <form className="glass waitlist" onSubmit={submit} noValidate aria-labelledby="waitlist-title">
      <h3 id="waitlist-title" className="card-title">Join the waitlist</h3>
      <p className="soft">Kairo isn’t available to download yet. Leave your email and you’ll be on the list for when it is.</p>
      <div className="waitlist__row">
        <label className="sr-only" htmlFor="waitlist-email">Email address</label>
        <input id="waitlist-email" name="email" type="email" autoComplete="email" required placeholder="you@example.com" className="input"
          aria-invalid={status === 'error'} aria-describedby="waitlist-msg" />
        {/* honeypot: real people never see or fill this */}
        <input name="website" tabIndex={-1} autoComplete="off" aria-hidden className="hp" />
        <button type="submit" className="btn btn-primary" disabled={status === 'sending'}>
          {status === 'sending' ? 'Sending…' : 'Join'}
        </button>
      </div>
      <p id="waitlist-msg" role="status" className={`waitlist__msg ${status === 'error' ? 'waitlist__msg--err' : ''}`}>{message}</p>
      <p className="soft small">We store only your email address and the time you signed up, on this site’s server, to tell you when Kairo is available. Nothing is tracked.</p>
    </form>
  )
}
