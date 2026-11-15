import { useState } from 'react'
import { adminDb } from '../lib/adminClient'

/** Excel metric header → metric_id. Headers look like "Uygunluk (Appropriate) puan" / "… gerekçe". */
const METRIC_BY_EN: Record<string, string> = {
  Appropriate: 'M_IND_01', Unambiguous: 'M_IND_02', Complete: 'M_IND_03',
  Singular: 'M_IND_04', Verifiable: 'M_IND_05', Conforming: 'M_IND_06',
}
const METRIC_IDS = Object.values(METRIC_BY_EN)
const ANNOTATOR_LABELS: Record<string, string> = {
  student: 'Öğrenci', industry: 'Sanayi çalışanı', researcher: 'Araştırmacı', other: 'Diğer',
}
const LANG_LABELS: Record<string, string> = { BOTH: 'EN ve TR', EN: 'Yalnız EN', TR: 'Yalnız TR' }

type Cell = string | number | boolean | null
type Built = { excel_row: number; req_id: string; language_tag: string; project_id: string; base_id: string; scores: Record<string, { score: string | null; note: string | null }> }
type RpcResult = { status: 'ok' | 'error'; rows?: number; batches?: number; error_count?: number; errors?: string[] }

const txt = (v: Cell | undefined) => (v == null ? '' : String(v).trim())

/**
 * Katılımcının kendi puanlarını Excel şablonundan içe aktarır (migration 0034).
 * Sunucu tüm satırları doğrular; bir sorun varsa hiçbir satır yazılmaz ve sorunlar listelenir.
 */
export default function ParticipantImport() {
  const [code, setCode] = useState('AYCA')
  const [annotator, setAnnotator] = useState('industry')
  const [lang, setLang] = useState('BOTH')
  const [rows, setRows] = useState<Built[] | null>(null)
  const [problems, setProblems] = useState<string[]>([])
  const [msg, setMsg] = useState('')
  const [busy, setBusy] = useState(false)

  const read = async (f: File) => {
    setMsg(''); setRows(null); setProblems([])
    const XLSX = await import('xlsx')
    const wb = XLSX.read(await f.arrayBuffer())
    const name = wb.SheetNames.includes('Puanlar') ? 'Puanlar' : wb.SheetNames[0]
    const data = XLSX.utils.sheet_to_json<Record<string, Cell>>(wb.Sheets[name], { defval: null, raw: true })
    const headers = Object.keys(data[0] ?? {})

    const scoreCol: Record<string, string> = {}
    const noteCol: Record<string, string> = {}
    for (const h of headers) {
      const m = /\((\w+)\)\s+(puan|gerekçe)\s*$/i.exec(h.trim())
      if (m && METRIC_BY_EN[m[1]]) (m[2].toLowerCase() === 'puan' ? scoreCol : noteCol)[METRIC_BY_EN[m[1]]] = h
    }
    const pre: string[] = []
    const missing = ['Req_ID', 'Project_ID', 'Base_ID', 'Dil'].filter((c) => !headers.includes(c))
    if (missing.length) pre.push(`Eksik sütun: ${missing.join(', ')}`)
    const noScore = METRIC_IDS.filter((id) => !scoreCol[id])
    if (noScore.length) pre.push(`Puan sütunu bulunamadı: ${noScore.join(', ')}`)
    if (pre.length) { setProblems(pre); return }

    const built: Built[] = []
    data.forEach((r, i) => {
      const scoreVals = METRIC_IDS.map((id) => r[scoreCol[id]])
      if (txt(r.Req_ID) === '' && scoreVals.every((v) => txt(v) === '')) return
      const scores: Built['scores'] = {}
      for (const id of METRIC_IDS) {
        const s = txt(r[scoreCol[id]])
        const n = noteCol[id] ? txt(r[noteCol[id]]) : ''
        scores[id] = { score: s === '' ? null : s, note: n === '' ? null : n }
      }
      built.push({ excel_row: i + 2, req_id: txt(r.Req_ID), language_tag: txt(r.Dil), project_id: txt(r.Project_ID), base_id: txt(r.Base_ID), scores })
    })
    if (!built.length) { setProblems(['Dosyada puanlanmış satır yok.']); return }
    setRows(built)
  }

  const run = async () => {
    if (!rows) return
    setBusy(true); setMsg(''); setProblems([])
    const { data, error } = await adminDb!.rpc('admin_import_participant_scores', {
      p_rater_code: code.trim(), p_annotator_type: annotator, p_language_pref: lang, p_rows: rows,
    })
    setBusy(false)
    if (error) { setMsg(`Hata: ${error.message}`); return }
    const res = data as RpcResult
    if (res.status === 'error') {
      setProblems(res.errors ?? [])
      setMsg(`${res.error_count} sorun bulundu. Hiçbir satır yazılmadı; düzeltip yeniden yükleyin.`)
      return
    }
    setMsg(`${res.rows} satır, ${res.batches} batch içe aktarıldı. Aynı kodla yeniden yüklemek önceki puanların yerine geçer.`)
    setRows(null)
  }

  return (
    <section className="panel">
      <h2>Katılımcı puanları (Excel şablonu)</h2>
      <p className="muted">Şablon: "Puanlar" sayfası, her gereksinim sürümü için bir satır, altı metrik için puan (0/1/2) ve gerekçe. Yalnız bu sayfa okunur. Aynı değerlendirici kodu ile yeniden yükleme önceki puanların yerine geçer. Hata varsa hiçbir satır yazılmaz.</p>
      <div className="row">
        <input type="text" placeholder="Değerlendirici kodu" value={code} onChange={(e) => setCode(e.target.value)} />
        <select value={annotator} onChange={(e) => setAnnotator(e.target.value)}>
          {Object.entries(ANNOTATOR_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
        <select value={lang} onChange={(e) => setLang(e.target.value)}>
          {Object.entries(LANG_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
      </div>
      <div className="row">
        <input type="file" accept=".xlsx,.xls" onChange={(e) => e.target.files?.[0] && read(e.target.files[0])} />
      </div>
      {rows && <p>{rows.length} satır okundu.</p>}
      {problems.length > 0 && (
        <div className="scroll">
          {problems.slice(0, 50).map((p, i) => <p key={i} className="err">{p}</p>)}
          {problems.length > 50 && <p className="muted">… ve {problems.length - 50} sorun daha.</p>}
        </div>
      )}
      {rows && <button className="btn btn-primary" disabled={busy || !code.trim()} onClick={run}>{busy ? 'Aktarılıyor…' : 'İçe aktar'}</button>}
      {msg && <p className={msg.startsWith('Hata') || msg.includes('sorun') ? 'err' : 'ok'}>{msg}</p>}
    </section>
  )
}
