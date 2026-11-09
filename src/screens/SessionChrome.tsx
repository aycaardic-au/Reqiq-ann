import { useEffect, useRef, type ReactNode } from 'react'
import type { SessionBarTexts } from '../lib/config'

/** Top bar with step label (and later progress) + footer "Oturumu sonlandır" (NFR-ETH-002). */
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

export function EndSession({ t, onEnd }: { t: SessionBarTexts; onEnd: () => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  return (
    <>
      <div className="foot"><button type="button" className="link" onClick={() => ref.current?.showModal()}>{t.end_link}</button></div>
      <dialog ref={ref} aria-labelledby="end-title">
        <form method="dialog" className="dlg">
          <h2 id="end-title">{t.end_confirm_title}</h2>
          <p>{t.end_confirm_text}</p>
          <div className="dlg-actions">
            <button value="cancel" className="btn btn-quiet">{t.end_confirm_cancel}</button>
            <button type="button" className="btn btn-primary" onClick={() => { ref.current?.close(); onEnd() }}>{t.end_confirm_ok}</button>
          </div>
        </form>
      </dialog>
    </>
  )
}

export function Ended({ t, onRestart }: { t: SessionBarTexts; onRestart: () => void }) {
  useEffect(() => { window.scrollTo(0, 0) }, [])
  return (
    <main className="narrow">
      <section className="panel">
        <h1>{t.ended_title}</h1>
        <p className="lede">{t.ended_body}</p>
        <button type="button" className="btn btn-primary" onClick={onRestart}>{t.ended_button}</button>
      </section>
    </main>
  )
}
