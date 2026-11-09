import { useState } from 'react'
import { adminDb, fetchAll } from '../lib/adminClient'
import { buildSheets, type Bat, type Item, type Ref, type Req, type Row, type Sc, type Ses } from './exportData'
import { A } from './texts'

const DESC: Record<string, string> = {
  Bilgi: 'Dışa aktarım zamanı, rubrik sürümü, parametreler ve sütun açıklamaları.',
  Puanlar_Ham: 'Her satır: oturum × gereksinim × metrik. Dikkat soruları ve dışlanan oturumlar dahil.',
  Gereksinim_Ozeti: 'Gereksinim × metrik: puan sayısı, ortalama, medyan, std, 0/1/2 dağılımı, referans puan ve farkı.',
  Oturumlar_QC: 'Oturum bilgileri, süreler, hız uyarısı, dikkat sorusu tutarlılığı, yorum.',
}

export default function Export() {
  const [sheets, setSheets] = useState<Record<string, Row[]> | null>(null)
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')

  const load = async () => {
    setBusy(true); setErr('')
    try {
      const [reqs, sessions, batches, items, scores, refs] = await Promise.all([
        fetchAll<Req>('requirements', 'req_id'), fetchAll<Ses>('sessions', 'created_at'),
        fetchAll<Bat>('batches', 'created_at'), fetchAll<Item>('batch_items', 'batch_item_id'),
        fetchAll<Sc>('scores', 'score_id'), fetchAll<Ref>('reference_labels', 'base_id'),
      ])
      const { data: cfg } = await adminDb!.from('app_config').select('*').eq('id', 1).single()
      const { data: rc } = await adminDb!.from('rubric_config').select('version_label').eq('is_active', true).single()
      setSheets(buildSheets({ reqs, sessions, batches, items, scores, refs, cfg: cfg ?? {}, rubricVersion: rc?.version_label ?? '' }))
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
      XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(rows.length ? rows : [{ bilgi: 'Kayıt yok' }]), name.slice(0, 31))
    }
    XLSX.writeFile(wb, `degerlendirme_export_${stamp()}.xlsx`)
  }
  const csv = async (name: string) => {
    const XLSX = await import('xlsx')
    const text = XLSX.utils.sheet_to_csv(XLSX.utils.json_to_sheet(sheets![name]))
    const blob = new Blob(['﻿' + text], { type: 'text/csv;charset=utf-8' })
    const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = `${name}_${stamp()}.csv`; a.click()
    URL.revokeObjectURL(a.href)
  }

  return (
    <div className="panel">
      <p className="muted">Veriler veritabanından okunur ve dosya tarayıcınızda oluşturulur.</p>
      <button className="btn btn-primary" onClick={load} disabled={busy}>{busy ? A.loading : sheets ? 'Verileri yeniden oku' : 'Verileri oku'}</button>
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
