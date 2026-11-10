import { useEffect, useMemo, useState } from 'react'
import { adminDb } from '../lib/adminClient'
import { loadAll } from './data'
import { buildSheets, type RawData, type Row } from './exportData'
import { A } from './texts'

/** Gereksinimler (FR-ADM-002, FR-ADM-006, FR-DAT-004): coverage list, eligibility toggle, detail of all scores. */
export default function Requirements({ tick }: { tick: number }) {
  const [data, setData] = useState<RawData | null>(null)
  const [sheets, setSheets] = useState<Record<string, Row[]> | null>(null)
  const [lang, setLang] = useState<'ALL' | 'EN' | 'TR'>('ALL')
  const [q, setQ] = useState('')
  const [open, setOpen] = useState<string | null>(null)
  const [err, setErr] = useState('')
  const [reload, setReload] = useState(0)

  useEffect(() => {
    let alive = true
    loadAll().then((d) => { if (alive) { setData(d); setSheets(buildSheets(d)) } }).catch((e) => setErr((e as Error).message))
    return () => { alive = false }
  }, [tick, reload])

  const list = useMemo(() => {
    if (!data || !sheets) return []
    const target = Number(data.cfg.coverage_target ?? 3)
    const byReq = new Map<string, Row>()
    for (const r of sheets.Gereksinim_Ozeti) if (!byReq.has(String(r.req_id))) byReq.set(String(r.req_id), r)
    return data.reqs
      .filter((r) => lang === 'ALL' || r.language_tag === lang)
      .filter((r) => !q || r.req_id.toLowerCase().includes(q.toLowerCase()) || (r.text_en ?? r.text_tr ?? '').toLowerCase().includes(q.toLowerCase()))
      .map((r) => ({ r, n: Number(byReq.get(r.req_id)?.n_raters ?? 0), target }))
  }, [data, sheets, lang, q])

  const toggle = async (reqId: string, eligible: boolean) => {
    const { error } = await adminDb!.from('requirements').update({ eligible }).eq('req_id', reqId)
    if (error) setErr(error.message); else setReload(reload + 1)
  }

  if (err) return <p className="err">{A.error}{err}</p>
  if (!data || !sheets) return <p className="muted">{A.loading}</p>
  const detail = open ? sheets.Puanlar_Ham.filter((r) => r.req_id === open) : []
  return (
    <section className="panel">
      <h2>Gereksinimler ({list.length})</h2>
      <div className="filters">
        <label>Dil <select value={lang} onChange={(e) => setLang(e.target.value as typeof lang)}>
          <option value="ALL">Tümü</option><option value="EN">İngilizce</option><option value="TR">Türkçe</option></select></label>
        <label>Ara <input type="text" value={q} onChange={(e) => setQ(e.target.value)} placeholder="req_id veya metin" /></label>
      </div>
      <p className="muted">Satıra tıklayınca o gereksinimin tüm puanları açılır. "Uygun" kutusu kaldırılan gereksinim yeni setlere atanmaz; verilen puanlar silinmez.</p>
      <div className="scroll">
        <table className="tbl">
          <thead><tr><th>req_id</th><th>Dil</th><th>Proje</th><th>Metin</th><th>Değerlendirici</th><th>Kapsama</th><th>Uygun</th></tr></thead>
          <tbody>
            {list.map(({ r, n, target }) => (
              <tr key={r.req_id} className="click" onClick={() => setOpen(open === r.req_id ? null : r.req_id)}>
                <td>{r.req_id}</td><td>{r.language_tag}</td><td>{r.project_id}</td>
                <td className="muted">{(r.language_tag === 'EN' ? r.text_en : r.text_tr)?.slice(0, 90)}</td>
                <td>{n}</td>
                <td>{n >= target ? <span className="badge good">hedef</span> : <span className="badge">{n}/{target}</span>}</td>
                <td onClick={(e) => e.stopPropagation()}>
                  <input type="checkbox" aria-label={`${r.req_id} uygun`} checked={r.eligible} onChange={(e) => toggle(r.req_id, e.target.checked)} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {open && (
        <div className="mt">
          <h2>{open}: puanlar ({detail.length})</h2>
          {detail.length === 0 ? <p className="muted">Henüz puan yok.</p> : (
            <div className="scroll">
              <table className="tbl">
                <thead><tr><th>Kod</th><th>Tur</th><th>Metrik</th><th>Puan</th><th>Not</th><th>Süre (sn)</th><th>Dikkat sorusu</th></tr></thead>
                <tbody>{detail.map((d, i) => (
                  <tr key={i}><td>{d.rater_code}</td><td>{d.round}</td><td>{d.metric_id}</td><td>{d.score}</td>
                    <td className="muted">{d.note}</td><td>{d.time_seconds_item}</td><td>{d.is_attention_check ? 'evet' : ''}</td></tr>
                ))}</tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </section>
  )
}
