import type { CheckIn as Value } from '../lib/demo'
import { PauseCircleIcon, SunIcon } from './Icons'

interface Props {
  value: Value
  onChange?: (v: Exclude<Value, null>) => void
}

export function CheckIn({ value, onChange }: Props) {
  const msg =
    value === 'free'
      ? 'Noted for this demo: you’re free right now.'
      : value === 'busy'
        ? 'Noted for this demo: you’re busy right now.'
        : 'Tap one to tell Kairo how right now is.'
  return (
    <section className="glass checkin" aria-labelledby="checkin-title">
      <h3 id="checkin-title" className="card-title">How’s right now?</h3>
      <div className="checkin__btns">
        <button type="button" className="btn btn-glass" aria-pressed={value === 'free'} disabled={!onChange} onClick={() => onChange?.('free')}>
          <SunIcon /> I’m free
        </button>
        <button type="button" className="btn btn-glass" aria-pressed={value === 'busy'} disabled={!onChange} onClick={() => onChange?.('busy')}>
          <PauseCircleIcon /> I’m busy
        </button>
      </div>
      <p className="checkin__msg soft" role="status">{msg}</p>
    </section>
  )
}
