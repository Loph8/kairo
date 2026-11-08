import { DEMO_EMAIL, DEMO_FAMILY_NAME, DEMO_INVITE_CODE, MEMBERS, YOU } from '../lib/demo'
import type { CopyStatus, SyncStatus } from '../lib/demoState'
import { CalendarCard } from './CalendarCard'
import { CopyIcon } from './Icons'
import { MemberAvatar } from './MemberAvatar'

interface Props {
  sync: SyncStatus
  copy: CopyStatus
  notice: string | null
  onSync: () => void
  onCopy: () => void
  onNotice: (t: string) => void
}

export function SettingsScreen({ sync, copy, notice, onSync, onCopy, onNotice }: Props) {
  return (
    <div className="screen">
      <h2 className="screen__title">Settings</h2>

      <section className="glass profile" aria-labelledby="profile-title">
        <div className="profile__who">
          <MemberAvatar member={YOU} size={56} />
          <div>
            <h3 id="profile-title" className="card-title">Alex Rivera</h3>
            <p className="soft">{DEMO_EMAIL}</p>
          </div>
        </div>
        <dl className="profile__rows">
          <div><dt>Family</dt><dd>{DEMO_FAMILY_NAME}</dd></div>
          <div>
            <dt>Invite code</dt>
            <dd>
              <span className="mono">{DEMO_INVITE_CODE}</span>
              <button type="button" className="icon-btn" onClick={onCopy} aria-label="Copy sample invite code"><CopyIcon /></button>
            </dd>
          </div>
          <div><dt>Members</dt><dd>{MEMBERS.length}</dd></div>
        </dl>
        <p className="soft small" role="status">{copy === 'copied' ? 'Sample code copied. It isn’t a real invite.' : copy === 'failed' ? 'Couldn’t copy here. It’s only a sample code.' : 'Demo profile with a sample code.'}</p>
        <div className="profile__btns">
          <button type="button" className="btn btn-glass" onClick={() => onNotice('Leave family isn’t available in the demo.')}>Leave family</button>
          <button type="button" className="btn btn-glass" onClick={() => onNotice('There’s no account to sign out of in the demo.')}>Sign out</button>
        </div>
        <p className="soft small" role="status">{notice}</p>
      </section>

      <CalendarCard sync={sync} onSync={onSync} />

      <p className="soft small privacy-foot">
        <strong>We use times, not content.</strong> The app stores when calls happen, whether someone picked up, and busy times, never message text, call audio or event titles.
      </p>
    </div>
  )
}
