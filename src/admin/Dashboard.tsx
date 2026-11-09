import { useEffect, useState } from 'react'
import { adminDb } from '../lib/adminClient'
import { Bars, Stacked } from './Charts'
import { A } from './texts'

interface Dash {
  sessions: number; sessions_scored: number; sessions_batch_done: number; sessions_excluded: number
  by_language: Record<string, number>; by_type: Record<string, number>
  batches: number; batches_done: number; items_scored: number; score_rows: number
  requirements: Record<string, number>; coverage_target: number; coverage: Record<string, number>
  score_dist: Record<string, { '0': number; '1': number; '2': number; ca: number }>
  daily: { day: string; n: number }[]; median_seconds: number | null
}

const METRICS: [string, string][] = [
  ['M_IND_01', 'Uygunluk'], ['M_IND_02', 'Tek anlamlılık'], ['M_IND_03', 'Tamlık'],
  ['M_IND_04', 'Tekillik'], ['M_IND_05', 'Doğrulanabilirlik'], ['M_IND_06', 'Kurallara uygunluk'],
]
const TYPES: Record<string, string> = { student: 'Öğrenci', industry: 'Sektör', researcher: 'Akademik', other: 'Diğer', none: 'Yanıtsız' }
const LANGS: Record<string, string> = { EN: 'İngilizce', TR: 'Türkçe', BOTH: 'Her ikisi' }

export default function Dashboard({ tick }: { tick: number }) {
  const [d, setD] = useState<Dash | null>(null)
  const [st, setSt] = useState<{ ended: number; withdrawn: number; strategy: string; config_version: string; flag_consistency: number; flag_speed: number; client_errors_24h: number } | null>(null)
  const [err, setErr] = useState('')
  useEffect(() => {
    adminDb!.rpc('admin_dashboard').then(({ data, error }) => {
      if (error) setErr(error.message); else setD(data as Dash)
    })
    adminDb!.rpc('admin_status').then(({ data }) => setSt(data as typeof st))
  }, [tick])
  if (err) return <p className="err">{A.error}{err}</p>
  if (!d) return <p className="muted">{A.loading}</p>

  const reqTotal = Object.values(d.requirements).reduce((a, b) => a + b, 0)
  const covKeys = Object.keys(d.coverage).filter((k) => k !== 'target').sort((a, b) => Number(a) - Number(b))
  return (
    <div className="dash">
      <div className="tiles">
        <Tile label="Oturum (bilgi formunu gönderen)" value={d.sessions} />
        <Tile label="Puan veren oturum" value={d.sessions_scored} />
        <Tile label="En az bir seti bitiren" value={d.sessions_batch_done} />
        <Tile label="Tamamlanan set" value={`${d.batches_done} / ${d.batches}`} />
        <Tile label="Puanlanan öğe (gereksinim × oturum)" value={d.items_scored} />
        <Tile label="Ortanca süre / öğe" value={d.median_seconds == null ? '—' : `${Math.round(d.median_seconds)} sn`} />
        <Tile label={`Kapsama hedefine (${d.coverage_target}) ulaşan gereksinim`} value={`${d.coverage.target ?? 0} / ${reqTotal}`} />
        <Tile label="Dışlanan oturum" value={d.sessions_excluded} />
        <Tile label="Sonlandırılan (yanıtlar saklandı)" value={st?.ended ?? '—'} />
        <Tile label="Yanıtlarını silen" value={st?.withdrawn ?? '—'} />
        <Tile label="Bayrak: tutarlılık / hız" value={st ? `${st.flag_consistency} / ${st.flag_speed}` : '—'} />
        <Tile label="İstemci hatası (son 24 saat)" value={st?.client_errors_24h ?? '—'} />
        <Tile label="Etkin örnekleme stratejisi" value={st ? (st.strategy === 'RAND' ? 'RAND' : `${st.strategy} → RAND`) : '—'} />
        <Tile label="Etkin yapılandırma sürümü" value={st?.config_version ?? '—'} />
      </div>
      <div className="grid2">
        <section className="panel">
          <h2>Kaç gereksinim kaç kez puanlandı</h2>
          <p className="muted">Farklı oturum sayısına göre gereksinim sayısı (dikkat soruları ve dışlanan oturumlar hariç).</p>
          <Bars rows={[...covKeys.map((k) => ({ label: `${k} kez`, value: d.coverage[k] })),
            ...(d.coverage.target ? [{ label: `≥ ${d.coverage_target} kez`, value: d.coverage.target }] : [])]} />
        </section>
        <section className="panel">
          <h2>Metrik başına puan dağılımı</h2>
          <Stacked rows={METRICS.map(([id, name]) => {
            const s = d.score_dist[id] ?? { '0': 0, '1': 0, '2': 0, ca: 0 }
            return { label: name, parts: [s['0'], s['1'], s['2'], s.ca] }
          })} />
        </section>
        <section className="panel">
          <h2>Oturumlar: dil tercihi</h2>
          <Bars rows={Object.entries(d.by_language).map(([k, v]) => ({ label: LANGS[k] ?? k, value: v }))} />
          <h2 className="mt">Oturumlar: katılımcı türü</h2>
          <Bars rows={Object.entries(d.by_type).map(([k, v]) => ({ label: TYPES[k] ?? k, value: v }))} />
        </section>
        <section className="panel">
          <h2>Günlere göre yeni oturum</h2>
          <Bars rows={d.daily.map((x) => ({ label: x.day, value: x.n }))} />
          <h2 className="mt">Havuz</h2>
          <Bars rows={Object.entries(d.requirements).map(([k, v]) => ({ label: LANGS[k] ?? k, value: v }))} />
        </section>
      </div>
    </div>
  )
}

function Tile({ label, value }: { label: string; value: number | string }) {
  return <div className="tile"><span className="tile-val">{value}</span><span className="tile-label">{label}</span></div>
}
