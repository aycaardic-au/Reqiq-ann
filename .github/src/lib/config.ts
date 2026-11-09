import { supabase } from './supabase'

/** Annotator-facing texts (ADD-02 v0.6 §7). Source: config/ui_texts.json → rubric_config. */
export type UiLang = 'en' | 'tr'
export type LanguagePref = 'EN' | 'TR' | 'BOTH'

export interface LanguageSelectTexts {
  page_title_en: string
  page_title_tr: string
  option_en: string
  option_tr: string
  option_both_en: string
  option_both_tr: string
}

export interface WelcomeTexts {
  title: string
  body: string
  button: string
}

export interface RubricContent {
  app_name: Record<UiLang, string>
  language_select: LanguageSelectTexts
  welcome: Record<UiLang, WelcomeTexts>
  [key: string]: unknown
}

/** D-16: BOTH sessions use the Turkish interface. */
export function uiLangFor(pref: LanguagePref): UiLang {
  return pref === 'EN' ? 'en' : 'tr'
}

function isValid(c: unknown): c is RubricContent {
  const x = c as RubricContent | null
  return Boolean(x?.app_name?.en && x?.language_select?.option_en && x?.welcome?.en?.title && x?.welcome?.tr?.title)
}

/** EXT-CFG-001: load the active rubric configuration at startup. */
export async function loadActiveConfig(): Promise<RubricContent> {
  if (!supabase) {
    if (import.meta.env.DEV) {
      // Local development without Supabase credentials: use the source file.
      const local = await import('../../config/ui_texts.json')
      return local.default as unknown as RubricContent
    }
    throw new Error('Supabase is not configured')
  }
  const { data, error } = await supabase
    .from('rubric_config')
    .select('content')
    .eq('is_active', true)
    .limit(1)
    .single()
  if (error) throw error
  if (!isValid(data?.content)) throw new Error('Active rubric_config has no UI texts (run migration 0006)')
  return data.content
}
