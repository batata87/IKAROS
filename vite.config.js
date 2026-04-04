import path from 'path';
import { fileURLToPath } from 'url';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/** Used by `vite build` and by server.js (middleware mode). Dev URL is server PORT (default 3333). */
export default defineConfig({
  /* IKAROS canvas code is plain JS — skip React/Babel on this tree (avoids dev/HMR oddities). */
  plugins: [react({ exclude: /[\\/]neon-pivot[\\/]/ })],
  build: {
    rollupOptions: {
      input: {
        main: path.resolve(__dirname, 'index.html'),
        neonpivot: path.resolve(__dirname, 'neon-pivot.html'),
      },
    },
  },
});
