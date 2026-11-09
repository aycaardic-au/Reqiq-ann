import { logClientError } from './session'

/** NFR-REL-003/004: report uncaught errors and unhandled promise rejections (best effort). */
export function installGlobalErrorHandlers(): void {
  window.addEventListener('error', (e) => logClientError('window.error', `${e.message} @ ${e.filename}:${e.lineno}`))
  window.addEventListener('unhandledrejection', (e) => {
    const r = e.reason as { message?: string } | undefined
    logClientError('unhandledrejection', r?.message ?? String(e.reason))
  })
}
