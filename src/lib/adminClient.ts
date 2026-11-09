import { createClient, type SupabaseClient } from '@supabase/supabase-js'

/**
 * Admin client (D-29): Supabase Auth e-mail + password, session kept in this browser.
 * Separate from the annotator client so annotator RPCs always run with the anonymous role.
 */
const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY

export const adminDb: SupabaseClient | null = url && key
  ? createClient(url, key, { auth: { persistSession: true, storageKey: 'reqiq-ann-admin', autoRefreshToken: true } })
  : null

/** Reads a whole table in pages of 1000 rows (PostgREST default limit). */
export async function fetchAll<T>(table: string, orderBy: string): Promise<T[]> {
  if (!adminDb) throw new Error('Supabase is not configured')
  const out: T[] = []
  for (let from = 0; ; from += 1000) {
    const cols = table === 'rubric_config' ? 'config_id, version_label, uploaded_at, is_active, note' : '*'
    const { data, error } = await adminDb.from(table).select(cols).order(orderBy).range(from, from + 999)
    if (error) throw error
    out.push(...(data as T[]))
    if (!data || data.length < 1000) return out
  }
}
