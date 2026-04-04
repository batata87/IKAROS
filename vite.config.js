import path from 'path';
import { fileURLToPath } from 'url';
import { defineConfig } from 'vite';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/** IKAROS canvas game only — single HTML entry at `/`. */
export default defineConfig({
  root: __dirname,
});
