import { useState } from 'react'
import type { AnnotatorType, CommonTexts, FormTexts, LanguagePref } from '../lib/config'

const LANGS: LanguagePref[] = ['EN', 'TR', 'BOTH']
const TYPES: AnnotatorType[] = ['student', 'industry', 'researcher', 'other']

/** K3 Bilgi formu: language (FR-LNG) + annotator type (FR-ONB-003, FR-BKG). Both required. */
export default function InfoForm({
  t, c, onSubmit,
}: {
  t: FormTexts
  c: CommonTexts
  onSubmit: (lang: LanguagePref, type: AnnotatorType, other: string | null) => Promise<void>
}) {
  const [lang, setLang] = useState<LanguagePref | null>(null)
  const [type, setType] = useState<AnnotatorType | null>(null)
  const [other, setOther] = useState('')
  const [tried, setTried] = useState(false)
  const [busy, setBusy] = useState(false)
  const [saveError, setSaveError] = useState(false)

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    setTried(true)
    if (!lang || !type) return
    setBusy(true)
    setSaveError(false)
    try {
      await onSubmit(lang, type, type === 'other' ? other.trim() || null : null)
    } catch (err) {
      console.error(err)
      setSaveError(true)
      setBusy(false)
    }
  }

  return (
    <main className="survey">
      <h1>{t.title}</h1>
      <p className="lede">{t.lede}</p>
      <form onSubmit={submit} noValidate>
        <fieldset className="q">
          <legend><span className="n">1.</span>{t.language_question}</legend>
          <p className="hint">{t.language_hint}</p>
          <div className="pills">
            {LANGS.map((k) => (
              <label key={k} className={`pill${lang === k ? ' on' : ''}`}>
                <input type="radio" name="lang" value={k} checked={lang === k} onChange={() => setLang(k)} />
                <span>{t.language_options[k]}</span>
              </label>
            ))}
          </div>
          {tried && !lang && <p className="err" role="alert">{t.required_error}</p>}
        </fieldset>
        <fieldset className="q">
          <legend><span className="n">2.</span>{t.type_question}</legend>
          <div className="pills">
            {TYPES.map((k) => (
              <label key={k} className={`pill${type === k ? ' on' : ''}`}>
                <input type="radio" name="type" value={k} checked={type === k}
                  onChange={() => { setType(k); if (k !== 'other') setOther('') }} />
                <span>{t.type_options[k]}</span>
              </label>
            ))}
          </div>
          {type === 'other' && (
            <div className="other">
              <label htmlFor="type-other">{t.other_label}</label>
              <input id="type-other" type="text" maxLength={50} value={other} onChange={(e) => setOther(e.target.value)} />
              <p className="warning" role="note"><span aria-hidden="true">⚠ </span>{t.other_warning}</p>
            </div>
          )}
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
