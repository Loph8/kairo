import type { CheckIn } from './demo'

export type Tab = 'family' | 'insights' | 'settings'
export type SyncStatus = 'idle' | 'syncing' | 'done'
export type CopyStatus = 'idle' | 'copied' | 'failed'

export interface DemoState {
  tab: Tab
  /** whose "When you pick up" dial Insights shows */
  insightsMemberId: string
  checkIn: CheckIn
  sync: SyncStatus
  copy: CopyStatus
  /** a short, honest message for the last demo-only action */
  notice: string | null
  callOpen: boolean
  callTargetId: string
  callOutcome: 'yes' | 'no' | null
}

export type DemoAction =
  | { type: 'tab'; tab: Tab }
  | { type: 'insightsMember'; id: string }
  | { type: 'checkIn'; value: Exclude<CheckIn, null> }
  | { type: 'syncStart' }
  | { type: 'syncDone' }
  | { type: 'copy'; ok: boolean }
  | { type: 'notice'; text: string | null }
  | { type: 'openCall' }
  | { type: 'closeCall' }
  | { type: 'callTarget'; id: string }
  | { type: 'callOutcome'; value: 'yes' | 'no' }

export const initialState = (): DemoState => ({
  tab: 'family',
  insightsMemberId: 'you',
  checkIn: null,
  sync: 'idle',
  copy: 'idle',
  notice: null,
  callOpen: false,
  callTargetId: 'mom',
  callOutcome: null,
})

export function reducer(s: DemoState, a: DemoAction): DemoState {
  switch (a.type) {
    case 'tab':
      return { ...s, tab: a.tab, notice: null }
    case 'insightsMember':
      return { ...s, insightsMemberId: a.id }
    case 'checkIn':
      // Choosing the same button again clears it, like an undo.
      return { ...s, checkIn: s.checkIn === a.value ? null : a.value }
    case 'syncStart':
      return s.sync === 'syncing' ? s : { ...s, sync: 'syncing' }
    case 'syncDone':
      return s.sync === 'syncing' ? { ...s, sync: 'done' } : s
    case 'copy':
      return { ...s, copy: a.ok ? 'copied' : 'failed' }
    case 'notice':
      return { ...s, notice: a.text }
    case 'openCall':
      return { ...s, callOpen: true, callOutcome: null }
    case 'closeCall':
      return { ...s, callOpen: false }
    case 'callTarget':
      return { ...s, callTargetId: a.id, callOutcome: null }
    case 'callOutcome':
      return { ...s, callOutcome: a.value }
  }
}
