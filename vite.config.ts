import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// GitHub Pages serves the app at https://<user>.github.io/reqiq-ann/
export default defineConfig({
  base: '/reqiq-ann/',
  plugins: [react()],
})
