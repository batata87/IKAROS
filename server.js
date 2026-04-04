import 'dotenv/config';
import path from 'path';
import { fileURLToPath } from 'url';
import express from 'express';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const isProd =
  process.argv.includes('--prod') ||
  process.env.NODE_ENV === 'production';
const PORT = Number(process.env.PORT) || 3333;

async function main() {
  const app = express();

  /* Some client libs probe same-origin `/models/...`; avoid SPA HTML being returned as JSON. */
  app.use('/models', (req, res) => {
    res.status(404).type('text/plain').send('Not found');
  });

  if (isProd) {
    const dist = path.join(__dirname, 'dist');
    app.use(express.static(dist));
    app.get('*', (req, res, next) => {
      res.sendFile(path.join(dist, 'index.html'), (err) => {
        if (err) next(err);
      });
    });
  } else {
    const { createServer: createViteServer } = await import('vite');
    const vite = await createViteServer({
      root: __dirname,
      configFile: path.join(__dirname, 'vite.config.js'),
      server: { middlewareMode: true },
      appType: 'spa',
    });
    app.use(vite.middlewares);
  }

  app.listen(PORT, '0.0.0.0', () => {
    console.log('');
    console.log(`  IKAROS  →  http://127.0.0.1:${PORT}/`);
    if (!isProd) {
      console.log('            Dev: Vite + static (IKAROS canvas)');
    }
    console.log('');
  });
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
