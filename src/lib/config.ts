import { supabase } from './supabase'

/** Annotator-facing texts (ADD-02 §7). Source: config/ui_texts.json → rubric_config. */
export type UiLang = 'en' | 'tr'
export type LanguagePref = 'EN' | 'TR' | 'BOTH'
export type AnnotatorType = 'student' | 'industry' | 'researcher' | 'other'

export interface ConsentTexts {
  title: string
  lede: string
  steps: string[]
  form_title: string
  form_sections: { heading: string; paragraphs: string[] }[]
  contact: string
  choice_title: string
  agree: string
  decline: string
  start_button: string
  choice_required: string
}

export interface DeclinedTexts { title: string; body: string; button: string }

export interface FormTexts {
  step: string
  title: string
  lede: string
  language_question: string
  language_hint: string
  language_options: Record<LanguagePref, string>
  type_question: string
  type_options: Record<AnnotatorType, string>
  other_label: string
  other_warning: string
  required_error: string
  button: string
}

export interface IntroTexts { step: string; title: string; items: string[]; button: string }

export interface SessionBarTexts {
  end_link: string
  end_confirm_title: string
  end_confirm_text: string
  opt_pause: string
  opt_pause_hint: string
  opt_end: string
  opt_end_hint: string
  opt_withdraw: string
  opt_withdraw_hint: string
  end_confirm_ok: string
  end_confirm_cancel: string
  end_confirm_simple: string
  paused_title: string
  paused_body: string
  paused_button: string
  ended_title: string
  ended_body: string
  withdrawn_body: string
  ended_button: string
}

export interface CommonTexts { save_error: string; saving: string; not_ready: string }

export interface AnnotateTexts {
  step: string
  progress: string
  requirement_title: string
  metric_label: string
  details_button: string
  details_hide: string
  requirement_label: string
  requirement_label_lang: string
  lang_names: Record<'EN' | 'TR', string>
  hint_button: string
  hint_hide: string
  hint_rules: string
  hint_bad: string
  hint_good: string
  note_toggle: string
  note_placeholder: string
  prev: string
  next: string
  finish: string
  incomplete: string
  loading: string
  exhausted: string
  max_reached: string
  to_thankyou: string
}

export interface AnnotateRubricTexts { cannot_assess: string; partial_note: string }

export interface BatchCompleteTexts { title: string; body: string; question: string; continue_button: string; stop_button: string }

export interface ThankYouTexts {
  title: string
  body: string
  session_label: string
  session_note: string
  comment_label: string
  comment_placeholder: string
  comment_max: string
  button: string
  closed: string
}

export interface RubricMetric {
  id: string
  name_en: string
  name_tr: string
  partial_scope_note?: boolean
  question: Record<UiLang, string>
  guidance: Record<UiLang, string>
  anchors: Record<'0' | '1' | '2', Record<UiLang, string>>
}

export interface HintMetric {
  id: string
  rules: Record<UiLang, string[]>
  bad: Record<UiLang, string[]>
  good: Record<UiLang, string[]>
}

export interface RubricContent {
  ui_texts_version: string
  app_name: Record<UiLang, string>
  consent: { tr: ConsentTexts }
  declined: { tr: DeclinedTexts }
  form: { tr: FormTexts }
  intro: { tr: IntroTexts }
  annotate: { tr: AnnotateTexts }
  annotate_rubric: Record<UiLang, AnnotateRubricTexts>
  batch_complete: { tr: BatchCompleteTexts }
  thankyou: { tr: ThankYouTexts }
  hints: { source: string; metrics: HintMetric[] }
  session_bar: { tr: SessionBarTexts }
  common: { tr: CommonTexts }
  scale: Record<'0' | '1' | '2', { label: Record<UiLang, string> }>
  general_guidance: Record<UiLang, string>
  metrics: RubricMetric[]
  [key: string]: unknown
}

/**
 * D-23: screen texts are Turkish for every session (EN, TR, BOTH).
 * The rubric (metric guidance, examples, score labels) follows each requirement's language.
 */
export const UI_LANG: UiLang = 'tr'

/** Rubric language for one requirement (D-23): EN requirement → EN rubric, TR → TR. */
export function rubricLangFor(languageTag: 'EN' | 'TR'): UiLang {
  return languageTag === 'EN' ? 'en' : 'tr'
}

function isValid(c: unknown): c is RubricContent {
  const x = c as RubricContent | null
  return Boolean(
    x?.consent?.tr?.form_sections && x?.declined?.tr && x?.form?.tr?.language_options &&
      x?.intro?.tr?.items && x?.annotate?.tr?.step && x?.annotate_rubric?.en && x?.thankyou?.tr?.closed &&
      x?.session_bar?.tr?.opt_withdraw && x?.common?.tr?.not_ready && x?.metrics?.length && x?.hints?.metrics?.length,
  )
}

/** EXT-CFG-001: load the active rubric configuration at startup. */
export async function loadActiveConfig(): Promise<RubricContent> {
  if (!supabase) {
    if (import.meta.env.DEV) {
      // Local development without Supabase credentials: use the source files.
      const [ui, rubric, hints] = await Promise.all([
        import('../../config/ui_texts.json'),
        import('../../config/rubric_v1.4.json'),
        import('../../config/metric_hints.json'),
      ])
      return { ...(rubric.default as object), ...(ui.default as object), hints: hints.default } as unknown as RubricContent
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
  if (!isValid(data?.content)) throw new Error('Active rubric_config lacks UI texts v2.3 or hints (run migrations 0010–0017)')
  return data.content
}

/** Replaces {name} placeholders. */
export function fill(text: string, vars: Record<string, string>): string {
  return text.replace(/\{(\w+)\}/g, (m, k: string) => vars[k] ?? m)
}
