import type { LanguagePref } from './config'

/**
 * Onboarding progress kept in localStorage (FR-LNG-003).
 * The session row is created at consent (D-20); see session.ts.
 */
export type Step = 'language' | 'welcome' | 'consent' | 'background' | 'calibration'

export interface FlowState {
  language: LanguagePref | null
  step: Step
}

const KEY = 'reqiq_ann_flow'
const STEPS: Step[] = ['language', 'welcome', 'consent', 'background', 'calibration']
const INITIAL: FlowState = { language: null, step: 'language' }

export function readFlow(): FlowState {
  try {
    const raw = localStorage.getItem(KEY)
    if (!raw) return INITIAL
    const s = JSON.parse(raw) as FlowState
    if (s.language && ['EN', 'TR', 'BOTH'].includes(s.language) && STEPS.includes(s.step)) return s
  } catch {
    /* storage unavailable or corrupt: start again */
  }
  return INITIAL
}

export function writeFlow(s: FlowState): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(s))
  } catch {
    /* storage unavailable: flow still works for this page load */
  }
}
