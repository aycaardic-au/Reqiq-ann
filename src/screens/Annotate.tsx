import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { fill, rubricLangFor, type RubricContent, type RubricMetric } from '../lib/config'
import { isSessionClosed, type BatchItem, type MetricScore } from '../lib/session'

type Draft = Record<string, MetricScore>

const DRAFT_KEY = 'reqiq_ann_drafts'
const toDraft = (scores: MetricScore[]): Draft => Object.fromEntries(scores.map((s) => [s.metric_id, { ...s }]))
const filled = (d: Draft | undefined) => (d ? Object.values(d).filter((s) => s.score !== null).length : 0)
const sameDraft = (a: Draft | undefined, b: Draft | undefined) => JSON.stringify(a ?? {}) === JSON.stringify(b ?? {})

/** NFR-REL-005: unsaved selections survive a reload or crash (kept per batch item in localStorage). */
function loadDrafts(): Record<number, Draft> {
  try { return JSON.parse(localStorage.getItem(DRAFT_KEY) ?? '{}') as Record<number, Draft> } catch { return {} }
}
function storeDrafts(d: Record<number, Draft>): void {
  try { localStorage.setItem(DRAFT_KEY, JSON.stringify(d)) } catch { /* storage unavailable */ }
}

/**
 * K5 Değerlendirme (FR-ANN-001..011, D-26, D-28, D-33).
 * One requirement per page; six metrics; details and hint panels; back navigation within the open batch;
 * keyboard shortcuts (UI-004); visible-time measurement (FR-QC-001); draft persistence (NFR-REL-005).
 */
