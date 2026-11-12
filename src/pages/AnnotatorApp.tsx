import { useCallback, useEffect, useState } from 'react'
import { fill, loadActiveConfig, UI_LANG, type RubricContent } from '../lib/config'
import { clearLocal, consumeResetHash, INITIAL_FLOW, readFlow, writeFlow, type FlowState } from '../lib/flowState'
import { createSession, endSession, finishSession, readSession, saveBackground, withdrawSession } from '../lib/session'
import ConsentPage from '../screens/ConsentPage'
import InfoForm from '../screens/InfoForm'
import Intro from '../screens/Intro'
import AnnotateStep from '../screens/AnnotateStep'
import Briefing from '../screens/Briefing'
import { BatchComplete, ThankYou } from '../screens/BatchEnd'
import { Ended, EndSession, TopBar, type EndChoice } from '../screens/SessionChrome'

/**
 * Annotator flow (D-24):
 * K1 Giriş + Onam → K3 Bilgi formu → K4 Yönerge → K5 Değerlendirme → K6 Set tamamlandı → Teşekkürler
 * Implemented: K1–K6 and Teşekkürler. Screen texts Turkish (D-23), all from rubric_config (FR-CFG-TXT-001).
 */
export default function AnnotatorApp() {
  const [config, setConfig] = useState<RubricContent | null>(null)
  const [failed, setFailed] = useState(false)
  const [loadTick, setLoadTick] = useState(0)
  const [ended, setEnded] = useState<EndChoice | null>(null)
  const [flow, setFlow] = useState<FlowState>(() => {
    if (consumeResetHash()) return INITIAL_FLOW // /#/reset: start again at K1 (FR-SES-010)
    const f = readFlow()
    // Steps after the form need the stored session; without it, start again (FR-SES-004).
    return f.step !== 'consent' && f.step !== 'form' && !readSession() ? INITIAL_FLOW : f
  })
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null)
  const onProgress = useCallback((done: number, total: number) => setProgress({ done, total }), [])

  useEffect(() => {
    loadActiveConfig().then(setConfig).catch((e) => {
      console.error(e)
      setFailed(true)
    })
  }, [loadTick])

  // /#/reset typed in a tab that is already open only changes the hash: no reload, so handle it here too.
  useEffect(() => {
    const onHash = () => {
      if (window.location.hash.replace(/\/+$/, '') !== '#/reset') return
      clearLocal()
      window.history.replaceState(null, '', `${window.location.pathname}${window.location.search}#/`)
      setEnded(null)
      setProgress(null)
      setFlow(INITIAL_FLOW)
      window.scrollTo(0, 0)
    }
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [])

  useEffect(() => {
    if (!config) return
    document.documentElement.lang = UI_LANG
    document.title = config.app_name[UI_LANG]
  }, [config])

  const update = (s: FlowState) => {
    writeFlow(s)
    setFlow(s)
    window.scrollTo(0, 0)
  }

  if (failed) {
    // FR-CFG-TXT-002: the only hard-coded text — shown when the configuration cannot be loaded.
    return (
      <main className="narrow">
        <section className="panel" role="alert">
          <p lang="tr">Araç şu anda yüklenemiyor. Lütfen daha sonra tekrar deneyin.</p>
          <p lang="en">The tool cannot be loaded at the moment. Please try again later.</p>
          <button type="button" className="btn btn-primary" onClick={() => { setFailed(false); setLoadTick(loadTick + 1) }}>Tekrar dene / Try again</button>
        </section>
      </main>
    )
  }
  if (!config) return <main className="narrow" aria-busy="true"><div className="spinner" /></main>

  const bar = config.session_bar.tr
  const appName = config.app_name[UI_LANG]
  const choose = async (choice: EndChoice) => {
    const sid = readSession()?.session_id
    if (choice === 'pause') { setEnded('pause'); return }
    if (sid) await (choice === 'withdraw' ? withdrawSession(sid) : endSession(sid))
    clearLocal(); setFlow(INITIAL_FLOW); setEnded(choice)
  }
  const end = <EndSession t={bar} c={config.common.tr} hasSession={Boolean(readSession())} onChoose={choose} />

  if (ended === 'pause') return <Ended title={bar.paused_title} body={bar.paused_body} button={bar.paused_button} onRestart={() => setEnded(null)} />
  if (ended) {
    return <Ended title={bar.ended_title}
      body={ended === 'withdraw' ? bar.withdrawn_body : ended === 'closed' ? (config.common.tr.session_closed ?? bar.ended_body) : bar.ended_body}
      button={bar.ended_button} onRestart={() => setEnded(null)} />
  }

  switch (flow.step) {
    case 'consent':
      return <ConsentPage t={config.consent.tr} d={config.declined.tr} onAgree={() => update({ ...flow, step: 'form' })} />
    case 'form':
      return (
        <>
          <TopBar appName={appName} step={config.form.tr.step} />
          <InfoForm
            t={config.form.tr}
            c={config.common.tr}
            onSubmit={async (lang, type, other) => {
              const s = await createSession(lang, config.ui_texts_version)
              await saveBackground(s.session_id, type, other)
              update({ step: 'intro', language: lang })
            }}
          />
          {end}
        </>
      )
    case 'intro':
      return (
        <>
          <TopBar appName={appName} step={config.intro.tr.step} />
          <Intro t={config.intro.tr} config={config} onStart={() => update({ ...flow, step: 'briefing' })} />
          {end}
        </>
      )
    case 'briefing':
      // K4b (SRS FR-BRF): one page per metric before the first item of every batch
      return (
        <>
          <TopBar appName={appName} step={(config.briefing?.tr as { step?: string } | undefined)?.step ?? 'Adım 3 / 4: Metrik bilgilendirmesi'} />
          <Briefing config={config} sessionId={readSession()!.session_id} language={flow.language}
            onDone={() => update({ ...flow, step: 'annotate' })} />
          {end}
        </>
      )
    case 'annotate': {
      const t = config.annotate.tr
      return (
        <>
          <TopBar appName={appName} step={t.step}
            right={progress && (
              <span className="progress" aria-live="polite">
                <span className="bar"><span style={{ width: `${(100 * progress.done) / Math.max(1, progress.total)}%` }} /></span>
                {fill(t.progress, { done: String(progress.done), total: String(progress.total) })}
              </span>
            )} />
          <AnnotateStep
            config={config}
            sessionId={readSession()!.session_id}
            onProgress={onProgress}
            onBatchDone={(r) => update({ ...flow, step: 'batch_complete',
              summary: { batchCount: r.batch_count, batchNumber: r.batch_number, total: r.total, canContinue: r.can_continue } })}
            onNoMore={() => update({ ...flow, step: 'thankyou' })}
            onEnded={() => { clearLocal(); setFlow(INITIAL_FLOW); setEnded('closed') }}
          />
          {end}
        </>
      )
    }
    case 'batch_complete':
      return (
        <BatchComplete
          t={config.batch_complete.tr}
          batchCount={flow.summary?.batchCount ?? 0}
          batchNumber={flow.summary?.batchNumber}
          total={flow.summary?.total ?? 0}
          canContinue={flow.summary?.canContinue ?? false}
          onContinue={() => { setProgress(null); update({ ...flow, step: 'briefing' }) }}
          onStop={() => update({ ...flow, step: 'thankyou' })}
        />
      )
    case 'thankyou': {
      const sid = readSession()!.session_id
      return (
        <ThankYou
          t={config.thankyou.tr}
          c={config.common.tr}
          total={flow.summary?.total ?? 0}
          sessionId={sid}
          onSubmit={async (comment) => { await finishSession(sid, comment); clearLocal() }}
        />
      )
    }
  }
}
