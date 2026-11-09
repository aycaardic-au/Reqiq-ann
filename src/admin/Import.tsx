import { useEffect, useState } from 'react'
import { adminDb, fetchAll } from '../lib/adminClient'
import type { Cfg } from './exportData'

type Kind = 'requirements' | 'refs'
const COLS: Record<Kind, string[]> = {
  requirements: ['req_id', 'base_id', 'language_tag', 'project_id', 'text_en', 'text_tr', 'eligible', 'req_type'],
  refs: ['base_id', 'metric_id', 'llm_score', 'llm_cannot_assess', 'llm_model'],
}
const REQUIRED: Record<Kind, string[]> = {
  requirements: ['req_id', 'language_tag', 'project_id'],
  refs: ['base_id', 'metric_id', 'llm_model'],
}
const RPC: Record<Kind, string> = { requirements: 'admin_import_requirements', refs: 'admin_import_reference_labels' }

type Cell = string | number | boolean | null

/** İçe aktar: requirement pool, reference labels (Excel/CSV) and texts/rubric/hints (JSON). */
export default function Import() {
  return (
    <div className="grid2">
      <TableImport kind="requirements" title="Gereksinim havuzu"
        note="Var olan req_id satırları güncellenir, yenileri eklenir. language_tag: EN veya TR; req_id biçimi EN_<no> / TR_<no>; base_id iki dilde aynı numara." />
      <TableImport kind="refs" title="Referans puanlar"
        note="base_id × metric_id başına bir satır (M_IND_01…M_IND_06). llm_score 0/1/2; değerlendirilemiyorsa llm_cannot_assess = TRUE ve puan boş." />
      <JsonImport />
      <Versions />
    </div>
  )
}

function TableImport({ kind, title, note }: { kind: Kind; title: string; note: string }) {
  const [rows, setRows] = useState<Record<string, Cell>[] | null>(null)
  const [problems, setProblems] = useState<string[]>([])
  const [msg, setMsg] = useState('')
  const [busy, setBusy] = useState(false)

  const template = async () => {
    const XLSX = await import('xlsx')
    const wb = XLSX.utils.book_new()
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([COLS[kind]]), 'data')
    XLSX.writeFile(wb, `sablon_${kind}.xlsx`)
  }

  const read = async (f: File) => {
    setMsg(''); setRows(null)
    const XLSX = await import('xlsx')
    const wb = XLSX.read(await f.arrayBuffer())
    const data = XLSX.utils.sheet_to_json<Record<string, Cell>>(wb.Sheets[wb.SheetNames[0]], { defval: null, raw: true })
    const p: string[] = []
    const cols = Object.keys(data[0] ?? {})
    for (const c of REQUIRED[kind]) if (!cols.includes(c)) p.push(`Eksik sütun: ${c}`)
    const extra = cols.filter((c) => !COLS[kind].includes(c))
    if (extra.length) p.push(`Kullanılmayacak sütunlar: ${extra.join(', ')}`)
    data.forEach((r, i) => {
      for (const c of REQUIRED[kind]) if (r[c] == null || r[c] === '') { p.push(`Satır ${i + 2}: ${c} boş`); break }
      if (kind === 'requirements' && r.language_tag && !['EN', 'TR'].includes(String(r.language_tag).toUpperCase())) p.push(`Satır ${i + 2}: language_tag EN/TR olmalı`)
      if (kind === 'refs' && r.metric_id && !/^M_IND_0[1-6]$/.test(String(r.metric_id))) p.push(`Satır ${i + 2}: metric_id geçersiz`)
    })
    setProblems(p.slice(0, 20))
    setRows(data.map((r) => Object.fromEntries(COLS[kind].map((c) => [c, r[c] == null ? null : String(r[c])]))))
  }

  const run = async () => {
    if (!rows) return
    setBusy(true); setMsg('')
    let n = 0
    for (let i = 0; i < rows.length; i += 500) {
      const { data, error } = await adminDb!.rpc(RPC[kind], { p_rows: rows.slice(i, i + 500) })
      if (error) { setMsg(`Hata (satır ${i + 2} civarı): ${error.message}`); setBusy(false); return }
      n += data as number
    }
    setMsg(`${n} satır içe aktarıldı.`); setBusy(false)
  }

  const blocking = problems.some((p) => !p.startsWith('Kullanılmayacak'))
  return (
    <section className="panel">
      <h2>{title}</h2>
      <p className="muted">{note}</p>
      <p className="muted">Sütunlar: <code>{COLS[kind].join(', ')}</code></p>
      <div className="row">
        <button className="link" onClick={template}>Şablon indir</button>
        <input type="file" accept=".xlsx,.xls,.csv" onChange={(e) => e.target.files?.[0] && read(e.target.files[0])} />
      </div>
      {rows && <p>{rows.length} satır okundu.</p>}
      {problems.map((p) => <p key={p} className={p.startsWith('Kullanılmayacak') ? 'muted' : 'err'}>{p}</p>)}
      {rows && <button className="btn btn-primary" disabled={busy || blocking || !rows.length} onClick={run}>{busy ? 'Aktarılıyor…' : 'İçe aktar'}</button>}
      {msg && <p className={msg.startsWith('Hata') ? 'err' : 'ok'}>{msg}</p>}
    </section>
  )
}

