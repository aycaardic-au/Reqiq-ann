import { Component, type ErrorInfo, type ReactNode } from 'react'
import { logClientError } from './session'

/**
 * NFR-REL-003: a rendering error must not leave a blank page. Shows a fixed bilingual message
 * (FR-CFG-TXT-002: texts cannot come from the configuration when the app itself failed).
 */
export class ErrorBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false }
  static getDerivedStateFromError() { return { failed: true } }
  componentDidCatch(error: Error, info: ErrorInfo) {
    logClientError('render', `${error.message}\n${info.componentStack ?? ''}`.slice(0, 2000))
  }
  render() {
    if (!this.state.failed) return this.props.children
    return (
      <main className="narrow">
        <section className="panel" role="alert">
          <h1 lang="tr">Beklenmeyen bir hata oluştu</h1>
          <p lang="tr">Kaydedilen yanıtlarınız korunuyor. Sayfayı yenileyerek kaldığınız yerden devam edebilirsiniz.</p>
          <p lang="en" className="muted">An unexpected error occurred. Your saved answers are kept. Reload the page to continue.</p>
          <button type="button" className="btn btn-primary" onClick={() => window.location.reload()}>Sayfayı yenile / Reload</button>
        </section>
      </main>
    )
  }
}
