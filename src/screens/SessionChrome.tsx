import { useEffect, useRef, useState, type ReactNode } from 'react'
import type { CommonTexts, SessionBarTexts } from '../lib/config'

/** Top bar with step label (and progress on K5). */
export function TopBar({ appName, step, right }: { appName: string; step: string; right?: ReactNode }) {
  return (
    <header className="top">
      <div className="top-in">
        <span className="appname">{appName}</span>
        <span className="stepnow">{step}</span>
        {right}
      </div>
    </header>
  )
}

export type EndChoice = 'pause' | 'end' | 'withdraw' | 'closed'

/**
 * Footer link "Ara ver / Oturumu sonlandır" (NFR-ETH-002, D-32).
 * With a stored session: pause, end and keep answers, or end and delete answers.
 * Before the session exists (K3): a simple confirmation.
 */
export function EndSession({ t, c, hasSession, onChoose }: {
  t: SessionBarTexts; c: CommonTexts; hasSession: boolean; onChoose: (choice: EndChoice) => Promise<void>
}) {
  const ref = useRef<HTMLDialogElement>(null)
  const [choice, setChoice] = useState<EndChoice | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(false)
  const open = () => { setChoice(hasSession ? null : 'end'); setError(false); ref.current?.showModal() }
  const confirm = async () => {
    if (!choice) return
    setBusy(true); setError(false)
    try { await onChoose(choice); ref.current?.close() } catch (e) { console.error(e); setError(true) } finally { setBusy(false) }
  }
  const opts: [EndChoice, string, string][] = [
    ['pause', t.opt_pause, t.opt_pause_hint],
    ['end', t.opt_end, t.opt_end_hint],
    ['withdraw', t.opt_withdraw, t.opt_withdraw_hint],
  ]
  return (
    <>
      <div className="foot"><button type="button" className="link" onClick={open}>{t.end_link}</button></div>
      <dialog ref={ref} aria-labelledby="end-title">
        <form method="dialog" className="dlg">
          <h2 id="end-title">{t.end_confirm_title}</h2>
          {hasSession ? (
            <>
              <p className="muted">{t.end_confirm_text}</p>
              {opts.map(([k, label, hint]) => (
                <label key={k} className={`choice${choice === k ? ' on' : ''}${k === 'withdraw' ? ' danger' : ''}`}>
                  <input type="radio" name="endchoice" checked={choice === k} onChange={() => setChoice(k)} />
                  <span><b>{label}</b><br /><span className="muted">{hint}</span></span>
                </label>
              ))}
            </>
          ) : <p>{t.end_confirm_simple}</p>}
          {error && <p className="err" role="alert">{c.save_error}</p>}
          <div className="dlg-actions">
            <button value="cancel" className="btn btn-quiet" disabled={busy}>{t.end_confirm_cancel}</button>
            <button type="button" className={`btn ${choice === 'withdraw' ? 'btn-danger' : 'btn-primary'}`}
              disabled={!choice || busy} onClick={confirm}>{busy ? c.saving : t.end_confirm_ok}</button>
          </div>
        </form>
      </dialog>
    </>
  )
}

export function Ended({ title, body, button, onRestart }: { title: string; body: string; button: string; onRestart: () => void }) {
  useEffect(() => { window.scrollTo(0, 0) }, [])
  return (
    <main className="narrow">
      <section className="panel">
        <h1>{title}</h1>
        <p className="lede">{body}</p>
        <button type="button" className="btn btn-primary" onClick={onRestart}>{button}</button>
      </section>
    </main>
  )
}
