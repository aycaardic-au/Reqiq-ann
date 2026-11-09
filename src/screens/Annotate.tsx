import { useEffect, useMemo, useRef, useState } from 'react'
import { fill, rubricLangFor, type RubricContent, type RubricMetric } from '../lib/config'
import type { BatchItem, MetricScore } from '../lib/session'

type Draft = Record<string, MetricScore>

const toDraft = (scores: MetricScore[]): Draft => Object.fromEntries(scores.map((s) => [s.metric_id, { ...s }]))
const isDone = (d: Draft | undefined, n: number) =>
  !!d && Object.values(d).filter((s) => s.cannot_assess || s.score !== null).length === n

/**
 * K5 Değerlendirme (FR-ANN-001..011, D-26, D-28).
 * One requirement per page; six metrics; hint panel; back navigation within the open batch.
 */
export default function Annotate({
  config, items, onSave, onFinish, onProgress,
}: {
  config: RubricContent
  items: BatchItem[]
  onSave: (item: BatchItem, scores: MetricScore[], seconds: number) => Promise<void>
  onFinish: () => Promise<void>
  onProgress: (done: number, total: number) => void
}) {
  const t = config.annotate.tr
  const metrics = config.metrics
  const [drafts, setDrafts] = useState<Record<number, Draft>>(() =>
    Object.fromEntries(items.map((it) => [it.batch_item_id, toDraft(it.scores)])))
  const [saved, setSaved] = useState<Set<number>>(() =>
    new Set(items.filter((it) => it.scores.length === metrics.length).map((it) => it.batch_item_id)))
  const [idx, setIdx] = useState(() => {
    const first = items.findIndex((it) => it.scores.length < metrics.length)
    return first === -1 ? items.length - 1 : first
  })
  const [tried, setTried] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(false)
  const shownAt = useRef(0)

  const item = items[idx]
  const lang = rubricLangFor(item.language_tag)
  const draft = drafts[item.batch_item_id] ?? {}

  useEffect(() => {
    shownAt.current = performance.now()
    window.scrollTo(0, 0)
  }, [idx])

  useEffect(() => { onProgress(saved.size, items.length) }, [saved, items.length, onProgress])

  const setMetric = (id: string, patch: Partial<MetricScore>) => {
    setDrafts((d) => {
      const cur = d[item.batch_item_id]?.[id] ?? { metric_id: id, score: null, cannot_assess: false, note: null }
      return { ...d, [item.batch_item_id]: { ...d[item.batch_item_id], [id]: { ...cur, ...patch } } }
    })
  }

  const complete = isDone(draft, metrics.length)
  const last = idx === items.length - 1
  const finalSave = items.every((it) => it.batch_item_id === item.batch_item_id || saved.has(it.batch_item_id))

  const save = async () => {
    setTried(true)
    if (!complete) return
    setBusy(true)
    setError(false)
    try {
      const seconds = (performance.now() - shownAt.current) / 1000
      await onSave(item, metrics.map((m) => draft[m.id]), Math.round(seconds * 10) / 10)
      const nextSaved = new Set(saved).add(item.batch_item_id)
      setSaved(nextSaved)
      setTried(false)
      if (nextSaved.size === items.length) { await onFinish(); return }
      setIdx(!last ? idx + 1 : items.findIndex((it) => !nextSaved.has(it.batch_item_id)))
    } catch (e) {
      console.error(e)
      setError(true)
    } finally {
      setBusy(false)
    }
  }

  return (
    <main className="annotate">
      <section className="req" aria-labelledby="req-label">
        <div id="req-label" className="req-label">
          {fill(t.requirement_label_lang, { lang: t.lang_names[item.language_tag] })} · {idx + 1}/{items.length}
        </div>
        <p className="req-text" lang={lang}>{item.text}</p>
      </section>

      {metrics.map((m, i) => (
        <MetricBlock
          key={`${item.batch_item_id}-${m.id}`}
          n={i + 1}
          m={m}
          lang={lang}
          config={config}
          value={draft[m.id]}
          showError={tried && !(draft[m.id]?.cannot_assess || (draft[m.id]?.score ?? null) !== null)}
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
  const hint = useMemo(() => config.hints.metrics.find((h) => h.id === m.id), [config, m.id])
  const [hintOpen, setHintOpen] = useState(false)
  const [noteOpen, setNoteOpen] = useState(Boolean(value?.note))
  const name = lang === 'en' ? m.name_en : m.name_tr
  const group = `${m.id}-score`

  return (
    <fieldset className={`metric${showError ? ' missing' : ''}`}>
      <legend><span className="n">{n}.</span>{name}</legend>
      {m.partial_scope_note && <p className="partial" lang={lang}>{rt.partial_note}</p>}
      <p className="question" lang={lang}>{m.question[lang]}</p>
      <p className="guidance" lang={lang}>{m.guidance[lang]}</p>

      <div className="scores" role="radiogroup" aria-label={name}>
        {(['0', '1', '2'] as const).map((k) => {
          const on = !value?.cannot_assess && value?.score === Number(k)
          return (
            <label key={k} className={`score${on ? ' on' : ''}`}>
              <input type="radio" name={group} checked={on}
                onChange={() => onChange({ score: Number(k), cannot_assess: false })} />
              <span className="score-head" lang={lang}><b>{k}</b> {config.scale[k].label[lang]}</span>
              <span className="anchor" lang={lang}>{m.anchors[k][lang]}</span>
            </label>
          )
        })}
        <label className={`score ca${value?.cannot_assess ? ' on' : ''}`}>
          <input type="radio" name={group} checked={Boolean(value?.cannot_assess)}
            onChange={() => onChange({ score: null, cannot_assess: true })} />
          <span className="score-head" lang={lang}>{rt.cannot_assess}</span>
        </label>
      </div>

      <div className="metric-tools">
        <button type="button" className="link" aria-expanded={hintOpen} onClick={() => setHintOpen(!hintOpen)}>
          {hintOpen ? t.hint_hide : t.hint_button}
        </button>
        {!noteOpen && <button type="button" className="link" onClick={() => setNoteOpen(true)}>{t.note_toggle}</button>}
      </div>

      {hintOpen && hint && (
        <div className="hint-panel" lang={lang}>
          <h4>{t.hint_rules}</h4>
          <ol>{hint.rules[lang].map((r, i) => <li key={i}>{r}</li>)}</ol>
          <h4>{t.hint_bad}</h4>
          <ol className="samples bad">{hint.bad[lang].map((r, i) => <li key={i}>{r}</li>)}</ol>
          <h4>{t.hint_good}</h4>
          <ol className="samples good">{hint.good[lang].map((r, i) => <li key={i}>{r}</li>)}</ol>
        </div>
      )}

      {noteOpen && (
        <textarea className="note" maxLength={500} rows={2} placeholder={t.note_placeholder}
          value={value?.note ?? ''} onChange={(e) => onChange({ note: e.target.value })} />
      )}
    </fieldset>
  )
}
