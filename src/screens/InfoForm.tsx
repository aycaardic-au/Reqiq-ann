import { useState } from 'react'
import {
  EXPERIENCE_BANDS, ROLE_CATEGORIES, SCHOOL_LEVELS, STUDY_LEVELS, STUDY_YEARS,
  type AnnotatorType, type CommonTexts, type ExperienceBand, type FormTexts, type LanguagePref, type RoleCategory, type StudyLevel, type StudyYear,
} from '../lib/config'
import type { Background } from '../lib/session'

const LANGS: LanguagePref[] = ['EN', 'TR', 'BOTH']
const TYPES: AnnotatorType[] = ['student', 'industry', 'other']
const MAX_OTHER = 50
const MAX_SCHOOL = 100

/** Marks a mandatory question (explained in form.tr.lede); screen readers get the native `required` state. */
const Star = () => <span aria-hidden="true" style={{ color: 'var(--err)' }}> *</span>

/**
 * K3 Bilgi formu: language (FR-LNG) + annotator type (FR-ONB-003, FR-BKG), both required and marked with *.
 * Optional follow-up questions by type (migrations 0038-0040), unanswered by default and clearable with a link (ui_texts 2.35),
 * shown directly under the chosen type option:
 * industry → role + years of work experience; student → study level, class year (bachelor only) and an optional
 * free-text school / department (bachelor, master's, PhD). The academic-researcher type was removed on 17 Nov 2026.
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
  const [year, setYear] = useState<StudyYear | null>(null)
  const [school, setSchool] = useState('')
  const [tried, setTried] = useState(false)
  const [busy, setBusy] = useState(false)
  const [saveError, setSaveError] = useState(false)

  const askRole = type === 'industry' && Boolean(t.role_question && t.role_options)
  const askExperience = type === 'industry' && Boolean(t.experience_options && t.experience_question)
  const askLevel = type === 'student' && Boolean(t.study_level_question && t.study_level_options)
  const askYear = askLevel && level === 'bachelor' && Boolean(t.study_year_question)
  const askSchool = askLevel && level !== null && SCHOOL_LEVELS.includes(level) && Boolean(t.school_label)

  const chooseType = (k: AnnotatorType) => {
    if (k !== type) {
      // Follow-up answers belong to one type and are cleared when the type changes
      setRole(null); setRoleOther(''); setExperience(null); setLevel(null); setLevelOther(''); setYear(null); setSchool('')
    }
    setType(k)
    if (k !== 'other') setOther('')
  }

  const clean = (s: string, max = MAX_OTHER) => s.trim().slice(0, max) || null

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
        studyYear: askYear ? year : null,
        school: askSchool ? clean(school, MAX_SCHOOL) : null,
      })
    } catch (err) {
      console.error(err)
      setSaveError(true)
      setBusy(false)
    }
  }

  /** Follow-up of the chosen type, shown under its option (layout decision 17 Nov 2026). */
  const reveal = (k: AnnotatorType) => {
    const parts: React.ReactNode[] = []
    if (k === 'other') {
      parts.push(<OtherText key="o" id="type-other" label={t.other_label} warning={t.other_warning} value={other} onChange={setOther} />)
    }
    if (k === 'industry' && askRole) {
      parts.push(
        <Choice key="role" name="role" question={t.role_question!} keys={ROLE_CATEGORIES} labels={t.role_options!}
          value={role} onChange={(x) => { setRole(x); if (x !== 'other') setRoleOther('') }}
          clearText={t.clear_choice} onClear={() => { setRole(null); setRoleOther('') }}>
          {role === 'other' && <OtherText id="role-other" label={t.other_label} warning={t.other_warning} value={roleOther} onChange={setRoleOther} />}
        </Choice>,
      )
    }
    if (askExperience && k === 'industry') {
      parts.push(
        <Choice key="exp" name="experience" question={t.experience_question!}
          keys={EXPERIENCE_BANDS} labels={t.experience_options!} value={experience} onChange={setExperience}
          clearText={t.clear_choice} onClear={() => setExperience(null)} />,
      )
    }
    if (k === 'student' && askLevel) {
      parts.push(
        <Choice key="level" name="level" question={t.study_level_question!} keys={STUDY_LEVELS} labels={t.study_level_options!}
          value={level} onChange={(x) => {
            setLevel(x)
            if (x !== 'other') setLevelOther('')
            if (x !== 'bachelor') setYear(null)
            if (!SCHOOL_LEVELS.includes(x)) setSchool('')
          }}
          clearText={t.clear_choice} onClear={() => { setLevel(null); setLevelOther(''); setYear(null); setSchool('') }}>
          {level === 'other' && <OtherText id="level-other" label={t.other_label} warning={t.other_warning} value={levelOther} onChange={setLevelOther} />}
        </Choice>,
      )
      if (askYear) {
        parts.push(
          <fieldset key="year" className="subq">
            <legend>{t.study_year_question}</legend>
            <div className="pills">
              {STUDY_YEARS.map((y) => (
                <label key={y} className={`pill${year === y ? ' on' : ''}`}>
                  <input type="radio" name="year" value={y} checked={year === y} onChange={() => setYear(y)} />
                  <span>{y}</span>
                </label>
              ))}
            </div>
            {year !== null && t.clear_choice && <button type="button" className="link" onClick={() => setYear(null)}>{t.clear_choice}</button>}
          </fieldset>,
        )
      }
      if (askSchool) {
        parts.push(
          <div key="school" className="subq">
            <OtherText id="school" label={t.school_label!} warning={t.other_warning} value={school} onChange={setSchool} max={MAX_SCHOOL} />
          </div>,
        )
      }
    }
    return parts.length ? <div className="reveal">{parts}</div> : null
  }

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
          <div className="typeopts">
            {TYPES.map((k) => (
              <div key={k} className="typeopt-item">
                <label className={`pill${type === k ? ' on' : ''}`}>
                  <input type="radio" name="type" value={k} required checked={type === k} onChange={() => chooseType(k)} />
                  <span>{t.type_options[k]}</span>
                </label>
                {type === k && reveal(k)}
              </div>
            ))}
          </div>
          {tried && !type && <p className="err" role="alert">{t.required_error}</p>}
        </fieldset>
        {saveError && <p className="err" role="alert">{c.save_error}</p>}
        <div className="submitrow">
          <button type="submit" className="btn btn-primary" disabled={busy}>{busy ? c.saving : t.button}</button>
        </div>
      </form>
    </main>
  )
}

