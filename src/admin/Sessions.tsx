import { useEffect, useState } from 'react'
import { adminDb, fetchAll } from '../lib/adminClient'
import { loadAll } from './data'
import { buildSheets, type Row } from './exportData'
import { A } from './texts'

interface ClientError { id: number; session_id: string | null; location: string; message: string; created_at: string }

/** Oturumlar (FR-ADM-003/004, FR-QC-005): list, flags, exclusion toggle; recent client errors (NFR-REL-004). */
export default function Sessions({ tick }: { tick: number }) {
  const [rows, setRows] = useState<Row[] | null>(null)
  const [errors, setErrors] = useState<ClientError[]>([])
  const [err, setErr] = useState('')
  const [reload, setReload] = useState(0)

  useEffect(() => {
    let alive = true
    loadAll().then((d) => { if (alive) setRows(buildSheets(d).Oturumlar_QC) }).catch((e) => setErr((e as Error).message))
    fetchAll<ClientError>('client_errors', 'id').then((x) => { if (alive) setErrors(x.slice(-50).reverse()) }).catch(() => undefined)
    return () => { alive = false }
  }, [tick, reload])

  const toggle = async (sid: string, excluded: boolean) => {
    const { error } = await adminDb!.from('sessions').update({ excluded }).eq('session_id', sid)
    if (error) setErr(error.message); else setReload(reload + 1)
  }

  if (err) return <p className="err">{A.error}{err}</p>
  if (!rows) return <p className="muted">{A.loading}</p>
  return (
    <>
      <section className="panel">
        <h2>Oturumlar ({rows.length})</h2>
        <p className="muted">Bayraklar set tamamlanınca sunucuda hesaplanır: tutarlılık = dikkat sorusunda 0↔2 farkı; hız = ortanca süre eşik altında. Bayrak oturumu kendiliğinden dışlamaz.</p>
        <div className="scroll">
          <table className="tbl">
            <thead><tr><th>Kod</th><th>Başlangıç</th><th>Dil</th><th>Tür</th><th>Set</th><th>Öğe</th><th>Ortanca sn</th><th>Dikkat eşleşme</th><th>Bayrak</th><th>Durum</th><th>Analize dahil</th></tr></thead>
            <tbody>
              {rows.map((r) => (
                <tr key={String(r.session_id)}>
                  <td title={String(r.session_id)}>{r.rater_code}</td>
                  <td>{String(r.created_at).slice(0, 16).replace('T', ' ')}</td>
                  <td>{r.language_pref}</td>
                  <td>{r.annotator_type}{r.annotator_type_other ? ` (${r.annotator_type_other})` : ''}</td>
                  <td>{r.batches_completed}</td>
                  <td>{r.items_scored}/{r.items_assigned}</td>
                  <td>{r.median_seconds_per_item ?? '—'}</td>
                  <td>{r.attention_exact_match_pct == null ? '—' : `%${r.attention_exact_match_pct}`}</td>
                  <td>
                    {r.flag_consistency && <span className="badge bad">tutarlılık</span>} {r.flag_speed && <span className="badge warn">hız</span>}
                  </td>
                  <td>{r.withdrawn_at ? <span className="badge bad">sildi</span> : r.ended_at ? <span className="badge">bitti</span> : <span className="badge good">açık</span>}</td>
                  <td><input type="checkbox" aria-label={`${r.rater_code} analize dahil`} checked={!r.excluded} disabled={Boolean(r.withdrawn_at)}
                    onChange={(e) => toggle(String(r.session_id), !e.target.checked)} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
      <section className="panel mt">
        <h2>Son istemci hataları</h2>
        {errors.length === 0 ? <p className="muted">Kayıt yok.</p> : (
          <div className="scroll">
            <table className="tbl">
              <thead><tr><th>Zaman</th><th>Yer</th><th>Mesaj</th></tr></thead>
              <tbody>{errors.map((e) => <tr key={e.id}><td>{e.created_at.slice(0, 16).replace('T', ' ')}</td><td>{e.location}</td><td className="muted">{e.message.slice(0, 300)}</td></tr>)}</tbody>
            </table>
          </div>
        )}
      </section>
    </>
  )
}
