import type { LanguagePref, LanguageSelectTexts } from '../lib/config'

/** [1] Language Selection (FR-LNG-001..005). Bilingual; three options shown together. */
export default function LanguageSelect({ t, onSelect }: { t: LanguageSelectTexts; onSelect: (p: LanguagePref) => void }) {
  const options: { pref: LanguagePref; lang: string; text: string; sub?: string }[] = [
    { pref: 'EN', lang: 'en', text: t.option_en },
    { pref: 'TR', lang: 'tr', text: t.option_tr },
    { pref: 'BOTH', lang: 'en', text: t.option_both_en, sub: t.option_both_tr },
  ]
  return (
    <section className="card" aria-labelledby="lang-title">
      <h1 id="lang-title" className="title">
        <span lang="en">{t.page_title_en}</span>
        <span className="title-sep" aria-hidden="true"> / </span>
        <span lang="tr">{t.page_title_tr}</span>
      </h1>
      <div className="options">
        {options.map((o) => (
          <button key={o.pref} type="button" className="option" onClick={() => onSelect(o.pref)}>
            <span lang={o.lang}>{o.text}</span>
            {o.sub && <span lang="tr" className="option-sub">{o.sub}</span>}
          </button>
        ))}
      </div>
    </section>
  )
}
