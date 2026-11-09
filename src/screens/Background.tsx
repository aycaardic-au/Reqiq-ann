import { useState } from 'react'
import type { AnnotatorType, BackgroundTexts, CommonTexts } from '../lib/config'

const TYPES: AnnotatorType[] = ['student', 'industry', 'researcher', 'other']

/** [4] Background (FR-ONB-003, FR-BKG-001..004). Exactly one option; "Other" text optional, max 50. */
export default function Background({
  t, c, onSubmit,
}: { t: BackgroundTexts; c: CommonTexts; onSubmit: (type: AnnotatorType, other: string | null) => Promise<void> }) {
  const [type, setType] = useState<AnnotatorType | null>(null)
  const [other, setOther] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(false)

  const submit = async () => {
    if (!type) return
    setBusy(true)
    setError(false)
    try {
      await onSubmit(type, type === 'other' ? other.trim() || null : null)
    } catch (e) {
      console.error(e)
      setError(true)
      setBusy(false)
    }
  }

  return (
    <section className="card" aria-labelledby="bg-title">
      <h1 id="bg-title" className="title">{t.title}</h1>
      <fieldset className="radios">
        <legend>{t.question}</legend>
        {TYPES.map((k) => (
          <label key={k} className="radio">
            <input
              type="radio" name="annotator_type" value={k} checked={type === k}
              onChange={() => { setType(k); if (k !== 'other') setOther('') }}
            />
            <span>{t.options[k]}</span>
          </label>
        ))}
      </fieldset>
      {type === 'other' && (
        <div className="other">
          <label htmlFor="bg-other">{t.other_label}</label>
          <input id="bg-other" type="text" maxLength={50} value={other} onChange={(e) => setOther(e.target.value)} />
          <p className="warning" role="note"><span aria-hidden="true">⚠ </span>{t.other_warning}</p>
        </div>
      )}
      {error && <p className="error" role="alert">{c.save_error}</p>}
      <div className="actions">
        <button type="button" className="primary" onClick={submit} disabled={!type || busy}>
          {busy ? c.saving : t.button} {!busy && <span aria-hidden="true">→</span>}
        </button>
      </div>
    </section>
  )
}
