import { useState } from 'react'
import { fill, type BatchCompleteTexts, type CommonTexts, type ThankYouTexts } from '../lib/config'

/** K6 Set tamamlandı (FR-BTH-001/002, ADD-02 §5). */
export function BatchComplete({
  t, batchCount, total, canContinue, onContinue, onStop,
}: {
  t: BatchCompleteTexts; batchCount: number; total: number; canContinue: boolean
  onContinue: () => void; onStop: () => void
}) {
  return (
    <main className="narrow">
      <section className="panel">
        <h1>{t.title}</h1>
        <p className="lede">{fill(t.body, { batch_count: String(batchCount), total: String(total) })}</p>
        {canContinue && <p>{t.question}</p>}
        <div className="dlg-actions spread">
          <button type="button" className="btn btn-quiet" onClick={onStop}>{t.stop_button}</button>
          {canContinue && <button type="button" className="btn btn-primary" onClick={onContinue}>{t.continue_button}</button>}
        </div>
      </section>
    </main>
  )
}

/** Teşekkürler (FR-ANN-012 revised, ADD-02 §6): session ID, total, optional comment. */
export function ThankYou({
  t, c, total, sessionId, onSubmit,
}: {
  t: ThankYouTexts; c: CommonTexts; total: number; sessionId: string; onSubmit: (comment: string) => Promise<void>
}) {
  const [comment, setComment] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(false)
  const [closed, setClosed] = useState(false)

  if (closed) {
    return <main className="narrow"><section className="panel"><h1>{t.title}</h1><p className="lede">{t.closed}</p></section></main>
  }

  const submit = async () => {
    setBusy(true)
    setError(false)
    try {
      await onSubmit(comment)
      setClosed(true)
    } catch (e) {
      console.error(e)
      setError(true)
      setBusy(false)
    }
  }

  return (
    <main className="narrow">
      <section className="panel">
        <h1>{t.title}</h1>
        <p className="lede">{fill(t.body, { n: String(total) })}</p>
        <p>{t.session_label} <code className="sid">{sessionId}</code></p>
        <p className="hint">{t.session_note}</p>
        <label htmlFor="comment" className="label">{t.comment_label}</label>
        <textarea id="comment" className="note" rows={4} maxLength={500} placeholder={t.comment_placeholder}
          value={comment} onChange={(e) => setComment(e.target.value)} />
        <p className="hint">{t.comment_max} · {comment.length}/500</p>
        {error && <p className="err" role="alert">{c.save_error}</p>}
        <div className="submitrow">
          <button type="button" className="btn btn-primary" disabled={busy} onClick={submit}>{busy ? c.saving : t.button}</button>
        </div>
      </section>
    </main>
  )
}
