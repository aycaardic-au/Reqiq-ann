import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// GitHub Pages serves the app at https://<user>.github.io/Reqiq-ann/ (repo name must match this path exactly)
export default defineConfig({
  base: '/Reqiq-ann/',
  plugins: [react()],
})
