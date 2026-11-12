import { useEffect, useRef, useState } from 'react'
import { fill, type HintMetric, type LanguagePref, type RubricContent, type RubricMetric, type UiLang } from '../lib/config'
import { assignBatch, fetchBriefingMinSeconds, getBriefingProgress, saveBriefingView } from '../lib/session'

/**
 * K4b Briefing (SRS v1.4 FR-BRF, D-39, D-40).
 * One page per metric (fixed order), shown before the first item of every batch.
 * "Sonraki" is locked until the page has been visible for the minimum time (admin parameter).
 * Önceki is allowed; a page unlocked once stays unlocked. Each forward move is stored (save_briefing_view).
 * On reload the pages already completed for this batch are skipped (get_briefing_progress).
 */

const DEFAULTS = {
  step: 'Adım 3 / 4: Metrik bilgilendirmesi',
  title: 'Metrik bilgilendirmesi',
  lede: 'Değerlendirmeye başlamadan önce her metriğin açıklamalarını ve örneklerini inceleyiniz.',
  progress: 'Metrik {n} / {total}',
  guidance_heading: 'Puanlama Açıklamaları ve Örnek Gereksinimler',
  hints_heading: 'Metriğe ait kurallar ve örnek gereksinimler',
  hint_rules: 'Kurallar',
  hint_bad: 'Uyumsuz Gereksinim Örnekleri (Score=0)',
  hint_partial: 'Kısmen Uyumlu Gereksinim Örnekleri (Score=1)',
  hint_good: 'Uyumlu Gereksinim Örnekleri (Score=2)',
  hint_rationale: 'Gerekçe (0 ve 1 puanları)',
  block_tr: 'Türkçe',
  block_en: 'English',
  wait: '{seconds} saniye sonra yeni sayfaya geçebilirsiniz',
  prev_button: '← Önceki',
  next_button: 'Sonraki',
  start_button: 'Değerlendirmeye başla',
}

