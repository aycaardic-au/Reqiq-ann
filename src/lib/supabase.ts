import { createClient, type SupabaseClient } from '@supabase/supabase-js'

/**
 * Supabase client using the PUBLIC anon key only (EXT-DB-001).
 * Privileged operations go through Edge Functions (EXT-DB-003).
 */
const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

export const isSupabaseConfigured = Boolean(url && anonKey)

export const supabase: SupabaseClient | null = isSupabaseConfigured
  ? createClient(url, anonKey, { auth: { persistSession: false } })
  : null
