# ReqIQ-ANN

Bilingual (EN/TR) web annotation tool for the ReqIQ MSc thesis (Ankara University).
Specification: `ReqIQ_Annotation_Tool_SRS_v0.3.md` + ADD-01 + ADD-02.

## Stack
React + Vite + TypeScript · HashRouter · Supabase (PostgreSQL) · GitHub Pages via GitHub Actions.

## Local development
```bash
npm install
cp .env.example .env.local   # fill in Supabase URL + PUBLIC publishable key
npm run dev                  # http://localhost:5173/reqiq-ann/
```
Admin route: `/#/admin`.

## Deployment (GitHub Pages)
1. Repo **Settings → Secrets and variables → Actions**: add `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`.
2. Push to `main` → the workflow builds and publishes `dist/` to the `gh-pages` branch.
3. Repo **Settings → Pages**: Source = *Deploy from a branch*, Branch = `gh-pages` / `(root)`.

Site URL: `https://<github-user>.github.io/Reqiq-ann/`

## Security (NFR-SEC-001..004)
- Only the public publishable key is used in the browser.
- The Supabase service-role key and the admin password live **only** in Supabase Edge Function secrets.
- No participant data is ever committed to this repo.

## Layout
```
src/lib/supabase.ts       Supabase client (publishable key)
src/pages/AnnotatorApp    Annotator flow (steps 1–8)
src/pages/AdminApp        Admin dashboard (/#/admin)
supabase/migrations/      SQL schema (step 2)
supabase/functions/       Edge Functions (admin auth, config upload)
.github/workflows/        GitHub Pages deploy
```
