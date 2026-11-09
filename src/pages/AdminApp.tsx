/**
 * Admin dashboard (FR-ADM). Reached at /#/admin.
 * Password is validated server-side by a Supabase Edge Function (FR-ADM-001).
 * Step 1 skeleton: implemented in step 10.
 */
export default function AdminApp() {
  return (
    <main id="admin-root" className="page">
      {import.meta.env.DEV && <p className="dev-marker">[dev] admin dashboard</p>}
    </main>
  )
}
