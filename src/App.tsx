import { HashRouter, Navigate, Route, Routes } from 'react-router-dom'
import AnnotatorApp from './pages/AnnotatorApp'
import AdminApp from './pages/AdminApp'
import Reset from './pages/Reset'

/**
 * HashRouter is used because GitHub Pages has no server-side routing:
 * URLs take the form .../reqiq-ann/#/admin (decision D-01).
 */
export default function App() {
  return (
    <HashRouter>
      <Routes>
        <Route path="/" element={<AnnotatorApp />} />
        <Route path="/admin" element={<AdminApp />} />
        <Route path="/reset" element={<Reset />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </HashRouter>
  )
}
