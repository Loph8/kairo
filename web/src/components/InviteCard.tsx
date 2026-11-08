import { DEMO_INVITE_CODE } from '../lib/demo'
import type { CopyStatus } from '../lib/demoState'
import { CopyIcon, PeopleIcon } from './Icons'

interface Props {
  status: CopyStatus
  onCopy: (ok: boolean) => void
}

export function InviteCard({ status, onCopy }: Props) {
  const copy = async () => {
    let ok = false
    try {
      await navigator.clipboard.writeText(DEMO_INVITE_CODE)
      ok = true
    } catch {
      ok = false
    }
    onCopy(ok)
  }

  return (
    <section className="glass invite" aria-labelledby="invite-title">
      <h3 id="invite-title" className="card-title"><PeopleIcon /> Bring your family in</h3>
      <p className="soft">Share this code. They download Kairo, sign in, and tap Join.</p>
      <div className="invite__row">
        <span className="invite__code" aria-label={`Sample invite code ${DEMO_INVITE_CODE.split('').join(' ')}`}>{DEMO_INVITE_CODE}</span>
        <button type="button" className="btn btn-glass btn-sm" onClick={copy}>
          <CopyIcon /> Copy code
        </button>
      </div>
      <p className="invite__note soft" role="status">
        {status === 'copied' && 'Sample code copied. It isn’t a real invite.'}
        {status === 'failed' && 'Couldn’t copy here. It’s only a sample code anyway.'}
        {status === 'idle' && 'Sample code for this demo. It doesn’t invite anyone.'}
      </p>
    </section>
  )
}
