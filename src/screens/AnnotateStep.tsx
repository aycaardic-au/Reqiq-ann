import { useEffect, useState } from 'react'
import type { RubricContent } from '../lib/config'
import { assignBatch, completeBatch, isSessionClosed, saveScores, type BatchResult, type CompleteResult } from '../lib/session'
import Annotate from './Annotate'

/** Loads (or resumes) the session's batch, then runs K5. */
export default function AnnotateStep({
  config, sessionId, onProgress, onBatchDone, onNoMore, onEnded,
}: {
  config: RubricContent
  sessionId: string
  onProgress: (done: number, total: number) => void
  onBatchDone: (r: CompleteResult) => void
  onNoMore: () => void
  onEnded: () => void
}) {
  const t = config.annotate.tr
  const [batch, setBatch] = useState<BatchResult | null>(null)
  const [error, setError] = useState(false)
  const [attempt, setAttempt] = useState(0)

  useEffect(() => {
    let alive = true
    assignBatch(sessionId)
      .then((b) => { if (!alive) return; if (b.status === 'ended') onEnded(); else setBatch(b) })
      .catch((e) => { console.error(e); if (!alive) return; if (isSessionClosed(e)) onEnded(); else setError(true) })
    return () => { alive = false }
  }, [sessionId, attempt]) // eslint-disable-line react-hooks/exhaustive-deps

  if (error) {
    return (
      <main className="narrow"><section className="panel">
        <p className="err" role="alert">{config.common.tr.save_error}</p>
        <button type="button" className="btn btn-primary" onClick={() => { setError(false); setAttempt(attempt + 1) }}>{config.common.tr.retry ?? '↻'}</button>
      </section></main>
    )
  }
  if (!batch) return <main className="narrow" aria-busy="true"><p className="lede">{t.loading}</p><div className="spinner" /></main>
  if (batch.status !== 'ok') {
    return (
      <main className="narrow"><section className="panel">
        <p className="lede">{batch.status === 'exhausted' ? t.exhausted : t.max_reached}</p>
        <button type="button" className="btn btn-primary" onClick={onNoMore}>{t.to_thankyou}</button>
      </section></main>
    )
  }
  return (
    <Annotate
      key={batch.batch_id}
      config={config}
      items={batch.items}
      onProgress={onProgress}
      onSave={async (item, scores, seconds) => { await saveScores(sessionId, item.batch_item_id, scores, seconds) }}
      onFinish={async () => onBatchDone(await completeBatch(sessionId, batch.batch_id))}
      onClosed={onEnded}
    />
  )
}
