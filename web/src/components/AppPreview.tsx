import { useEffect, useMemo, useReducer, useRef, useState, type KeyboardEvent } from 'react'
import { MEMBERS, bestTime } from '../lib/demo'
import { initialState, reducer, type Tab } from '../lib/demoState'
import { CallSheet } from './CallSheet'
import { FamilyScreen } from './FamilyScreen'
import { GearIcon, PulseIcon, SunHorizonIcon } from './Icons'
import { InsightsScreen } from './InsightsScreen'
import { SettingsScreen } from './SettingsScreen'

const TABS: { id: Tab; label: string; icon: JSX.Element }[] = [
  { id: 'family', label: 'Family', icon: <SunHorizonIcon /> },
  { id: 'insights', label: 'Insights', icon: <PulseIcon /> },
  { id: 'settings', label: 'Settings', icon: <GearIcon /> },
]

const reduceMotion = () => typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches

async function copyCode(code: string) {
  try {
    await navigator.clipboard.writeText(code)
    return true
  } catch {
    return false
  }
}

export function AppPreview() {
  const [s, dispatch] = useReducer(reducer, undefined, initialState)
  const [finding, setFinding] = useState(true)
  const tabRefs = useRef<Record<Tab, HTMLButtonElement | null>>({ family: null, insights: null, settings: null })

  const ctx = useMemo(() => ({ checkIn: s.checkIn }), [s.checkIn])
  const suggestion = useMemo(() => bestTime(MEMBERS, ctx), [ctx])

  // A short, honest "finding" state whenever the inputs change; instant with reduced motion.
  useEffect(() => {
    setFinding(true)
    const t = window.setTimeout(() => setFinding(false), reduceMotion() ? 0 : 700)
    return () => window.clearTimeout(t)
  }, [ctx])

  // "Sync now": a short simulated refresh. No calendar is read.
  useEffect(() => {
    if (s.sync !== 'syncing') return
    const t = window.setTimeout(() => dispatch({ type: 'syncDone' }), reduceMotion() ? 0 : 900)
    return () => window.clearTimeout(t)
  }, [s.sync])

  const status = finding ? 'loading' : suggestion ? 'ready' : 'empty'

  const onKey = (e: KeyboardEvent) => {
    const i = TABS.findIndex((t) => t.id === s.tab)
    let n = i
    if (e.key === 'ArrowRight') n = (i + 1) % TABS.length
    else if (e.key === 'ArrowLeft') n = (i + TABS.length - 1) % TABS.length
    else if (e.key === 'Home') n = 0
    else if (e.key === 'End') n = TABS.length - 1
    else return
    e.preventDefault()
    dispatch({ type: 'tab', tab: TABS[n].id })
    tabRefs.current[TABS[n].id]?.focus()
  }

  const copy = async () => dispatch({ type: 'copy', ok: await copyCode('SAMPLE') })

  return (
    <div className="app-shell">
      <p className="app-shell__badge"><span className="tag tag--demo">Interactive demo</span> <span className="soft small">Sample family. Nothing is saved or sent.</span></p>
      <div className="app">
        <div className="app__screen">
          {TABS.map((t) => (
            <div key={t.id} id={`panel-${t.id}`} role="tabpanel" aria-labelledby={`tab-${t.id}`} hidden={s.tab !== t.id} tabIndex={0} className="app__panel">
              {t.id === 'family' && s.tab === 'family' && (
                <FamilyScreen
                  ctx={ctx} status={status} suggestion={suggestion} checkIn={s.checkIn} copy={s.copy}
                  onCall={() => dispatch({ type: 'openCall' })}
                  onCheckIn={(v) => dispatch({ type: 'checkIn', value: v })}
                  onCopy={(ok) => dispatch({ type: 'copy', ok })}
                />
              )}
              {t.id === 'insights' && s.tab === 'insights' && (
                <InsightsScreen ctx={ctx} finding={finding} suggestion={suggestion} memberId={s.insightsMemberId} onMember={(id) => dispatch({ type: 'insightsMember', id })} />
              )}
              {t.id === 'settings' && s.tab === 'settings' && (
                <SettingsScreen
                  sync={s.sync} copy={s.copy} notice={s.notice}
                  onSync={() => dispatch({ type: 'syncStart' })} onCopy={copy}
                  onNotice={(text) => dispatch({ type: 'notice', text })}
                />
              )}
            </div>
          ))}
        </div>
        <div className="tabbar" role="tablist" aria-label="Kairo demo screens" onKeyDown={onKey}>
          {TABS.map((t) => (
            <button
              key={t.id} id={`tab-${t.id}`} type="button" role="tab" aria-selected={s.tab === t.id} aria-controls={`panel-${t.id}`}
              tabIndex={s.tab === t.id ? 0 : -1} ref={(el) => { tabRefs.current[t.id] = el }}
              className="tab" onClick={() => dispatch({ type: 'tab', tab: t.id })}
            >
              {t.icon}<span>{t.label}</span>
            </button>
          ))}
        </div>
      </div>
      <CallSheet
        state={s}
        onClose={() => dispatch({ type: 'closeCall' })}
        onTarget={(id) => dispatch({ type: 'callTarget', id })}
        onOutcome={(value) => dispatch({ type: 'callOutcome', value })}
      />
    </div>
  )
}
