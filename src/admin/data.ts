import { adminDb, fetchAll } from '../lib/adminClient'
import type { Bat, Brf, Cfg, Item, RawData, Ref, Req, Sc, Ses } from './exportData'

/** Loads every table the admin views need (paged reads, RLS: admins only). */
export async function loadAll(): Promise<RawData> {
  const [reqs, sessions, batches, items, scores, refs, configs] = await Promise.all([
    fetchAll<Req>('requirements', 'req_id'), fetchAll<Ses>('sessions', 'created_at'),
    fetchAll<Bat>('batches', 'created_at'), fetchAll<Item>('batch_items', 'batch_item_id'),
    fetchAll<Sc>('scores', 'score_id'), fetchAll<Ref>('reference_labels', 'base_id'),
    fetchAll<Cfg>('rubric_config', 'config_id'),
  ])
  const { data: cfg } = await adminDb!.from('app_config').select('*').eq('id', 1).single()
  // FR-BRF-009: briefing_views has no table grants; read through the admin-only function (migration 0026)
  const { data: briefing, error: briefingError } = await adminDb!.rpc('admin_briefing_views')
  if (briefingError) throw briefingError
  const active = configs.find((c) => c.is_active)
  return { reqs, sessions, batches, items, scores, refs, cfg: cfg ?? {}, rubricVersion: active?.version_label ?? '', configs, briefing: (briefing ?? []) as Brf[] }
}
