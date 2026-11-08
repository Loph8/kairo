import { useEffect, useRef } from 'react'
import { OTHERS, memberById } from '../lib/demo'
import type { DemoState } from '../lib/demoState'
import { formatTime } from '../lib/time'
import { ANCHOR } from '../lib/demo'
import { PhoneIcon } from './Icons'

interface Props {
  state: DemoState
  onClose: () => void
  onTarget: (id: string) => void
  onOutcome: (v: 'yes' | 'no') => void
}

/** A simulated call sheet. Nothing is dialed, opened or sent. */
export function CallSheet({ state, onClose, onTarget, onOutcome }: Props) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => {
    const d = ref.current
    if (!d) return
    if (state.callOpen && !d.open) d.showModal()
    if (!state.callOpen && d.open) d.close()
  }, [state.callOpen])

  const target = memberById(state.callTargetId)
  return (
    <dialog ref={ref} className="sheet" aria-labelledby="sheet-title" onClose={onClose} onClick={(e) => e.target === ref.current && onClose()}>
      <div className="sheet__body">
        <span className="tag tag--demo">Call preview · nothing is dialed</span>
        <h3 id="sheet-title" className="sheet__title"><PhoneIcon /> Call {target.name}?</h3>

        <fieldset className="sheet__who">
          <legend className="sr-only">Who would you call?</legend>
          {OTHERS.map((m) => (
            <label key={m.id} className="chip chip--radio">
              <input type="radio" name="call-target" checked={m.id === state.callTargetId} onChange={() => onTarget(m.id)} />
              <span>{m.name} · {formatTime(ANCHOR, m.timeZone)}</span>
            </label>
          ))}
        </fieldset>

        <p className="soft">
          In the app, Call opens the calling app you chose for that person, such as FaceTime, Phone or a chat app. Kairo
          only opens it. It doesn’t read it.
        </p>
        <p className="sheet__q">Afterwards, Kairo asks: <strong>Did {target.name} pick up?</strong></p>
        <div className="sheet__btns">
          <button type="button" className="btn btn-glass btn-sm" aria-pressed={state.callOutcome === 'yes'} onClick={() => onOutcome('yes')}>Yes, we talked</button>
          <button type="button" className="btn btn-glass btn-sm" aria-pressed={state.callOutcome === 'no'} onClick={() => onOutcome('no')}>No answer</button>
        </div>
        <p className="soft small" role="status">
          {state.callOutcome ? 'Thanks. In the app, an answer like this helps Kairo learn. In this demo nothing is saved.' : 'Try an answer to see what the follow-up looks like.'}
        </p>
        <button type="button" className="btn btn-primary" onClick={onClose}>Close preview</button>
      </div>
    </dialog>
  )
}