export default function Annotate({
  config, items, onSave, onFinish, onProgress, onClosed,
}: {
  config: RubricContent
  items: BatchItem[]
  onSave: (item: BatchItem, scores: MetricScore[], seconds: number) => Promise<void>
  onFinish: () => Promise<void>
  onProgress: (done: number, total: number) => void
  onClosed: () => void
}) {
  const t = config.annotate.tr
  const metrics = config.metrics
  const [serverDrafts, setServerDrafts] = useState<Record<number, Draft>>(() => Object.fromEntries(items.map((it) => [it.batch_item_id, toDraft(it.scores)])))
  const [drafts, setDrafts] = useState<Record<number, Draft>>(() => {
    const local = loadDrafts()
    const merged: Record<number, Draft> = Object.fromEntries(items.map((it) => [it.batch_item_id, toDraft(it.scores)]))
    for (const it of items) if (local[it.batch_item_id]) merged[it.batch_item_id] = local[it.batch_item_id]
    return merged
  })
  const [saved, setSaved] = useState<Set<number>>(() =>
    new Set(items.filter((it) => it.scores.length === metrics.length).map((it) => it.batch_item_id)))
  const [idx, setIdx] = useState(() => {
    const first = items.findIndex((it) => it.scores.length < metrics.length)
    return first === -1 ? items.length - 1 : first
  })
  const [tried, setTried] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(false)
  const visibleMs = useRef(0)
  const shownAt = useRef<number | null>(null)
  const reqRef = useRef<HTMLElement>(null)

  const item = items[idx]
  const lang = rubricLangFor(item.language_tag)
  const draft = drafts[item.batch_item_id] ?? {}
  const dirty = !sameDraft(draft, serverDrafts[item.batch_item_id])
  const restored = dirty && filled(draft) > 0 && !tried

  // FR-QC-001: count only the time the page is visible
  useEffect(() => {
    visibleMs.current = 0
    shownAt.current = document.visibilityState === 'visible' ? performance.now() : null
    const onVis = () => {
      if (document.visibilityState === 'visible') shownAt.current = performance.now()
      else if (shownAt.current !== null) { visibleMs.current += performance.now() - shownAt.current; shownAt.current = null }
    }
    document.addEventListener('visibilitychange', onVis)
    window.scrollTo(0, 0)
    reqRef.current?.focus({ preventScroll: true })
    return () => document.removeEventListener('visibilitychange', onVis)
  }, [idx])

  useEffect(() => { storeDrafts(drafts) }, [drafts])
  useEffect(() => { onProgress(saved.size, items.length) }, [saved, items.length, onProgress])

  // Warn before leaving with unsaved selections on this item
  useEffect(() => {
    if (!dirty) return
    const h = (e: BeforeUnloadEvent) => { e.preventDefault() }
    window.addEventListener('beforeunload', h)
    return () => window.removeEventListener('beforeunload', h)
  }, [dirty])

  const setMetric = useCallback((id: string, patch: Partial<MetricScore>) => {
    setDrafts((d) => {
      const cur = d[item.batch_item_id]?.[id] ?? { metric_id: id, score: null, note: null }
      return { ...d, [item.batch_item_id]: { ...d[item.batch_item_id], [id]: { ...cur, ...patch } } }
    })
  }, [item.batch_item_id])

  const complete = filled(draft) === metrics.length
  const last = idx === items.length - 1
  const finalSave = items.every((it) => it.batch_item_id === item.batch_item_id || saved.has(it.batch_item_id))

  const save = async () => {
    setTried(true)
    if (!complete || busy) return
    setBusy(true)
    setError(false)
    try {
      const running = shownAt.current !== null ? performance.now() - shownAt.current : 0
      const seconds = Math.round(((visibleMs.current + running) / 1000) * 10) / 10
      const scores = metrics.map((m) => draft[m.id])
      await onSave(item, scores, seconds)
      setServerDrafts((sd) => ({ ...sd, [item.batch_item_id]: toDraft(scores) }))
      setDrafts((d) => { const n = { ...d }; delete n[item.batch_item_id]; n[item.batch_item_id] = toDraft(scores); return n })
      try { const l = loadDrafts(); delete l[item.batch_item_id]; storeDrafts(l) } catch { /* ignore */ }
      const nextSaved = new Set(saved).add(item.batch_item_id)
      setSaved(nextSaved)
      setTried(false)
      if (nextSaved.size === items.length) {
        try { localStorage.removeItem(DRAFT_KEY) } catch { /* ignore */ }
        await onFinish()
        return
      }
      setIdx(!last ? idx + 1 : items.findIndex((it) => !nextSaved.has(it.batch_item_id)))
    } catch (e) {
      console.error(e)
      if (isSessionClosed(e)) { onClosed(); return }
      setError(true)
    } finally {
      setBusy(false)
    }
  }

  return (
    <main className="annotate">
      <section className="req" aria-labelledby="req-label" ref={reqRef} tabIndex={-1}>
        <div id="req-label" className="req-label">
          <span>{t.requirement_title}</span>
          <span className="req-meta">{t.lang_names[item.language_tag]}</span>
        </div>
        <p className="req-text" lang={lang}>{item.text}</p>
      </section>

      {restored && t.draft_restored && <p className="notice" role="status">{t.draft_restored}</p>}
      {t.shortcut_hint && idx === 0 && <p className="muted shortcut">{t.shortcut_hint}</p>}

      {metrics.map((m, i) => (
        <MetricBlock
          key={`${item.batch_item_id}-${m.id}`}
          n={i + 1}
          m={m}
          lang={lang}
          config={config}
          value={draft[m.id]}
          showError={tried && (draft[m.id]?.score ?? null) === null}
          onChange={(p) => setMetric(m.id, p)}
        />
      ))}

      {tried && !complete && <p className="err" role="alert">{t.incomplete}</p>}
      {error && <p className="err" role="alert">{config.common.tr.save_error}</p>}
      <div className="navrow">
        <button type="button" className="btn btn-quiet" disabled={idx === 0 || busy} onClick={() => { setTried(false); setIdx(idx - 1) }}>
          ← {t.prev}
        </button>
        <button type="button" className="btn btn-primary" disabled={busy} onClick={save}>
          {busy ? config.common.tr.saving : finalSave ? t.finish : t.next}
        </button>
      </div>
    </main>
  )
}

function Bulb() {
  return (
    <svg className="bulb" width="16" height="16" viewBox="0 0 24 24" aria-hidden="true">
      <path d="M12 2a7 7 0 0 0-4.2 12.6c.7.6 1.2 1.4 1.2 2.4v.5h6V17c0-1 .5-1.8 1.2-2.4A7 7 0 0 0 12 2z" fill="#f7d65a" stroke="#a07d10" strokeWidth="1.2" />
      <rect x="9" y="18.5" width="6" height="1.8" rx=".9" fill="#a07d10" />
      <rect x="10" y="21" width="4" height="1.6" rx=".8" fill="#a07d10" />
    </svg>
  )
}

