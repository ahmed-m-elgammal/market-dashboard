import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: true,
  },
  build: {
    outDir: 'dist',
    // Private admin dashboard: a public sourcemap would expose the readable
    // source of every screen to anyone who loads it.
    sourcemap: false,
  },
});