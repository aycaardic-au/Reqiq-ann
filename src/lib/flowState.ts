import type { LanguagePref } from './config'

/**
 * Flow progress kept in localStorage (D-24):
 * consent (K1) → form (K3) → intro (K4) → annotate (K5) → batch_complete (K6) → thankyou
 * The session row is created when the form is submitted (D-24); see session.ts.
 */
export type Step = 'consent' | 'form' | 'intro' | 'annotate' | 'batch_complete' | 'thankyou'

export interface BatchSummary { batchCount: number; batchNumber?: number; total: number; canContinue: boolean }

export interface FlowState {
  step: Step
  language: LanguagePref | null
  summary?: BatchSummary
}

const KEY = 'reqiq_ann_flow'
const STEPS: Step[] = ['consent', 'form', 'intro', 'annotate', 'batch_complete', 'thankyou']
export const INITIAL_FLOW: FlowState = { step: 'consent', language: null }

export function readFlow(): FlowState {
  try {
    const raw = localStorage.getItem(KEY)
    if (!raw) return INITIAL_FLOW
    const s = JSON.parse(raw) as FlowState
    if (STEPS.includes(s.step)) return s
  } catch {
    /* storage unavailable or corrupt: start again */
  }
  return INITIAL_FLOW // also covers states saved by the earlier flow (v1.x)
}

export function writeFlow(s: FlowState): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(s))
  } catch {
    /* storage unavailable: flow still works for this page load */
  }
}

/**
 * FR-SES-010: the address ".../#/reset" clears this browser's flow state only.
 * The hash is removed afterwards, so a later reload does not reset again.
 * Returns true when the reset was requested (the caller then starts at K1).
 */
export function consumeResetHash(): boolean {
  try {
    if (window.location.hash.replace(/\/+$/, '') !== '#/reset') return false
    clearLocal()
    window.history.replaceState(null, '', `${window.location.pathname}${window.location.search}#/`)
    return true
  } catch {
    return false
  }
}

export function clearLocal(): void {
  try {
    localStorage.removeItem(KEY)
    localStorage.removeItem('reqiq_ann_session')
    localStorage.removeItem('reqiq_ann_drafts')
  } catch {
    /* nothing to clear */
  }
}
