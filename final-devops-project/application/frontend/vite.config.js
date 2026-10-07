import { defineConfig } from 'vite';

// During "npm run dev" the browser talks to Vite on :5173 and /api is proxied
// to the backend. In the container image nginx does the same job.
export default defineConfig({
  server: {
    port: 5173,
    proxy: { '/api': process.env.VITE_API_TARGET || 'http://localhost:8401' },
  },
  build: { outDir: 'dist', sourcemap: false },
});
