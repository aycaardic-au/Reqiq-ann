import { useEffect, useState } from 'react'
import { adminDb } from '../lib/adminClient'
import { A } from './texts'

type Cfg = Record<string, number | string>

const FIELDS: { key: string; label: string; hint: string; type: 'int' | 'real' | 'strategy' }[] = [
  { key: 'batch_size', label: 'Set büyüklüğü', hint: 'Bir setteki toplam öğe (benzersiz + dikkat sorusu). Varsayılan 30.', type: 'int' },
  { key: 'attention_check_count', label: 'Dikkat sorusu sayısı', hint: 'Her sette tekrar gösterilen öğe sayısı. Varsayılan 2.', type: 'int' },
  { key: 'coverage_target', label: 'Kapsama hedefi', hint: 'Bir gereksinimin en az kaç farklı kişi tarafından puanlanması hedefleniyor. Varsayılan 3.', type: 'int' },
  { key: 'max_batches_per_session', label: 'Oturum başına en fazla set', hint: 'Varsayılan 5.', type: 'int' },
  { key: 'project_id_cap_pct', label: 'Bir projenin set içindeki en yüksek payı', hint: '0–1 arası. Varsayılan 0,25 (%25).', type: 'real' },
  { key: 'speed_flag_threshold_sec', label: 'Hız uyarısı eşiği (sn / öğe)', hint: 'Ortanca süre bunun altındaysa dışa aktarımda uyarı verilir. Varsayılan 20.', type: 'int' },
  { key: 'sampling_strategy', label: 'Örnekleme stratejisi', hint: 'Şu an yalnızca RAND (kademe + rastgele + proje payı sınırı) uygulanıyor; diğerleri RAND gibi çalışır (D-27).', type: 'strategy' },
]

export default function Params() {
  const [cfg, setCfg] = useState<Cfg | null>(null)
  const [msg, setMsg] = useState('')
  const [err, setErr] = useState('')
  useEffect(() => {
    adminDb!.from('app_config').select('*').eq('id', 1).single().then(({ data, error }) => {
      if (error) setErr(error.message); else setCfg(data as Cfg)
    })
  }, [])
  if (err && !cfg) return <p className="err">{A.error}{err}</p>
  if (!cfg) return <p className="muted">{A.loading}</p>

  const save = async (e: React.FormEvent) => {
    e.preventDefault()
    setMsg(''); setErr('')
    const patch: Cfg = {}
    for (const f of FIELDS) patch[f.key] = f.type === 'strategy' ? String(cfg[f.key]) : Number(cfg[f.key])
    const { error } = await adminDb!.from('app_config').update(patch).eq('id', 1)
    if (error) setErr(error.message); else setMsg(A.saved)
  }

  return (
    <form className="panel params" onSubmit={save}>
      <p className="muted">Değişiklikler yeni atanan setlerde geçerli olur; açık setler değişmez.</p>
      {FIELDS.map((f) => (
        <label key={f.key} className="param">
          <span className="param-label">{f.label}</span>
          {f.type === 'strategy' ? (
            <select value={String(cfg[f.key])} onChange={(e) => setCfg({ ...cfg, [f.key]: e.target.value })}>
              {['RAND', 'DIST', 'SCORE-STRAT', 'ADAPT'].map((s) => <option key={s}>{s}</option>)}
            </select>
          ) : (
            <input type="number" step={f.type === 'real' ? '0.05' : '1'} value={String(cfg[f.key])}
              onChange={(e) => setCfg({ ...cfg, [f.key]: e.target.value })} />
          )}
          <span className="hint">{f.hint}</span>
        </label>
      ))}
      {err && <p className="err">{err}</p>}
      {msg && <p className="ok">{msg}</p>}
      <div className="submitrow"><button className="btn btn-primary" type="submit">{A.save}</button></div>
    </form>
  )
}
