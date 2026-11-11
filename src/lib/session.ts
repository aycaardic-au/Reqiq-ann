import { supabase } from './supabase'
import type { LanguagePref } from './config'

/**
 * Pseudonymous session (FR-SES-002..004, NFR-SEC-001) and all annotator RPCs (EXT-DB-002).
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
  const parts = [navigator.userAgent, `${screen.width}x${screen.height}`, String(new Date().getTimezoneOffset()), navigator.language, salt]
  return { session_id: await sha256Hex(parts.join('|')), salt }
}

function storeSession(s: StoredSession): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(s))
  } catch {
    /* FR-SES-004: without storage the session cannot be recovered later */
  }
}

/** A server-side rule rejected the call (RAISE EXCEPTION): retrying will not help. */
export class ServerRuleError extends Error {
  constructor(message: string) { super(message); this.name = 'ServerRuleError' }
}

/** The session was ended or withdrawn (FR-SES-009). */
export const isSessionClosed = (e: unknown) => e instanceof ServerRuleError && /session ended|unknown session/i.test(e.message)

/**
 * NFR-REL-001: network/transport failures are retried up to 3 times with exponential back-off
 * (0.5 s, 1 s, 2 s); server rule violations (PostgreSQL P0001) are not retried.
 */
async function rpcData<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  if (!supabase) {
    if (import.meta.env.DEV) return devRpc(fn, args) as T
    throw new Error('Supabase is not configured')
  }
  let lastError: unknown
  for (let attempt = 0; attempt <= 3; attempt++) {
    if (attempt > 0) await new Promise((r) => setTimeout(r, 500 * 2 ** (attempt - 1)))
    try {
      const { data, error } = await supabase.rpc(fn, args)
      if (!error) return data as T
      if (error.code === 'P0001' || error.code === '22023' || error.code === '23514') throw new ServerRuleError(error.message)
      lastError = error
    } catch (e) {
      if (e instanceof ServerRuleError) throw e
      lastError = e
    }
  }
  throw lastError instanceof Error ? lastError : new Error(JSON.stringify(lastError))
}

/** K3 submit: create the session row (D-20, D-21). Idempotent server-side. */
export async function createSession(language: LanguagePref, consentVersion: string): Promise<StoredSession> {
  const s = readSession() ?? (await newSessionId())
  storeSession(s)
  await rpcData<null>('create_session', { p_session_id: s.session_id, p_language: language, p_consent_version: consentVersion })
  return s
}

export async function saveBackground(sessionId: string, type: string, other: string | null): Promise<void> {
  await rpcData<null>('set_background', { p_session_id: sessionId, p_type: type, p_other: other })
}

/* ---------- K5 / K6 / thank-you ---------- */

export interface MetricScore {
  metric_id: string
  score: number | null
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
  | { status: 'exhausted' | 'max_reached' | 'ended' }

export interface CompleteResult {
  batch_count: number
  batch_number?: number
  total: number
  batches_completed: number
  can_continue: boolean
}

export const assignBatch = (sessionId: string) => rpcData<BatchResult>('assign_batch', { p_session_id: sessionId })

export const saveScores = (sessionId: string, itemId: number, scores: MetricScore[], seconds: number) =>
  rpcData<null>('save_scores', { p_session_id: sessionId, p_batch_item_id: itemId, p_scores: scores, p_time_seconds: seconds })

export const completeBatch = (sessionId: string, batchId: string) =>
  rpcData<CompleteResult>('complete_batch', { p_session_id: sessionId, p_batch_id: batchId })

export const endSession = (sessionId: string) => rpcData<null>('end_session', { p_session_id: sessionId })

export const withdrawSession = (sessionId: string) => rpcData<null>('withdraw_session', { p_session_id: sessionId })

/** Thank-you: saves the optional comment and closes the session (ADD-02 §6). */
export const finishSession = (sessionId: string, comment: string) =>
  rpcData<null>('finish_session', { p_session_id: sessionId, p_comment: comment })

/** NFR-REL-004: best-effort client error report; never throws. */
export function logClientError(location: string, message: string): void {
  if (!supabase) { if (import.meta.env.DEV) console.warn('[dev] client error', location, message); return }
  supabase.rpc('log_client_error', {
    p_session_id: readSession()?.session_id ?? null, p_location: location,
    p_message: message.slice(0, 2000), p_user_agent: navigator.userAgent.slice(0, 300),
  }).then(() => undefined, () => undefined)
}

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
    return { batch_count: n, batch_number: devDone, total: n * devDone, batches_completed: devDone, can_continue: devDone < 2 }
  }
  return null
}

/* ---------- K4b Briefing (SRS v1.4 FR-BRF, migration 0023) ---------- */

/** FR-BRF-004: minimum visible seconds per briefing page (admin parameter). Falls back to 10 s. */
export async function fetchBriefingMinSeconds(): Promise<number> {
  if (!supabase) return 10
  try {
    const { data, error } = await supabase.from('app_config').select('briefing_min_seconds').eq('id', 1).single()
    if (error || typeof data?.briefing_min_seconds !== 'number') return 10
    return data.briefing_min_seconds
  } catch {
    return 10
  }
}

/** FR-BRF-006: metric ids whose briefing page was completed in this batch. */
export const getBriefingProgress = (sessionId: string, batchId: string) =>
  rpcData<string[] | null>('get_briefing_progress', { p_session_id: sessionId, p_batch_id: batchId })

/** FR-BRF-006: store one page visit when the annotator moves forward from it. */
export const saveBriefingView = (sessionId: string, batchId: string, metricId: string, language: LanguagePref, seconds: number, completed: boolean) =>
  rpcData<null>('save_briefing_view', {
    p_session_id: sessionId, p_batch_id: batchId, p_metric_id: metricId,
    p_language: language, p_visible_seconds: seconds, p_completed: completed,
  })
