/** Builds the export sheets from raw table rows (D-26, D-31). Pure functions; no I/O. */

export interface Req { req_id: string; base_id: string | null; language_tag: string; project_id: string; text_en: string | null; text_tr: string | null; eligible: boolean; source_meta?: Record<string, unknown> }
export interface Ses { session_id: string; annotator_type: string | null; annotator_type_other: string | null; language_pref: string; batches_completed: number; comment: string | null; excluded: boolean; consent_version: string | null; created_at: string; last_active_at: string; ended_at?: string | null; withdrawn_at?: string | null; flag_consistency?: boolean; flag_speed?: boolean }
export interface Bat { batch_id: string; session_id: string; created_at: string; completed_at: string | null; config_id?: number | null; ac_pairs?: number | null; ac_mismatches?: number | null; ac_max_diff?: number | null; median_seconds?: number | null }
export interface Cfg { config_id: number; version_label: string; uploaded_at: string; is_active: boolean; note?: string | null }
export interface Item { batch_item_id: number; batch_id: string; req_id: string; position: number; is_attention_check: boolean; attention_check_original_req_id: string | null; time_seconds: number | null; round: number }
export interface Sc { session_id: string; batch_item_id: number; req_id: string; metric_id: string; score: number; note: string | null; annotation_language: string; round: number; created_at: string }
export interface Ref { base_id: string; metric_id: string; llm_score: number; llm_model: string }

export interface RawData { reqs: Req[]; sessions: Ses[]; batches: Bat[]; items: Item[]; scores: Sc[]; refs: Ref[]; cfg: Record<string, unknown>; rubricVersion: string; configs?: Cfg[] }

/** FR-ADM-008: export filters. */
export interface ExportFilter {
  includeExcluded: boolean
  includeFlagged: boolean
  language: 'ALL' | 'EN' | 'TR'
  round: 'ALL' | '1' | '2' | '3+'
  coverageMetOnly: boolean
}
export const DEFAULT_FILTER: ExportFilter = { includeExcluded: false, includeFlagged: true, language: 'ALL', round: 'ALL', coverageMetOnly: false }

/** Applies the filters to the raw rows (sessions and scores); requirements stay complete for reference. */
export function applyFilter(d: RawData, f: ExportFilter): RawData {
  const sessions = d.sessions.filter((s) => (f.includeExcluded || !s.excluded) && (f.includeFlagged || !(s.flag_consistency || s.flag_speed)))
  const keep = new Set(sessions.map((s) => s.session_id))
  let scores = d.scores.filter((s) => keep.has(s.session_id))
  if (f.language !== 'ALL') scores = scores.filter((s) => s.annotation_language === f.language)
  if (f.round !== 'ALL') scores = scores.filter((s) => (f.round === '3+' ? s.round >= 3 : s.round === Number(f.round)))
  if (f.coverageMetOnly) {
    const target = Number(d.cfg.coverage_target ?? 3)
    const items = new Map(d.items.map((i) => [i.batch_item_id, i]))
    const raters = new Map<string, Set<string>>()
    for (const s of d.scores) {
      if (items.get(s.batch_item_id)?.is_attention_check || !keep.has(s.session_id)) continue
      raters.set(s.req_id, (raters.get(s.req_id) ?? new Set()).add(s.session_id))
    }
    scores = scores.filter((s) => (raters.get(s.req_id)?.size ?? 0) >= target)
  }
  return { ...d, sessions, scores }
}

/** NFR-SEC-005: neutralise spreadsheet formulas in exported text (CSV/Excel injection). */
export function sanitizeCell(v: Row[string]): Row[string] {
  return typeof v === 'string' && /^[=+\-@\t\r]/.test(v) ? `'${v}` : v
}
export const sanitizeRows = (rows: Row[]) => rows.map((r) => Object.fromEntries(Object.entries(r).map(([k, v]) => [k, sanitizeCell(v)])) as Row)

export type Row = Record<string, string | number | boolean | null>
export const METRIC_IDS = ['M_IND_01', 'M_IND_02', 'M_IND_03', 'M_IND_04', 'M_IND_05', 'M_IND_06']

const median = (a: number[]) => {
  if (!a.length) return null
  const s = [...a].sort((x, y) => x - y); const m = Math.floor(s.length / 2)
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2
}
const mean = (a: number[]) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : null)
const sd = (a: number[]) => {
  if (a.length < 2) return null
  const m = mean(a)!; return Math.sqrt(a.reduce((x, y) => x + (y - m) ** 2, 0) / (a.length - 1))
}
const r3 = (v: number | null) => (v == null ? null : Math.round(v * 1000) / 1000)

