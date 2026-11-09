import { fill, type IntroTexts, type RubricContent } from '../lib/config'

/** K4 Değerlendirme yönergesi (replaces the calibration tutorial, D-24). */
export default function Intro({ t, config, onStart }: { t: IntroTexts; config: RubricContent; onStart: () => void }) {
  const vars = {
    metrics: config.metrics.map((m) => m.name_tr).join(', '),
    scale: (['0', '1', '2'] as const).map((k) => `${k} — ${config.scale[k].label.tr}`).join(', '),
    general_guidance: config.general_guidance.tr,
  }
  return (
    <main className="intro">
      <h1>{t.title}</h1>
      <ul className="guide">
        {t.items.map((s, i) => <li key={i}>{fill(s, vars)}</li>)}
      </ul>
      <div className="submitrow">
        <button type="button" className="btn btn-primary" onClick={onStart}>{t.button}</button>
      </div>
    </main>
  )
}