function MetricBlock({
  n, m, lang, config, value, showError, onChange,
}: {
  n: number
  m: RubricMetric
  lang: 'en' | 'tr'
  config: RubricContent
  value: MetricScore | undefined
  showError: boolean
  onChange: (p: Partial<MetricScore>) => void
}) {
  const t = config.annotate.tr
  const rt = config.annotate_rubric[lang]
  const hint = useMemo(() => config.hints?.metrics?.find((h) => h.id === m.id), [config, m.id])
  const [hintOpen, setHintOpen] = useState(false)
  const [detailsOpen, setDetailsOpen] = useState(false)
  const [noteOpen, setNoteOpen] = useState(Boolean(value?.note))
  const group = `${m.id}-score`
  const sampleText = (s: NonNullable<RubricMetric['samples']>[number]) => (lang === 'en' ? s.text_en ?? null : s.text)
  const sampleReason = (s: NonNullable<RubricMetric['samples']>[number]) => (lang === 'en' ? s.reason_en : s.reason_tr)

  // UI-004: 0/1/2 select a score, while focus is inside this metric
  const onKey = (e: React.KeyboardEvent) => {
    if ((e.target as HTMLElement).tagName === 'TEXTAREA' || e.ctrlKey || e.metaKey || e.altKey) return
    if (['0', '1', '2'].includes(e.key)) { onChange({ score: Number(e.key) }); e.preventDefault() }
  }

  return (
    <fieldset className={`metric${showError ? ' missing' : ''}`} onKeyDown={onKey}>
      <legend>
        <span className="metric-no">{fill(t.metric_label, { n: String(n) })}</span>
        <span className="metric-name">{m.name_tr} <span className="metric-en">/ {m.name_en}</span></span>
      </legend>
      <p className="question" lang={lang}>{m.question[lang]}</p>
      {m.partial_scope_note && <p className="partial" lang={lang}>{rt.partial_note}</p>}

      <div className="scores" role="radiogroup" aria-label={`${m.name_tr} / ${m.name_en}`}>
        {(['0', '1', '2'] as const).map((k) => {
          const on = value?.score === Number(k)
          return (
            <label key={k} className={`score${on ? ' on' : ''}`} title={m.anchors[k][lang]}>
              <input type="radio" name={group} checked={on}
                onChange={() => onChange({ score: Number(k) })} />
              <span className="score-head" lang={lang}><b>{k}</b> {config.scale[k].label[lang]}</span>
            </label>
          )
        })}
      </div>

      <div className="metric-tools">
        <button type="button" className="link" aria-expanded={detailsOpen} onClick={() => setDetailsOpen(!detailsOpen)}>
          {detailsOpen ? t.details_hide : t.details_button}
        </button>
        {hint && (
          <button type="button" className="link hint-link" aria-expanded={hintOpen} onClick={() => setHintOpen(!hintOpen)}>
            <Bulb />{hintOpen ? t.hint_hide : t.hint_button}
          </button>
        )}
        {!noteOpen && <button type="button" className="link" onClick={() => setNoteOpen(true)}>{t.note_toggle}</button>}
      </div>

      {detailsOpen && (
        <div className="details-panel" lang={lang}>
          <p>{m.guidance[lang]}</p>
          <dl>
            {(['0', '1', '2'] as const).map((k) => {
              const sample = m.samples?.find((s) => s.score === Number(k) && sampleText(s))
              return (
                <div key={k}>
                  <dt><b>{k}</b> {config.scale[k].label[lang]}</dt>
                  <dd>{m.anchors[k][lang]}</dd>
                  {sample && (
                    <dd className="sample">
                      <span className="sample-label">{t.sample_label ?? 'Örnek'}:</span> “{sampleText(sample)}”
                      {sampleReason(sample) && <span className="muted"> — {sampleReason(sample)}</span>}
                    </dd>
                  )}
                </div>
              )
            })}
          </dl>
        </div>
      )}

      {hintOpen && hint && (
        <div className="hint-panel" lang={lang}>
          <h4>{t.hint_rules}</h4>
          <ol>{hint.rules[lang].map((r, i) => <li key={i}>{r}</li>)}</ol>
          <h4>{t.hint_bad}</h4>
          <ol className="samples bad">{hint.bad[lang].map((r, i) => <li key={i}>{r}</li>)}</ol>
          {hint.partial?.[lang]?.length ? (
            <>
              <h4>{t.hint_partial ?? 'Kısmen uyumlu örnekler'}</h4>
              <ol className="samples mid">{hint.partial[lang].map((r, i) => <li key={i}>{r}</li>)}</ol>
            </>
          ) : null}
          <h4>{t.hint_good}</h4>
          <ol className="samples good">{hint.good[lang].map((r, i) => <li key={i}>{r}</li>)}</ol>
          {hint.rationale?.[lang]?.length ? (
            <>
              <h4>{t.hint_rationale ?? 'Puan gerekçeleri (0 ve 1)'}</h4>
              <ol className="rationale">{hint.rationale[lang].map((r, i) => <li key={i}>{r}</li>)}</ol>
            </>
          ) : null}
        </div>
      )}

      {noteOpen && (
        <textarea className="note" maxLength={500} rows={2} placeholder={t.note_placeholder} aria-label={`${t.note_placeholder} — ${m.name_tr}`}
          value={value?.note ?? ''} onChange={(e) => onChange({ note: e.target.value })} />
      )}
    </fieldset>
  )
}
