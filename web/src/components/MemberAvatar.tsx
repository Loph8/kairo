import { initial, type Member } from '../lib/demo'

/** A member's own color, like a small glowing planet (MemberPalette in the app). */
export function MemberAvatar({ member, size = 44 }: { member: Member; size?: number }) {
  return (
    <span
      className="avatar"
      aria-hidden
      style={{ width: size, height: size, fontSize: size * 0.42, background: member.color, boxShadow: `0 0 ${size * 0.3}px ${member.color}66` }}
    >
      {initial(member.name)}
    </span>
  )
}