function JsonImport() {
  const [kind, setKind] = useState<'ui' | 'hints' | 'rubric'>('ui')
  const [obj, setObj] = useState<Record<string, unknown> | null>(null)
  const [label, setLabel] = useState('')
  const [note, setNote] = useState('')
  const [msg, setMsg] = useState('')

  const read = async (f: File) => {
    setMsg('')
    try { setObj(JSON.parse(await f.text())) } catch { setObj(null); setMsg('Hata: geçerli bir JSON dosyası değil.') }
  }
  const run = async () => {
    if (!obj) return
    const patch = kind === 'hints' ? { hints: obj.hints ?? obj } : obj
    const { data, error } = await adminDb!.rpc('admin_merge_config', { p_patch: patch, p_label: label || null, p_note: note || null })
    setMsg(error ? `Hata: ${error.message}` : `Etkin sürüm: ${data}`)
  }
  return (
    <section className="panel">
      <h2>Ekran metinleri / ipuçları / rubrik</h2>
      <p className="muted">Depodaki JSON dosyası yüklenir; etkin yapılandırmanın aynı adlı anahtarlarının yerine geçen <b>yeni bir sürüm</b> oluşturulur, önceki sürüm saklanır (geri alınabilir). Yeni setler yeni sürümle atanır. Yükledikten sonra katılımcı ekranını yenileyip kontrol edin.</p>
      <div className="row">
        <select value={kind} onChange={(e) => setKind(e.target.value as typeof kind)}>
          <option value="ui">Ekran metinleri (config/ui_texts.json)</option>
          <option value="hints">İpuçları (config/metric_hints.json)</option>
          <option value="rubric">Rubrik (config/rubric_v1.4.json)</option>
        </select>
        <input type="file" accept=".json" onChange={(e) => e.target.files?.[0] && read(e.target.files[0])} />
      </div>
      <div className="row"><input type="text" placeholder="Sürüm adı (isteğe bağlı)" value={label} onChange={(e) => setLabel(e.target.value)} />
        <input type="text" placeholder="Not (isteğe bağlı)" value={note} onChange={(e) => setNote(e.target.value)} /></div>
      {obj && <p>Anahtarlar: <code>{Object.keys(obj).filter((k) => k !== '_comment').join(', ')}</code></p>}
      {obj && <button className="btn btn-primary" onClick={run}>Yükle</button>}
      {msg && <p className={msg.startsWith('Hata') ? 'err' : 'ok'}>{msg}</p>}
    </section>
  )
}

/** FR-CFG-VER-003: configuration history and rollback. */
function Versions() {
  const [rows, setRows] = useState<Cfg[] | null>(null)
  const [msg, setMsg] = useState('')
  const [tick, setTick] = useState(0)
  useEffect(() => { fetchAll<Cfg>('rubric_config', 'config_id').then((x) => setRows([...x].reverse())).catch((e) => setMsg(`Hata: ${(e as Error).message}`)) }, [tick])
  const activate = async (c: Cfg) => {
    if (!window.confirm(`"${c.version_label}" sürümü etkin yapılsın mı? Yeni setler bu sürümle atanır.`)) return
    const { error } = await adminDb!.rpc('admin_activate_config', { p_config_id: c.config_id })
    setMsg(error ? `Hata: ${error.message}` : `Etkin sürüm: ${c.version_label}`); setTick(tick + 1)
  }
  return (
    <section className="panel">
      <h2>Yapılandırma sürümleri</h2>
      <p className="muted">Rubrik, metinler ve ipuçları birlikte sürümlenir. Her set, atandığı andaki sürümle kaydedilir (dışa aktarımda <code>config_version</code>).</p>
      {msg && <p className={msg.startsWith('Hata') ? 'err' : 'ok'}>{msg}</p>}
      {rows && (
        <div className="scroll">
          <table className="tbl">
            <thead><tr><th>Sürüm</th><th>Tarih</th><th>Not</th><th></th></tr></thead>
            <tbody>{rows.map((c) => (
              <tr key={c.config_id}>
                <td>{c.version_label}</td><td>{c.uploaded_at.slice(0, 16).replace('T', ' ')}</td><td className="muted">{c.note}</td>
                <td>{c.is_active ? <span className="badge good">etkin</span> : <button className="link" onClick={() => activate(c)}>Etkinleştir</button>}</td>
              </tr>
            ))}</tbody>
          </table>
        </div>
      )}
    </section>
  )
}