export default function Briefing({ config, sessionId, language, onDone }: {
  config: RubricContent
  sessionId: string
  language: LanguagePref | null
  onDone: () => void
}) {
  const t = { ...DEFAULTS, ...(config.briefing?.tr ?? {}) }
  const metrics = config.metrics
  const pref: LanguagePref = language ?? 'TR'
  const langs: UiLang[] = pref === 'EN' ? ['en'] : pref === 'BOTH' ? ['tr', 'en'] : ['tr']

  const [batchId, setBatchId] = useState<string | null>(null)
  const [minSeconds, setMinSeconds] = useState(10)
  const [page, setPage] = useState(0)
  const [unlocked, setUnlocked] = useState<Set<number>>(() => new Set())
  const [elapsed, setElapsed] = useState(0) // visible seconds on the current page
  const [loaded, setLoaded] = useState(false)
  const [error, setError] = useState(false)
  const [saving, setSaving] = useState(false)
  const visibleMs = useRef(0)
  const shownAt = useRef<number | null>(null)

  // Load the batch (idempotent: returns the open batch), minimum time and the progress of this batch
  useEffect(() => {
    let alive = true
    ;(async () => {
      try {
        const [b, min] = await Promise.all([assignBatch(sessionId), fetchBriefingMinSeconds()])
        if (!alive) return
        setMinSeconds(min)
        if (b.status !== 'ok') { onDone(); return } // K5 shows the exhausted / max / ended message
        setBatchId(b.batch_id)
        const done = (await getBriefingProgress(sessionId, b.batch_id)) ?? []
        if (!alive) return
        if (done.length >= metrics.length) { onDone(); return }
        const idxs = metrics.map((m, i) => (done.includes(m.id) ? i : -1)).filter((i) => i >= 0)
        setUnlocked(new Set(idxs))
        const firstOpen = metrics.findIndex((m) => !done.includes(m.id))
        setPage(firstOpen < 0 ? 0 : firstOpen)
        setLoaded(true)
      } catch (e) {
        console.error(e)
        if (alive) setError(true)
      }
    })()
    return () => { alive = false }
  }, [sessionId]) // eslint-disable-line react-hooks/exhaustive-deps

  // Visible-time measurement per page (same rule as FR-QC-001)
  useEffect(() => {
    if (!loaded) return
    visibleMs.current = 0
    shownAt.current = document.visibilityState === 'visible' ? performance.now() : null
    setElapsed(0)
    const onVis = () => {
      if (document.visibilityState === 'visible') shownAt.current = performance.now()
      else if (shownAt.current !== null) { visibleMs.current += performance.now() - shownAt.current; shownAt.current = null }
    }
    document.addEventListener('visibilitychange', onVis)
    const tick = window.setInterval(() => {
      const running = shownAt.current !== null ? performance.now() - shownAt.current : 0
      setElapsed((visibleMs.current + running) / 1000)
    }, 250)
    window.scrollTo(0, 0)
    return () => {
      document.removeEventListener('visibilitychange', onVis)
      window.clearInterval(tick)
    }
  }, [page, loaded])

  const ready = unlocked.has(page) || elapsed >= minSeconds
  useEffect(() => {
    if (ready && !unlocked.has(page)) setUnlocked((s) => new Set(s).add(page))
  }, [ready, page, unlocked])

  if (error) {
    return (
      <main className="narrow"><section className="panel">
        <p className="err" role="alert">{config.common.tr.save_error}</p>
        <button type="button" className="btn btn-primary" onClick={() => window.location.reload()}>{config.common.tr.retry ?? '↻'}</button>
      </section></main>
    )
  }
  if (!loaded || !batchId) return <main className="narrow" aria-busy="true"><div className="spinner" /></main>

  const m: RubricMetric = metrics[page]
  const last = page === metrics.length - 1
  const remaining = Math.max(0, Math.ceil(minSeconds - elapsed))
  const hint: HintMetric | undefined = config.hints?.metrics?.find((h) => h.id === m.id)

  const next = async () => {
    if (!ready || saving) return
    const running = shownAt.current !== null ? performance.now() - shownAt.current : 0
    const seconds = Math.round(((visibleMs.current + running) / 1000) * 10) / 10
    setSaving(true)
    setError(false)
    try {
      await saveBriefingView(sessionId, batchId, m.id, pref, seconds, true)
      if (last) onDone()
      else setPage(page + 1)
    } catch (e) {
      console.error(e)
      setError(true)
    } finally {
      setSaving(false)
    }
  }

  return (
    <main className="annotate briefing">
      <div className="bf-progress" aria-live="polite">
        <span>{fill(t.progress, { n: String(page + 1), total: String(metrics.length) })}</span>
        <span className="bf-bar" aria-hidden="true">
          {metrics.map((x, i) => <span key={x.id} className={i <= page ? 'on' : ''} />)}
        </span>
      </div>
      <h1 className="bf-title">{t.title}</h1>
      <p className="lede">{t.lede}</p>

      <section className="panel bf-page">
        <h2 className="bf-metric">
          {m.name_tr} <span className="metric-en">/ {m.name_en}</span>
        </h2>

        {langs.map((lang) => (
          <div key={lang} className="bf-block" lang={lang}>
            {langs.length > 1 && <p className="bf-lang">{lang === 'tr' ? t.block_tr : t.block_en}</p>}
            <p className="question">{m.question[lang]}</p>

            {hint && (
              <div className="hint-panel">
                <h3 className="bf-h">{lang === 'en' ? 'Metric Guidance' : t.hints_heading}</h3>
                <h4>{lang === 'tr' ? t.hint_rules : 'Rules'}</h4>
                <ol>{hint.rules[lang].map((r, i) => <li key={i}>{r}</li>)}</ol>
                <h4>{lang === 'tr' ? t.hint_bad : 'Non-Compliant Sample Requirements (Score=0)'}</h4>
                <ol>{hint.bad[lang].map((r, i) => <li key={i}>{r}</li>)}</ol>
                {hint.partial?.[lang]?.length ? (
                  <>
                    <h4>{lang === 'tr' ? t.hint_partial : 'Partially Compliant Sample Requirements (Score=1)'}</h4>
                    <ol>{hint.partial[lang].map((r, i) => <li key={i}>{r}</li>)}</ol>
                  </>
                ) : null}
                <h4>{lang === 'tr' ? t.hint_good : 'Compliant Sample Requirements (Score=2)'}</h4>
                <ol>{hint.good[lang].map((r, i) => <li key={i}>{r}</li>)}</ol>
                {hint.rationale?.[lang]?.length ? (
                  <>
                    <h4>{lang === 'tr' ? t.hint_rationale : 'Rationale for 0 and 1 scores'}</h4>
                    <ol className="rationale">{hint.rationale[lang].map((r, i) => <li key={i}>{r}</li>)}</ol>
                  </>
                ) : null}
              </div>
            )}

            <div className="details-panel">
              <h3 className="bf-h">{lang === 'en' ? 'Scoring Guidance' : t.guidance_heading}</h3>
              <p>{m.guidance[lang]}</p>
              <dl>
                {(['0', '1', '2'] as const).map((k) => {
                  const sample = m.samples?.find((s) => s.score === Number(k) && (lang === 'en' ? s.text_en : s.text))
                  const sampleText = sample ? (lang === 'en' ? sample.text_en : sample.text) : null
                  const reason = sample ? (lang === 'en' ? sample.reason_en : sample.reason_tr) : null
                  return (
                    <div key={k}>
                      <dt><b>{k}</b> {config.scale[k].label[lang]}</dt>
                      <dd>{m.anchors[k][lang]}</dd>
                      {sampleText && (
                        <dd className="sample">“{sampleText}”{reason && <span className="muted"> — {reason}</span>}</dd>
                      )}
                    </div>
                  )
                })}
              </dl>
            </div>
          </div>
        ))}
      </section>

      <div className="navrow bf-nav">
        {page > 0 ? (
          <button type="button" className="btn btn-quiet" disabled={saving} onClick={() => setPage(page - 1)}>{t.prev_button}</button>
        ) : <span />}
        <div className="bf-next">
          {!ready && <p className="muted" role="status">{fill(t.wait, { seconds: String(remaining) })}</p>}
          <button type="button" className="btn btn-primary" disabled={!ready || saving} onClick={next}>
            {saving ? config.common.tr.saving : last ? t.start_button : t.next_button}
          </button>
        </div>
      </div>
    </main>
  )
}