export function buildSheets(d: RawData, filterNote = ''): Record<string, Row[]> {
  const reqBy = new Map(d.reqs.map((r) => [r.req_id, r]))
  const sesBy = new Map(d.sessions.map((s) => [s.session_id, s]))
  const batBy = new Map(d.batches.map((b) => [b.batch_id, b]))
  const itemBy = new Map(d.items.map((i) => [i.batch_item_id, i]))
  const refBy = new Map(d.refs.map((r) => [`${r.base_id}|${r.metric_id}`, r]))
  const cfgLabel = new Map((d.configs ?? []).map((c) => [c.config_id, c.version_label]))
  const target = Number(d.cfg.coverage_target ?? 3)
  const speedSec = Number(d.cfg.speed_flag_threshold_sec ?? 20)

  // Rater codes R001… in order of session creation
  const sesSorted = [...d.sessions].sort((a, b) => a.created_at.localeCompare(b.created_at))
  const code = new Map(sesSorted.map((s, i) => [s.session_id, `R${String(i + 1).padStart(3, '0')}`]))
  // Batch number per session
  const batchNo = new Map<string, number>()
  const perSes = new Map<string, Bat[]>()
  for (const b of d.batches) perSes.set(b.session_id, [...(perSes.get(b.session_id) ?? []), b])
  for (const list of perSes.values()) list.sort((a, b) => a.created_at.localeCompare(b.created_at)).forEach((b, i) => batchNo.set(b.batch_id, i + 1))

  // 1. Raw scores, long format
  const raw: Row[] = d.scores.map((s) => {
    const it = itemBy.get(s.batch_item_id); const r = reqBy.get(s.req_id); const se = sesBy.get(s.session_id)
    return {
      rater_code: code.get(s.session_id) ?? null, session_id: s.session_id,
      annotator_type: se?.annotator_type ?? null, annotator_type_other: se?.annotator_type_other ?? null,
      language_pref: se?.language_pref ?? null, session_excluded: se?.excluded ?? null,
      batch_number: it ? batchNo.get(it.batch_id) ?? null : null, position: it?.position ?? null,
      batch_item_id: s.batch_item_id, is_attention_check: it?.is_attention_check ?? null,
      req_id: s.req_id, base_id: r?.base_id ?? null, project_id: r?.project_id ?? null, language_tag: s.annotation_language,
      requirement_text: (s.annotation_language === 'EN' ? r?.text_en : r?.text_tr) ?? null, text_en: r?.text_en ?? null, text_tr: r?.text_tr ?? null,
      config_version: it ? cfgLabel.get(batBy.get(it.batch_id)?.config_id ?? -1) ?? null : null,
      metric_id: s.metric_id, score: s.score, note: s.note,
      round: s.round, time_seconds_item: it?.time_seconds ?? null, created_at: s.created_at,
    }
  }).sort((a, b) => String(a.rater_code).localeCompare(String(b.rater_code)) || Number(a.batch_number) - Number(b.batch_number)
    || Number(a.position) - Number(b.position) || String(a.metric_id).localeCompare(String(b.metric_id)))

  // Analysis rows: no attention-check duplicates, no excluded sessions
  const valid = d.scores.filter((s) => !itemBy.get(s.batch_item_id)?.is_attention_check && !sesBy.get(s.session_id)?.excluded)

  // 2. Wide matrices per metric: rows = requirement, columns = rater (score; blank = not scored by that rater)
  const raters = sesSorted.filter((s) => !s.excluded).map((s) => s.session_id)
  const matrices: Record<string, Row[]> = {}
  for (const m of METRIC_IDS) {
    const cell = new Map<string, number | string>()
    const reqIds = new Set<string>()
    for (const s of valid.filter((x) => x.metric_id === m)) {
      reqIds.add(s.req_id); cell.set(`${s.req_id}|${s.session_id}`, s.score)
    }
    matrices[`Matris_${m}`] = [...reqIds].sort().map((rid) => {
      const r = reqBy.get(rid)
      const row: Row = { req_id: rid, base_id: r?.base_id ?? null, language_tag: r?.language_tag ?? null }
      for (const sid of raters) row[code.get(sid)!] = cell.get(`${rid}|${sid}`) ?? null
      return row
    })
  }

  // 3. Requirement summary per metric (+ reference score)
  const summary: Row[] = []
  for (const r of [...d.reqs].sort((a, b) => a.req_id.localeCompare(b.req_id))) {
    const nSes = new Set(valid.filter((s) => s.req_id === r.req_id).map((s) => s.session_id)).size
    for (const m of METRIC_IDS) {
      const rows = valid.filter((s) => s.req_id === r.req_id && s.metric_id === m)
      const vals = rows.map((s) => s.score)
      const ref = refBy.get(`${r.base_id ?? r.req_id}|${m}`)
      const mu = mean(vals)
      summary.push({
        req_id: r.req_id, base_id: r.base_id, language_tag: r.language_tag, project_id: r.project_id, eligible: r.eligible,
        metric_id: m, n_raters: nSes, n_scores: vals.length,
        n0: vals.filter((v) => v === 0).length, n1: vals.filter((v) => v === 1).length, n2: vals.filter((v) => v === 2).length,
        mean: r3(mu), median: median(vals), sd: r3(sd(vals)),
        reference_score: ref ? ref.llm_score : null,
        reference_model: ref?.llm_model ?? null,
        mean_minus_reference: ref && mu != null ? r3(mu - ref.llm_score) : null,
        coverage_met: nSes >= target,
      })
    }
  }

  // 4. Sessions + quality control
  const sessions: Row[] = sesSorted.map((se) => {
    const sItems = d.items.filter((i) => batBy.get(i.batch_id)?.session_id === se.session_id)
    const times = sItems.map((i) => i.time_seconds).filter((t): t is number => t != null)
    const scoresOf = (itemId: number) => new Map(d.scores.filter((s) => s.batch_item_id === itemId).map((s) => [s.metric_id, s]))
    let acPairs = 0, acSame = 0, acMax = 0
    for (const ac of sItems.filter((i) => i.is_attention_check)) {
      const orig = sItems.find((i) => i.batch_id === ac.batch_id && !i.is_attention_check && i.req_id === ac.req_id)
      if (!orig) continue
      const a = scoresOf(ac.batch_item_id), o = scoresOf(orig.batch_item_id)
      for (const m of METRIC_IDS) {
        const x = a.get(m), y = o.get(m)
        if (!x || !y) continue
        acPairs++
        if (x.score === y.score) acSame++
        acMax = Math.max(acMax, Math.abs(x.score - y.score))
      }
    }
    const med = median(times)
    return {
      rater_code: code.get(se.session_id)!, session_id: se.session_id, language_pref: se.language_pref,
      annotator_type: se.annotator_type, annotator_type_other: se.annotator_type_other, consent_version: se.consent_version,
      created_at: se.created_at, last_active_at: se.last_active_at, batches_completed: se.batches_completed,
      items_assigned: sItems.length, items_scored: new Set(d.scores.filter((s) => s.session_id === se.session_id).map((s) => s.batch_item_id)).size,
      median_seconds_per_item: r3(med), speed_flag: med != null && med < speedSec,
      attention_metric_pairs: acPairs, attention_exact_match_pct: acPairs ? Math.round((100 * acSame) / acPairs) : null,
      attention_max_abs_diff: acPairs ? acMax : null,
      flag_consistency: se.flag_consistency ?? null, flag_speed: se.flag_speed ?? null, ended_at: se.ended_at ?? null, withdrawn_at: se.withdrawn_at ?? null,
      excluded: se.excluded, comment: se.comment,
    }
  })

  const info: Row[] = [
    { key: 'exported_at', value: new Date().toISOString() },
    { key: 'rubric_version', value: d.rubricVersion },
    { key: 'filter', value: filterNote || 'none' },
    { key: 'analysis_rows', value: 'Matris_* and Gereksinim_Ozeti exclude attention-check duplicates and excluded sessions; Puanlar_Ham includes everything.' },
    { key: 'matrix_cells', value: '0/1/2 = score, empty = not scored by that rater.' },
    { key: 'flags', value: 'flag_consistency / flag_speed are computed by the server at batch completion (FR-QC-003/004).' },
    { key: 'config_version', value: 'Configuration (rubric + texts) version active when the batch was assigned (FR-CFG-VER-002).' },
    ...Object.entries(d.cfg).map(([k, v]) => ({ key: `app_config.${k}`, value: typeof v === 'object' ? JSON.stringify(v) : (v as string | number) })),
  ]

  return { Bilgi: info, Puanlar_Ham: raw, ...matrices, Gereksinim_Ozeti: summary, Oturumlar_QC: sessions }
}
