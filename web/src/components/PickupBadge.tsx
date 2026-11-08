import { PICKUP_LABEL, type Pickup } from '../lib/demo'
import { PickupIcon } from './Icons'

export function PickupBadge({ level }: { level: Pickup }) {
  return (
    <span className={`pickup pickup--${level}`}>
      <PickupIcon level={level} />
      {PICKUP_LABEL[level]}
    </span>
  )
}
