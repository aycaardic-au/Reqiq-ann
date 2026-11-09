# Gereksinim Kalite Metrikleri Değerlendirme Aracı (ReqIQ-ANN)

Bilingual (EN/TR) web annotation tool for the MSc thesis "Büyük Dil Modelleri Kullanarak Gereksinim
Belirtimlerinin Otomatik Kalite Değerlendirmesi" (Ankara University).
Specification: Drive `TEZ/5.Rubrick/Web_Tool/` — SRS v1.1 + ADD-01 v0.4 (sampling) + ADD-02 v1.0 (screens and texts).

## Stack
React 19 + Vite + TypeScript · HashRouter · Supabase (PostgreSQL, Auth) · GitHub Pages via GitHub Actions.
`xlsx` is loaded only in the admin panel.

## Layout
```
src/pages/AnnotatorApp.tsx   annotator flow K1–K6 + thank-you (state machine, localStorage resume)
src/screens/                 ConsentPage, InfoForm, Intro, AnnotateStep, Annotate, BatchEnd, SessionChrome
src/pages/AdminApp.tsx       admin shell (/#/admin): Özet, Oturumlar, Gereksinimler, Parametreler, Dışa aktar, İçe aktar
src/admin/                   admin views; exportData.ts = pure export builder (filters, sanitising)
src/lib/                     config loader, session + RPC client (retry), admin client, error boundary/reporting
config/                      ui_texts.json (screen texts), rubric_v1.4.json, metric_hints.json
scripts/                     build_ui_texts_sql.py, build_hints.py (generate versioned config SQL)
supabase/migrations/         0001–0019, forward-only, run in order in the Supabase SQL Editor
```

## Local development
```bash
npm ci
npm run dev        # without .env.local: texts from config/*.json, RPCs replaced by an in-memory stub
npm run build && npm run lint
```
With a real backend: `cp .env.example .env.local` and fill in `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`.

## Deployment
1. Run new migrations in order in Supabase → SQL Editor (each file ends with a verify query).
2. Repo secrets `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`; push to `main` → Actions builds and publishes `gh-pages`.
3. Admin account: Supabase → Authentication → Users → Add user (Auto Confirm) → `INSERT INTO admins …` (see 0015) →
   disable "Allow new users to sign up".

## Operations
- Change screen texts / hints / rubric: edit the JSON in `config/`, then admin → İçe aktar (creates a new configuration
  version; older versions stay and can be re-activated).
- Load the full requirement pool / reference labels: admin → İçe aktar (Excel/CSV, template provided).
- Back up: admin → Dışa aktar → Excel, regularly and before any reset.
- After the pilot: admin → Parametreler → "Çalışma verilerini sıfırla" (type SIFIRLA).
- Testing as a participant: `/#/reset` clears this browser's state.

## Security
Only the public publishable key is used in the browser. All tables have RLS; annotators have no direct table access and
write only through SECURITY DEFINER functions with input checks. Admins are Supabase Auth users listed in `admins`.
Exports neutralise spreadsheet formulas. No participant data or secrets are committed to this repository.
