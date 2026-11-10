/** Small, dependency-free charts for the admin dashboard (dataviz skill: thin marks, one hue, legend, tooltip). */

const ORD = ['#86b6ef', '#3987e5', '#184f95'] // ordinal blue: 0, 1, 2 (validated, light surface)

export function Bars({ rows, unit = '' }: { rows: { label: string; value: number }[]; unit?: string }) {
  const max = Math.max(1, ...rows.map((r) => r.value))
  if (!rows.length) return <p className="muted">Henüz veri yok.</p>
  return (
    <div className="hbars" role="table">
      {rows.map((r) => (
        <div className="hbar" role="row" key={r.label} title={`${r.label}: ${r.value}${unit}`}>
          <span className="hbar-label" role="cell">{r.label}</span>
          <span className="hbar-track" role="cell"><span className="hbar-fill" style={{ width: `${(100 * r.value) / max}%` }} /></span>
          <span className="hbar-val" role="cell">{r.value}{unit}</span>
        </div>
      ))}
    </div>
  )
}

export function Stacked({ rows }: { rows: { label: string; parts: number[] }[] }) {
  const names = ['0', '1', '2']
  const colors = ORD
  if (!rows.length) return <p className="muted">Henüz veri yok.</p>
  return (
    <div>
      <div className="legend">
        {names.map((n, i) => <span key={n}><i style={{ background: colors[i] }} />{n}</span>)}
      </div>
      <div className="hbars">
        {rows.map((r) => {
          const total = r.parts.reduce((a, b) => a + b, 0) || 1
          return (
            <div className="hbar" key={r.label}>
              <span className="hbar-label">{r.label}</span>
              <span className="stack">
                {r.parts.map((v, i) => v > 0 && (
                  <span key={i} className="seg" title={`${r.label} · ${names[i]}: ${v} (%${Math.round((100 * v) / total)})`}
                    style={{ width: `${(100 * v) / total}%`, background: colors[i] }} />
                ))}
              </span>
              <span className="hbar-val">{total === 1 && !r.parts.some(Boolean) ? 0 : total}</span>
            </div>
          )
        })}
      </div>
    </div>
  )
}
