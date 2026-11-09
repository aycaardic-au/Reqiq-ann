import { useState } from 'react'
import { loadAll } from './data'
import { applyFilter, buildSheets, DEFAULT_FILTER, sanitizeRows, type ExportFilter, type Row } from './exportData'
import { A } from './texts'

const DESC: Record<string, string> = {
  Bilgi: 'Dışa aktarım zamanı, rubrik sürümü, uygulanan filtre, parametreler ve sütun açıklamaları.',
  Puanlar_Ham: 'Her satır: oturum × gereksinim × metrik; gereksinim metni, yapılandırma sürümü, dikkat sorusu işareti dahil.',
  Gereksinim_Ozeti: 'Gereksinim × metrik: puan sayısı, ortalama, medyan, std, 0/1/2 dağılımı, referans puan ve farkı.',
  Oturumlar_QC: 'Oturum bilgileri, süreler, sunucunun hesapladığı bayraklar, dikkat sorusu tutarlılığı, yorum.',
}

/** Dışa aktar (FR-ADM-007/008, D-31): filters, Excel with all sheets or CSV per sheet; cells sanitised (NFR-SEC-005). */
export default function Export() {
  const [sheets, setSheets] = useState<Record<string, Row[]> | null>(null)
  const [f, setF] = useState<ExportFilter>(DEFAULT_FILTER)
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')

  const describe = (x: ExportFilter) => [
    x.includeExcluded ? 'excluded sessions included' : 'excluded sessions removed',
    x.includeFlagged ? 'flagged sessions included' : 'flagged sessions removed',
    `language=${x.language}`, `round=${x.round}`, x.coverageMetOnly ? 'coverage-met requirements only' : '',
  ].filter(Boolean).join('; ')

  const load = async () => {
    setBusy(true); setErr('')
    try {
      const raw = await loadAll()
      setSheets(buildSheets(applyFilter(raw, f), describe(f)))
    } catch (e) {
      setErr((e as Error).message)
    } finally {
      setBusy(false)
    }
  }

  const stamp = () => new Date().toISOString().slice(0, 16).replace(/[-:T]/g, '')
  const excel = async () => {
    const XLSX = await import('xlsx')
    const wb = XLSX.utils.book_new()
    for (const [name, rows] of Object.entries(sheets!)) {
      XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(rows.length ? sanitizeRows(rows) : [{ bilgi: 'Kayıt yok' }]), name.slice(0, 31))
    }
    XLSX.writeFile(wb, `degerlendirme_export_${stamp()}.xlsx`)
  }
  const csv = async (name: string) => {
    const XLSX = await import('xlsx')
    const text = XLSX.utils.sheet_to_csv(XLSX.utils.json_to_sheet(sanitizeRows(sheets![name])))
    const blob = new Blob(['﻿' + text], { type: 'text/csv;charset=utf-8' })
    const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = `${name}_${stamp()}.csv`; a.click()
    URL.revokeObjectURL(a.href)
  }
  const set = (patch: Partial<ExportFilter>) => { setF({ ...f, ...patch }); setSheets(null) }

  return (
    <div className="panel">
      <p className="muted">Veriler veritabanından okunur ve dosya tarayıcınızda oluşturulur. Filtre değişince verileri yeniden okuyun.</p>
      <div className="filters">
        <label><input type="checkbox" checked={f.includeExcluded} onChange={(e) => set({ includeExcluded: e.target.checked })} /> Dışlanan oturumları dahil et</label>
        <label><input type="checkbox" checked={f.includeFlagged} onChange={(e) => set({ includeFlagged: e.target.checked })} /> Bayraklı oturumları dahil et</label>
        <label>Dil <select value={f.language} onChange={(e) => set({ language: e.target.value as ExportFilter['language'] })}>
          <option value="ALL">Tümü</option><option value="EN">İngilizce</option><option value="TR">Türkçe</option></select></label>
        <label>Tur <select value={f.round} onChange={(e) => set({ round: e.target.value as ExportFilter['round'] })}>
          <option value="ALL">Tümü</option><option value="1">1</option><option value="2">2</option><option value="3+">3+</option></select></label>
        <label><input type="checkbox" checked={f.coverageMetOnly} onChange={(e) => set({ coverageMetOnly: e.target.checked })} /> Yalnızca kapsama hedefine ulaşan gereksinimler</label>
      </div>
      <button className="btn btn-primary" onClick={load} disabled={busy}>{busy ? A.loading : 'Verileri oku'}</button>
      {err && <p className="err">{A.error}{err}</p>}
      {sheets && (
        <>
          <div className="submitrow left"><button className="btn btn-primary" onClick={excel}>Excel indir (tüm sayfalar)</button></div>
          <table className="tbl">
            <thead><tr><th>Sayfa</th><th>Satır</th><th>Açıklama</th><th>CSV</th></tr></thead>
            <tbody>
              {Object.entries(sheets).map(([name, rows]) => (
                <tr key={name}>
                  <td>{name}</td><td>{rows.length}</td>
                  <td className="muted">{DESC[name] ?? (name.startsWith('Matris_') ? 'Satır = gereksinim, sütun = değerlendirici kodu (Rxxx); IRA araçları için.' : '')}</td>
                  <td><button className="link" onClick={() => csv(name)}>CSV</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
    </div>
  )
}
