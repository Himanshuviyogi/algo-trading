import path from 'path'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  // Build with /admin/ base so assets resolve correctly when served at /admin
  base: '/admin/',
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  build: {
    outDir: '../price-server/admin-dist',
    emptyOutDir: true,
  },
  server: {
    port: 5173,
    // Proxy price-server calls to avoid CORS in dev
    proxy: {
      '/api/price-server': {
        target: 'http://31.172.87.141:3002',
        changeOrigin: true,
        rewrite: (p) => p.replace(/^\/api\/price-server/, ''),
      },
    },
  },
})
