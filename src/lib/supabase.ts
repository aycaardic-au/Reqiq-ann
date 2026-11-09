import { createClient, type SupabaseClient } from '@supabase/supabase-js'

/**
 * Supabase client using the PUBLIC publishable key only (EXT-DB-001).
 * Privileged operations go through Edge Functions (EXT-DB-003).
 */
const url = import.meta.env.VITE_SUPABASE_URL
const publishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY

export const isSupabaseConfigured = Boolean(url && publishableKey)

export const supabase: SupabaseClient | null = isSupabaseConfigured
  ? createClient(url, publishableKey, { auth: { persistSession: false } })
  : null
