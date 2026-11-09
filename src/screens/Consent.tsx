import { useState } from 'react'
import type { CommonTexts, ConsentTexts } from '../lib/config'
import Paragraphs from './Paragraphs'

/**
 * [3] Consent (FR-ONB-002, FR-ONB-005, NFR-ETH-002).
 * Continue is enabled only after the checkbox is ticked. Declining records nothing.
 */
export default function Consent({ t, c, onAgree }: { t: ConsentTexts; c: CommonTexts; onAgree: () => Promise<void> }) {
  const [checked, setChecked] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(false)
  const [declined, setDeclined] = useState(false)

  if (declined) {
    return (
      <section className="card" aria-labelledby="declined-title">
        <h1 id="declined-title" className="title">{t.declined_title}</h1>
        <p>{t.declined_body}</p>
      </section>
    )
  }

  const agree = async () => {
    setBusy(true)
    setError(false)
    try {
      await onAgree()
    } catch (e) {
      console.error(e)
      setError(true)
      setBusy(false)
    }
  }

  return (
    <section className="card" aria-labelledby="consent-title">
      <h1 id="consent-title" className="title">{t.title}</h1>
      <Paragraphs text={t.body} />
      <label className="check">
        <input type="checkbox" checked={checked} onChange={(e) => setChecked(e.target.checked)} />
        <span>{t.checkbox}</span>
      </label>
      {error && <p className="error" role="alert">{c.save_error}</p>}
      <div className="actions spread">
        <button type="button" className="secondary" onClick={() => setDeclined(true)} disabled={busy}>
          {t.decline_button}
        </button>
        <button type="button" className="primary" onClick={agree} disabled={!checked || busy}>
          {busy ? c.saving : t.agree_button} {!busy && <span aria-hidden="true">→</span>}
        </button>
      </div>
    </section>
  )
}
