import { supabase } from './supabase'
import type { LanguagePref } from './config'

/**
 * Pseudonymous session (FR-SES-002..004, NFR-SEC-001).
 * session_id = SHA-256(user-agent | screen | timezone offset | language | UUID salt).
 * Only the hash leaves the browser. Hash and salt are kept in localStorage.
 */
const KEY = 'reqiq_ann_session'

export interface StoredSession {
  session_id: string
  salt: string
}

export function readSession(): StoredSession | null {
  try {
    const raw = localStorage.getItem(KEY)
    if (!raw) return null
    const s = JSON.parse(raw) as StoredSession
    return /^[0-9a-f]{64}$/.test(s.session_id) ? s : null
  } catch {
    return null
  }
}

async function sha256Hex(text: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, '0')).join('')
}

export async function newSessionId(): Promise<StoredSession> {
  const salt = crypto.randomUUID()
  const parts = [
    navigator.userAgent,
    `${screen.width}x${screen.height}`,
    String(new Date().getTimezoneOffset()),
    navigator.language,
    salt,
  ]
  return { session_id: await sha256Hex(parts.join('|')), salt }
}

function storeSession(s: StoredSession): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(s))
  } catch {
    /* FR-SES-004: without storage the session cannot be recovered later */
  }
}

/** NFR-REL-001: up to 3 retries with exponential back-off (0.5 s, 1 s, 2 s). */
async function rpc(fn: string, args: Record<string, unknown>): Promise<void> {
  if (!supabase) {
    if (import.meta.env.DEV) {
      console.info('[dev] rpc skipped (no Supabase):', fn, args)
      return
    }
    throw new Error('Supabase is not configured')
  }
  let lastError: unknown
  for (let attempt = 0; attempt <= 3; attempt++) {
    if (attempt > 0) await new Promise((r) => setTimeout(r, 500 * 2 ** (attempt - 1)))
    const { error } = await supabase.rpc(fn, args)
    if (!error) return
    lastError = error
  }
  throw lastError
}

/** [3] Consent given: create the session row (D-20, D-21). Idempotent server-side. */
export async function createSession(language: LanguagePref, consentVersion: string): Promise<StoredSession> {
  const s = readSession() ?? (await newSessionId())
  storeSession(s)
  await rpc('create_session', { p_session_id: s.session_id, p_language: language, p_consent_version: consentVersion })
  return s
}

/** [4] Background answer (FR-ONB-003). */
export async function saveBackground(sessionId: string, type: string, other: string | null): Promise<void> {
  await rpc('set_background', { p_session_id: sessionId, p_type: type, p_other: other })
}

/* ---------- K5 / K6 / thank-you (migration 0013) ---------- */

export interface MetricScore {
  metric_id: string
  score: number | null
  cannot_assess: boolean
  note: string | null
}

export interface BatchItem {
  batch_item_id: number
  position: number
  language_tag: 'EN' | 'TR'
  text: string
  scores: MetricScore[]
}

export type BatchResult =
  | { status: 'ok'; batch_id: string; batch_number: number; items: BatchItem[] }
  | { status: 'exhausted' | 'max_reached' }

export interface CompleteResult {
  batch_count: number
  total: number
  batches_completed: number
  can_continue: boolean
}

async function rpcData<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  if (!supabase) {
    if (import.meta.env.DEV) return devRpc(fn, args) as T
    throw new Error('Supabase is not configured')
  }
  let lastError: unknown
  for (let attempt = 0; attempt <= 3; attempt++) {
    if (attempt > 0) await new Promise((r) => setTimeout(r, 500 * 2 ** (attempt - 1)))
    const { data, error } = await supabase.rpc(fn, args)
    if (!error) return data as T
    lastError = error
  }
  throw lastError
}

export const assignBatch = (sessionId: string) => rpcData<BatchResult>('assign_batch', { p_session_id: sessionId })

export const saveScores = (sessionId: string, itemId: number, scores: MetricScore[], seconds: number) =>
  rpcData<null>('save_scores', { p_session_id: sessionId, p_batch_item_id: itemId, p_scores: scores, p_time_seconds: seconds })

export const completeBatch = (sessionId: string, batchId: string) =>
  rpcData<CompleteResult>('complete_batch', { p_session_id: sessionId, p_batch_id: batchId })

export const saveComment = (sessionId: string, comment: string) =>
  rpcData<null>('set_comment', { p_session_id: sessionId, p_comment: comment })

/* Local development without Supabase: a small in-memory stand-in for the RPCs. */
let devBatch: BatchResult | null = null
let devDone = 0
function devRpc(fn: string, args: Record<string, unknown>): unknown {
  console.info('[dev] rpc', fn)
  if (fn === 'assign_batch') {
    if (devDone >= 2) return { status: 'max_reached' }
    if (!devBatch) {
      const items: BatchItem[] = Array.from({ length: 6 }, (_, i) => ({
        batch_item_id: devDone * 100 + i + 1,
        position: i + 1,
        language_tag: i % 2 ? 'TR' : 'EN',
        text: i % 2
          ? 'Sistem, kullanıcı oturum açtığında son 30 günün işlem özetini 2 saniye içinde göstermelidir.'
          : 'The system shall display the operational status of each component to the operator.',
        scores: [],
      }))
      devBatch = { status: 'ok', batch_id: `dev-${devDone + 1}`, batch_number: devDone + 1, items }
    }
    return devBatch
  }
  if (fn === 'save_scores' && devBatch && devBatch.status === 'ok') {
    const it = devBatch.items.find((x) => x.batch_item_id === args.p_batch_item_id)
    if (it) it.scores = args.p_scores as MetricScore[]
    return null
  }
  if (fn === 'complete_batch') {
    devDone += 1
    const n = devBatch && devBatch.status === 'ok' ? devBatch.items.length : 0
    devBatch = null
    return { batch_count: n, total: n * devDone, batches_completed: devDone, can_continue: devDone < 2 }
  }
  return null
}
