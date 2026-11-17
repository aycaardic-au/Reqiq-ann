/**
 * Admin screen texts (researcher-facing). Kept in code: FR-CFG-TXT-003 (ADD-02 v0.9) limits
 * FR-CFG-TXT-001 to annotator-facing texts.
 */
export const A = {
  title: 'Yönetim paneli',
  subtitle: 'Gereksinim Kalite Metrikleri Değerlendirme Aracı',
  login_title: 'Yönetici girişi',
  email: 'E-posta',
  password: 'Şifre',
  login: 'Giriş yap',
  login_error: 'Giriş yapılamadı. E-posta ve şifreyi kontrol edin.',
  not_admin: 'Bu hesabın yönetici yetkisi yok.',
  logout: 'Çıkış',
  annotator_view: 'Katılımcı ekranı',
  refresh: 'Yenile',
  tabs: { dashboard: 'Özet', sessions: 'Oturumlar', requirements: 'Gereksinimler', params: 'Parametreler', export: 'Dışa aktar', import: 'İçe aktar' },
  loading: 'Yükleniyor…',
  error: 'Veriler yüklenemedi: ',
  saved: 'Kaydedildi.',
  save: 'Kaydet',
  not_configured: 'Supabase bağlantısı tanımlı değil.',
}

/** K3 optional answers (migration 0038): admin labels. 'none' = empty (not asked, skipped or older session). */
export const PROFILE_LABELS: Record<string, Record<string, string>> = {
  role_category: {
    requirements_engineer: 'Gereksinim mühendisi', systems_engineer: 'Sistem mühendisi', test_engineer: 'Test mühendisi',
    project_manager: 'Proje yöneticisi', software_developer: 'Yazılım geliştirici', other: 'Diğer',
    prefer_not_to_say: 'Belirtmek istemiyor', none: 'Boş',
  },
  experience_band: { '0-2': '0–2 yıl', '3-5': '3–5 yıl', '6-10': '6–10 yıl', '11-20': '11–20 yıl', '20+': '20+ yıl', prefer_not_to_say: 'Belirtmek istemiyor', none: 'Boş' },
  study_level: {
    year_1: '1. sınıf', year_2: '2. sınıf', year_3: '3. sınıf', year_4: '4. sınıf', masters: 'Yüksek lisans', phd: 'Doktora',
    other: 'Diğer', prefer_not_to_say: 'Belirtmek istemiyor', none: 'Boş',
  },
}

/** One-line summary of a session's optional K3 answers for the session list. */
export function profileSummary(r: Record<string, unknown>): string {
  const lab = (field: string, v: unknown) => (v == null || v === '' ? '' : PROFILE_LABELS[field][String(v)] ?? String(v))
  const withOther = (field: string, v: unknown, other: unknown) => {
    const x = lab(field, v)
    return x && other ? `${x} (${String(other)})` : x
  }
  return [
    withOther('role_category', r.role_category, r.role_other),
    lab('experience_band', r.experience_band),
    withOther('study_level', r.study_level, r.study_level_other),
  ].filter(Boolean).join(' · ')
}
