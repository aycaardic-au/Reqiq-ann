import { fill, type IntroTexts, type RubricContent } from '../lib/config'

/** K4 Değerlendirme yönergesi (replaces the calibration tutorial, D-24). */
export default function Intro({ t, config, onStart, english = false }: { t: IntroTexts; config: RubricContent; onStart: () => void; english?: boolean }) {
  const vars = {
    metrics: config.metrics.map((m) => (english ? m.name_en : m.name_tr)).join(', '),
    scale: (['0', '1', '2'] as const).map((k) => `${k} — ${english ? config.scale[k].label.en : config.scale[k].label.tr}`).join(', '),
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
