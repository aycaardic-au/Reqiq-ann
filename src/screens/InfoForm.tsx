import { useState } from 'react'
import {
  EXPERIENCE_BANDS, ROLE_CATEGORIES, STUDY_LEVELS,
  type AnnotatorType, type CommonTexts, type ExperienceBand, type FormTexts, type LanguagePref, type RoleCategory, type StudyLevel,
} from '../lib/config'
import type { Background } from '../lib/session'

const LANGS: LanguagePref[] = ['EN', 'TR', 'BOTH']
const TYPES: AnnotatorType[] = ['student', 'industry', 'researcher', 'other']
const MAX_OTHER = 50

/** Marks a mandatory question (explained in form.tr.lede); screen readers get the native `required` state. */
const Star = () => <span aria-hidden="true" style={{ color: 'var(--err)' }}> *</span>

/**
 * K3 Bilgi formu: language (FR-LNG) + annotator type (FR-ONB-003, FR-BKG), both required and marked with *.
 * Optional follow-up questions by type (migration 0038, ui_texts 2.29), each with "prefer not to say":
 * industry → role + years in the sector; researcher → years of sector/academic experience; student → study level.
 * A question is shown only when its texts exist in the active configuration.
 */
export default function InfoForm({
  t, c, onSubmit,
}: {
  t: FormTexts
  c: CommonTexts
  onSubmit: (lang: LanguagePref, background: Background) => Promise<void>
}) {
  const [lang, setLang] = useState<LanguagePref | null>(null)
  const [type, setType] = useState<AnnotatorType | null>(null)
  const [other, setOther] = useState('')
  const [role, setRole] = useState<RoleCategory | null>(null)
  const [roleOther, setRoleOther] = useState('')
  const [experience, setExperience] = useState<ExperienceBand | null>(null)
  const [level, setLevel] = useState<StudyLevel | null>(null)
  const [levelOther, setLevelOther] = useState('')
  const [tried, setTried] = useState(false)
  const [busy, setBusy] = useState(false)
  const [saveError, setSaveError] = useState(false)

  const askRole = type === 'industry' && Boolean(t.role_question && t.role_options)
  const askExperience = (type === 'industry' || type === 'researcher') && Boolean(t.experience_options)
    && Boolean(type === 'industry' ? t.experience_question : t.researcher_experience_question)
  const askLevel = type === 'student' && Boolean(t.study_level_question && t.study_level_options)

  const chooseType = (k: AnnotatorType) => {
    if (k !== type) {
      // Follow-up answers belong to one type; the experience question differs between industry and researcher
      setRole(null); setRoleOther(''); setExperience(null); setLevel(null); setLevelOther('')
    }
    setType(k)
    if (k !== 'other') setOther('')
  }

  const clean = (s: string) => s.trim().slice(0, MAX_OTHER) || null

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    setTried(true)
    if (!lang || !type) return
    setBusy(true)
    setSaveError(false)
    try {
      await onSubmit(lang, {
        type,
        other: type === 'other' ? clean(other) : null,
        role: askRole ? role : null,
        roleOther: askRole && role === 'other' ? clean(roleOther) : null,
        experience: askExperience ? experience : null,
        studyLevel: askLevel ? level : null,
        studyLevelOther: askLevel && level === 'other' ? clean(levelOther) : null,
      })
    } catch (err) {
      console.error(err)
      setSaveError(true)
      setBusy(false)
    }
  }

  let n = 2
  return (
    <main className="survey">
      <h1>{t.title}</h1>
      <p className="lede">{t.lede}</p>
      <form onSubmit={submit} noValidate>
        <fieldset className="q">
          <legend><span className="n">1.</span>{t.language_question}<Star /></legend>
          <p className="hint">{t.language_hint}</p>
          <div className="pills">
            {LANGS.map((k) => (
              <label key={k} className={`pill${lang === k ? ' on' : ''}`}>
                <input type="radio" name="lang" value={k} required checked={lang === k} onChange={() => setLang(k)} />
                <span>{t.language_options[k]}</span>
              </label>
            ))}
          </div>
          {tried && !lang && <p className="err" role="alert">{t.required_error}</p>}
        </fieldset>
        <fieldset className="q">
          <legend><span className="n">2.</span>{t.type_question}<Star /></legend>
          <div className="pills">
            {TYPES.map((k) => (
              <label key={k} className={`pill${type === k ? ' on' : ''}`}>
                <input type="radio" name="type" value={k} required checked={type === k} onChange={() => chooseType(k)} />
                <span>{t.type_options[k]}</span>
              </label>
            ))}
          </div>
          {type === 'other' && (
            <OtherText id="type-other" label={t.other_label} warning={t.other_warning} value={other} onChange={setOther} />
          )}
          {tried && !type && <p className="err" role="alert">{t.required_error}</p>}
        </fieldset>
        {askRole && (
          <Choice
            n={++n} name="role" question={t.role_question!} keys={ROLE_CATEGORIES} labels={t.role_options!}
            value={role} onChange={(k) => { setRole(k); if (k !== 'other') setRoleOther('') }}
          >
            {role === 'other' && (
              <OtherText id="role-other" label={t.other_label} warning={t.other_warning} value={roleOther} onChange={setRoleOther} />
            )}
          </Choice>
        )}
        {askExperience && (
          <Choice
            n={++n} name="experience"
            question={(type === 'industry' ? t.experience_question : t.researcher_experience_question)!}
            keys={EXPERIENCE_BANDS} labels={t.experience_options!} value={experience} onChange={setExperience}
          />
        )}
        {askLevel && (
          <Choice
            n={++n} name="level" question={t.study_level_question!} keys={STUDY_LEVELS} labels={t.study_level_options!}
            value={level} onChange={(k) => { setLevel(k); if (k !== 'other') setLevelOther('') }}
          >
            {level === 'other' && (
              <OtherText id="level-other" label={t.other_label} warning={t.other_warning} value={levelOther} onChange={setLevelOther} />
            )}
          </Choice>
        )}
        {saveError && <p className="err" role="alert">{c.save_error}</p>}
        <div className="submitrow">
          <button type="submit" className="btn btn-primary" disabled={busy}>{busy ? c.saving : t.button}</button>
        </div>
      </form>
    </main>
  )
}

/** One optional single-choice question; no error when left empty. */
function Choice<K extends string>({
  n, name, question, keys, labels, value, onChange, children,
}: {
  n: number
  name: string
  question: string
  keys: K[]
  labels: Record<K, string>
  value: K | null
  onChange: (k: K) => void
  children?: React.ReactNode
}) {
  return (
    <fieldset className="q">
      <legend><span className="n">{n}.</span>{question}</legend>
      <div className="pills">
        {keys.filter((k) => labels[k]).map((k) => (
          <label key={k} className={`pill${value === k ? ' on' : ''}`}>
            <input type="radio" name={name} value={k} checked={value === k} onChange={() => onChange(k)} />
            <span>{labels[k]}</span>
          </label>
        ))}
      </div>
      {children}
    </fieldset>
  )
}

/** Free text for "Diğer" (at most 50 characters) with the no-identifying-information warning (D-04). */
function OtherText({ id, label, warning, value, onChange }: {
  id: string; label: string; warning: string; value: string; onChange: (v: string) => void
}) {
  return (
    <div className="other">
      <label htmlFor={id}>{label}</label>
      <input id={id} type="text" maxLength={MAX_OTHER} value={value} onChange={(e) => onChange(e.target.value)} />
      <p className="warning" role="note"><span aria-hidden="true">⚠ </span>{warning}</p>
    </div>
  )
}
