import { useState } from 'react'
import type { ConsentTexts, DeclinedTexts } from '../lib/config'

/** K1 Giriş + Onam (FR-ONB-002, FR-ONB-005) and K2 Katılmama (NFR-ETH-002). Nothing is stored here. */
export default function ConsentPage({ t, d, onAgree }: { t: ConsentTexts; d: DeclinedTexts; onAgree: () => void }) {
  const [choice, setChoice] = useState<'yes' | 'no' | null>(null)
  const [error, setError] = useState(false)
  const [declined, setDeclined] = useState(false)

  if (declined) {
    return (
      <main className="narrow">
        <section className="panel">
          <h1>{d.title}</h1>
          <p className="lede">{d.body}</p>
          <button type="button" className="btn btn-primary" onClick={() => { setDeclined(false); setChoice(null) }}>
            {d.button}
          </button>
        </section>
      </main>
    )
  }

  const start = (e: React.FormEvent) => {
    e.preventDefault()
    if (!choice) { setError(true); return }
    if (choice === 'no') { setDeclined(true); return }
    onAgree()
  }

  return (
    <main className="welcome">
      <div className="wleft">
        <h1>{t.title}</h1>
        <p className="lede">{t.lede}</p>
        <ol className="steps" aria-label="Aşamalar">
          {t.steps.map((s, i) => <li key={i}><b>{i + 1}</b><span>{s}</span></li>)}
        </ol>
        <section className="consent-box" tabIndex={0} aria-label={t.form_title}>
          <h2>{t.form_title}</h2>
          {t.form_sections.map((s, i) => (
            <div key={i}>
              {s.heading && <h3>{s.heading}</h3>}
              {s.paragraphs.map((p, j) => <p key={j}>{p}</p>)}
            </div>
          ))}
        </section>
        <p className="contact">{t.contact}</p>
      </div>
      <form className="start panel" onSubmit={start} noValidate>
        <fieldset>
          <legend className="label">{t.choice_title}</legend>
          {(['yes', 'no'] as const).map((v) => (
            <label key={v} className={`choice${choice === v ? ' on' : ''}`}>
              <input type="radio" name="consent" value={v} checked={choice === v}
                onChange={() => { setChoice(v); setError(false) }} />
              <span>{v === 'yes' ? t.agree : t.decline}</span>
            </label>
          ))}
        </fieldset>
        {error && <p className="err" role="alert">{t.choice_required}</p>}
        <button type="submit" className="btn btn-primary btn-block">{t.start_button}</button>
      </form>
    </main>
  )
}
