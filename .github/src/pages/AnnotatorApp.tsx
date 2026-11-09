import { useEffect, useState } from 'react'
import { loadActiveConfig, uiLangFor, type LanguagePref, type RubricContent } from '../lib/config'
import { readFlow, writeFlow, type FlowState } from '../lib/flowState'
import LanguageSelect from '../screens/LanguageSelect'
import Welcome from '../screens/Welcome'

/**
 * Annotator flow container (FR-ONB-001):
 * [1] Language → [2] Welcome → [3] Consent → [4] Background →
 * [5] Calibration → [6] Batch → [7] Batch Complete → [8] Thank-You
 * Implemented: [1], [2]. All texts come from rubric_config (FR-CFG-TXT-001).
 */
export default function AnnotatorApp() {
  const [config, setConfig] = useState<RubricContent | null>(null)
  const [failed, setFailed] = useState(false)
  const [flow, setFlow] = useState<FlowState>(readFlow)

  useEffect(() => {
    loadActiveConfig().then(setConfig).catch((e) => {
      console.error(e)
      setFailed(true)
    })
  }, [])

  const uiLang = flow.language ? uiLangFor(flow.language) : null

  useEffect(() => {
    if (!config) return
    document.documentElement.lang = uiLang ?? 'en'
    document.title = uiLang ? config.app_name[uiLang] : `${config.app_name.en} / ${config.app_name.tr}`
  }, [config, uiLang])

  const update = (s: FlowState) => {
    writeFlow(s)
    setFlow(s)
  }

  if (failed) {
    // FR-CFG-TXT-002: the only hard-coded text — shown when the configuration cannot be loaded.
    return (
      <main className="page">
        <section className="card" role="alert">
          <p lang="en">The tool cannot be loaded at the moment. Please try again later.</p>
          <p lang="tr">Araç şu anda yüklenemiyor. Lütfen daha sonra tekrar deneyin.</p>
        </section>
      </main>
    )
  }
  if (!config) {
    return <main className="page" aria-busy="true"><div className="spinner" /></main>
  }

  return (
    <main id="annotator-root" className="page">
      {flow.step === 'language' && (
        <LanguageSelect
          t={config.language_select}
          onSelect={(p: LanguagePref) => update({ language: p, step: 'welcome' })}
        />
      )}
      {flow.step === 'welcome' && uiLang && (
        <Welcome t={config.welcome[uiLang]} onContinue={() => update({ ...flow, step: 'consent' })} />
      )}
      {flow.step === 'consent' && import.meta.env.DEV && (
        <p className="dev-marker">[dev] next: consent (step 3) — language {flow.language}</p>
      )}
    </main>
  )
}
