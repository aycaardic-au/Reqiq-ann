import type { WelcomeTexts } from '../lib/config'

/** [2] Welcome (FR-WEL-001..004). Single Continue button; no back navigation. */
export default function Welcome({ t, onContinue }: { t: WelcomeTexts; onContinue: () => void }) {
  return (
    <section className="card" aria-labelledby="welcome-title">
      <h1 id="welcome-title" className="title">{t.title}</h1>
      {t.body.split(/\n\s*\n/).map((p, i) => <p key={i}>{p}</p>)}
      <div className="actions">
        <button type="button" className="primary" onClick={onContinue} autoFocus>
          {t.button} <span aria-hidden="true">→</span>
        </button>
      </div>
    </section>
  )
}
