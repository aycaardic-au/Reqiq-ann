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