/** One optional single-choice follow-up question; no error when left empty. */
function Choice<K extends string>({
  name, question, keys, labels, value, onChange, clearText, onClear, children,
}: {
  name: string
  question: string
  keys: K[]
  labels: Record<K, string>
  value: K | null
  onChange: (k: K) => void
  /** "Seçimi temizle": a radio button cannot be unselected, so the optional question gets a clear link (ui_texts 2.35). */
  clearText?: string
  onClear?: () => void
  children?: React.ReactNode
}) {
  return (
    <fieldset className="subq">
      <legend>{question}</legend>
      <div className="pills">
        {keys.filter((k) => labels[k]).map((k) => (
          <label key={k} className={`pill${value === k ? ' on' : ''}`}>
            <input type="radio" name={name} value={k} checked={value === k} onChange={() => onChange(k)} />
            <span>{labels[k]}</span>
          </label>
        ))}
      </div>
      {value !== null && clearText && onClear && <button type="button" className="link" onClick={onClear}>{clearText}</button>}
      {children}
    </fieldset>
  )
}

/** Free text for "Diğer" (at most 50 characters) and school / department (100) with the no-identifying-information warning (D-04). */
function OtherText({ id, label, warning, value, onChange, max = MAX_OTHER }: {
  id: string; label: string; warning: string; value: string; onChange: (v: string) => void; max?: number
}) {
  return (
    <div className="other">
      <label htmlFor={id}>{label}</label>
      <input id={id} type="text" maxLength={max} value={value} onChange={(e) => onChange(e.target.value)} />
      <p className="warning" role="note"><span aria-hidden="true">⚠ </span>{warning}</p>
    </div>
  )
}
