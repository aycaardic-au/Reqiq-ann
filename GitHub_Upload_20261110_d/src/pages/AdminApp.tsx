import { useEffect, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { adminDb } from '../lib/adminClient'
import Dashboard from '../admin/Dashboard'
import Params from '../admin/Params'
import Export from '../admin/Export'
import Import from '../admin/Import'
import { A } from '../admin/texts'

type Tab = keyof typeof A.tabs

/** Admin panel at /#/admin (D-29): Supabase Auth login; users must be listed in `admins` (migration 0015). */
export default function AdminApp() {
  const [session, setSession] = useState<Session | null>(null)
  const [ready, setReady] = useState(!adminDb)
  const [adminOf, setAdminOf] = useState<{ uid: string; ok: boolean } | null>(null)
  const [tab, setTab] = useState<Tab>('dashboard')
  const [tick, setTick] = useState(0)

  useEffect(() => {
    document.title = `${A.title} · ${A.subtitle}`
    if (!adminDb) return
    adminDb.auth.getSession().then(({ data }) => { setSession(data.session); setReady(true) })
    const { data: sub } = adminDb.auth.onAuthStateChange((_e, s) => setSession(s))
    return () => sub.subscription.unsubscribe()
  }, [])

  useEffect(() => {
    if (!session || !adminDb) return
    const uid = session.user.id
    adminDb.rpc('is_admin').then(({ data }) => setAdminOf({ uid, ok: Boolean(data) }))
  }, [session])
  const isAdmin = session && adminOf?.uid === session.user.id ? adminOf.ok : null

  if (!adminDb) return <main className="narrow"><section className="panel"><p>{A.not_configured}</p></section></main>
  if (!ready) return <main className="narrow"><div className="spinner" /></main>
  if (!session) return <Login />
  if (isAdmin === null) return <main className="narrow"><div className="spinner" /></main>
  if (!isAdmin) {
    return (
      <main className="narrow"><section className="panel">
        <p className="err">{A.not_admin}</p>
        <button className="btn btn-quiet" onClick={() => adminDb!.auth.signOut()}>{A.logout}</button>
      </section></main>
    )
  }

  return (
    <>
      <header className="top">
        <div className="top-in wide">
          <span className="appname">{A.title}</span>
          <nav className="tabs" aria-label={A.title}>
            {(Object.keys(A.tabs) as Tab[]).map((k) => (
              <button key={k} className={`tab${tab === k ? ' on' : ''}`} aria-current={tab === k} onClick={() => setTab(k)}>{A.tabs[k]}</button>
            ))}
          </nav>
          <span className="row">
            <button className="link" onClick={() => setTick(tick + 1)}>{A.refresh}</button>
            <a className="link" href="#/">{A.annotator_view}</a>
            <button className="link" onClick={() => adminDb!.auth.signOut()}>{A.logout}</button>
          </span>
        </div>
      </header>
      <main className="admin">
        {tab === 'dashboard' && <Dashboard tick={tick} />}
        {tab === 'params' && <Params key={tick} />}
        {tab === 'export' && <Export />}
        {tab === 'import' && <Import />}
      </main>
    </>
  )
}

function Login() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [err, setErr] = useState(false)
  const [busy, setBusy] = useState(false)
  const submit = async (e: React.FormEvent) => {
    e.preventDefault(); setBusy(true); setErr(false)
    const { error } = await adminDb!.auth.signInWithPassword({ email, password })
    if (error) setErr(true)
    setBusy(false)
  }
  return (
    <main className="narrow">
      <form className="panel login" onSubmit={submit}>
        <h1>{A.login_title}</h1>
        <p className="muted">{A.subtitle}</p>
        <label className="param"><span className="param-label">{A.email}</span>
          <input type="email" autoComplete="username" required value={email} onChange={(e) => setEmail(e.target.value)} /></label>
        <label className="param"><span className="param-label">{A.password}</span>
          <input type="password" autoComplete="current-password" required value={password} onChange={(e) => setPassword(e.target.value)} /></label>
        {err && <p className="err" role="alert">{A.login_error}</p>}
        <button className="btn btn-primary btn-block" type="submit" disabled={busy}>{A.login}</button>
      </form>
    </main>
  )
}
