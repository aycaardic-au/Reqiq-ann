import { useEffect, useState } from 'react'
import { loadActiveConfig, UI_LANG, type RubricContent } from '../lib/config'
import { clearLocal, INITIAL_FLOW, readFlow, writeFlow, type FlowState } from '../lib/flowState'
import { createSession, readSession, saveBackground } from '../lib/session'
import ConsentPage from '../screens/ConsentPage'
import InfoForm from '../screens/InfoForm'
import Intro from '../screens/Intro'
import { Ended, EndSession, TopBar } from '../screens/SessionChrome'

/**
 * Annotator flow (D-24):
 * K1 Giriş + Onam → K3 Bilgi formu → K4 Yönerge → K5 Değerlendirme → K6 Set tamamlandı → Teşekkürler
 * Implemented: K1–K4. Screen texts Turkish (D-23), all from rubric_config (FR-CFG-TXT-001).
 */
export default function AnnotatorApp() {
  const [config, setConfig] = useState<RubricContent | null>(null)
  const [failed, setFailed] = useState(false)
  const [ended, setEnded] = useState(false)
  const [flow, setFlow] = useState<FlowState>(() => {
    const f = readFlow()
    // Steps after the form need the stored session; without it, start again (FR-SES-004).
    return (f.step === 'intro' || f.step === 'annotate') && !readSession() ? INITIAL_FLOW : f
  })

  useEffect(() => {
    loadActiveConfig().then(setConfig).catch((e) => {
      console.error(e)
      setFailed(true)
    })
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
        </section>
      </main>
    )
  }
  if (!config) return <main className="narrow" aria-busy="true"><div className="spinner" /></main>

  const bar = config.session_bar.tr
  const appName = config.app_name[UI_LANG]
  const endSession = () => { clearLocal(); setFlow(INITIAL_FLOW); setEnded(true) }

  if (ended) return <Ended t={bar} onRestart={() => setEnded(false)} />

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
          <EndSession t={bar} onEnd={endSession} />
        </>
      )
    case 'intro':
      return (
        <>
          <TopBar appName={appName} step={config.intro.tr.step} />
          <Intro t={config.intro.tr} config={config} onStart={() => update({ ...flow, step: 'annotate' })} />
          <EndSession t={bar} onEnd={endSession} />
        </>
      )
    case 'annotate':
      return (
        <>
          <TopBar appName={appName} step="" />
          <main className="narrow"><section className="panel"><p className="lede">{config.common.tr.not_ready}</p></section></main>
          <EndSession t={bar} onEnd={endSession} />
        </>
      )
  }
}
