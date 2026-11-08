import { PICKUP_LABEL, pickupAt, type Context, type Member } from '../lib/demo'
import { ANCHOR } from '../lib/demo'
import { dayLabel, formatTime } from '../lib/time'
import { MemberAvatar } from './MemberAvatar'
import { PickupBadge } from './PickupBadge'

export function MemberRow({ member, ctx }: { member: Member; ctx: Context }) {
  const level = pickupAt(member, ANCHOR, ctx)
  const time = formatTime(ANCHOR, member.timeZone)
  return (
    <div className="glass member" role="group" aria-label={`${member.name}, ${time} in ${member.city}, ${PICKUP_LABEL[level]}`}>
      <MemberAvatar member={member} />
      <span className="member__who">
        <span className="member__name">{member.name}</span>
        <span className="member__sub">{dayLabel(ANCHOR, ANCHOR, member.timeZone)} · {member.city}</span>
      </span>
      <span className="member__right">
        <span className="time">{time}</span>
        <PickupBadge level={level} />
      </span>
    </div>
  )
}
