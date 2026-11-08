import { DEMO_FAMILY_NAME, MEMBERS, OTHERS, type Context, type Suggestion } from '../lib/demo'
import type { CopyStatus } from '../lib/demoState'
import type { CheckIn as Value } from '../lib/demo'
import { BestTimeCard, type SuggestionStatus } from './BestTimeCard'
import { CheckIn } from './CheckIn'
import { InviteCard } from './InviteCard'
import { MemberRow } from './MemberRow'

interface Props {
  ctx: Context
  status: SuggestionStatus
  suggestion: Suggestion | null
  checkIn: Value
  copy: CopyStatus
  onCall: () => void
  onCheckIn: (v: Exclude<Value, null>) => void
  onCopy: (ok: boolean) => void
}

export function FamilyScreen({ ctx, status, suggestion, checkIn, copy, onCall, onCheckIn, onCopy }: Props) {
  return (
    <div className="screen">
      <h2 className="screen__title">{DEMO_FAMILY_NAME}</h2>
      <BestTimeCard status={status} suggestion={suggestion} onCall={onCall} />
      <ul className="member-list" aria-label={`${MEMBERS.length} family members`}>
        {OTHERS.map((m) => (
          <li key={m.id}><MemberRow member={m} ctx={ctx} /></li>
        ))}
      </ul>
      <InviteCard status={copy} onCopy={onCopy} />
      <CheckIn value={checkIn} onChange={onCheckIn} />
    </div>
  )
}
