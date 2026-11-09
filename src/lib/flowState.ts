import type { LanguagePref } from './config'

/**
 * Flow progress kept in localStorage (D-24):
 * consent (K1) → form (K3) → intro (K4) → annotate (K5) → …
 * The session row is created when the form is submitted (D-24); see session.ts.
 */
export type Step = 'consent' | 'form' | 'intro' | 'annotate'

export interface FlowState {
  step: Step
  language: LanguagePref | null
}

const KEY = 'reqiq_ann_flow'
const STEPS: Step[] = ['consent', 'form', 'intro', 'annotate']
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

export function clearLocal(): void {
  try {
    localStorage.removeItem(KEY)
    localStorage.removeItem('reqiq_ann_session')
  } catch {
    /* nothing to clear */
  }
}
