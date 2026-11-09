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

export interface ConsentTexts {
  title: string
  body: string
  checkbox: string
  agree_button: string
  decline_button: string
  declined_title: string
  declined_body: string
}

export type AnnotatorType = 'student' | 'industry' | 'researcher' | 'other'

export interface BackgroundTexts {
  title: string
  question: string
  options: Record<AnnotatorType, string>
  other_label: string
  other_warning: string
  button: string
}

export interface CommonTexts {
  save_error: string
  saving: string
}

export interface RubricContent {
  ui_texts_version: string
  app_name: Record<UiLang, string>
  language_select: LanguageSelectTexts
  welcome: Record<UiLang, WelcomeTexts>
  consent: Record<UiLang, ConsentTexts>
  background: Record<UiLang, BackgroundTexts>
  common: Record<UiLang, CommonTexts>
  [key: string]: unknown
}

/**
 * D-23: screen texts (welcome, consent, background, batch complete, thank-you,
 * buttons, messages) are Turkish for every session, including EN. The rubric
 * (metric guidance, examples, score labels) follows each requirement's language.
 * EN screen texts stay in the config for possible later use.
 */
export function uiLangFor(_pref: LanguagePref): UiLang {
  return 'tr'
}

/** Rubric language for one requirement (D-23): EN requirement → EN rubric, TR → TR. */
export function rubricLangFor(languageTag: 'EN' | 'TR'): UiLang {
  return languageTag === 'EN' ? 'en' : 'tr'
}

function isValid(c: unknown): c is RubricContent {
  const x = c as RubricContent | null
  return Boolean(
    x?.app_name?.en && x?.language_select?.option_en && x?.welcome?.tr?.title &&
      x?.consent?.tr?.title && x?.background?.tr?.title && x?.common?.tr?.save_error,
  )
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
  if (!isValid(data?.content)) throw new Error('Active rubric_config has no UI texts (run migrations 0006 and 0009)')
  return data.content
}
