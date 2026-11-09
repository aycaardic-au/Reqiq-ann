/**
 * Annotator flow container (FR-ONB-001):
 * [1] Language → [2] Welcome → [3] Consent → [4] Background →
 * [5] Calibration → [6] Batch → [7] Batch Complete → [8] Thank-You
 *
 * Step 1 skeleton: screens are implemented in later steps.
 * No user-facing text is hard-coded (FR-CFG-TXT-001); the dev marker
 * below is shown only in local development builds.
 */
export default function AnnotatorApp() {
  return (
    <main id="annotator-root" className="page">
      {import.meta.env.DEV && <p className="dev-marker">[dev] annotator flow</p>}
    </main>
  )
}
