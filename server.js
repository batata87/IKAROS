import 'dotenv/config';
import path from 'path';
import { fileURLToPath } from 'url';
import express from 'express';
import cors from 'cors';
import OpenAI from 'openai';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const isProd =
  process.argv.includes('--prod') ||
  process.env.NODE_ENV === 'production';
/** Single port for UI + API — avoids 5173/8787 conflicts and proxy issues */
const PORT = Number(process.env.PORT) || 3333;
const SECRET_CONCEPT =
  process.env.IKAROS_SECRET || process.env.LOGIOS_SECRET || 'Eternity';

const openai = process.env.OPENAI_API_KEY
  ? new OpenAI({ apiKey: process.env.OPENAI_API_KEY })
  : null;

function createSyncHandler() {
  return async (req, res) => {
    const word = typeof req.body?.word === 'string' ? req.body.word.trim() : '';
    if (!word) {
      return res.status(400).json({ error: 'word required' });
    }
    if (!openai) {
      return res.status(503).json({ error: 'OPENAI_API_KEY not configured' });
    }

    try {
      const completion = await openai.chat.completions.create({
        model: process.env.OPENAI_MODEL || 'gpt-4o-mini',
        temperature: 0.2,
        max_tokens: 80,
        messages: [
          {
            role: 'system',
            content: `You compare a single user word/phrase to a secret target concept for a game called IKAROS.
The secret concept is: "${SECRET_CONCEPT}".
Respond with ONLY valid JSON: {"score": <integer 0-100>}
Rules:
- score is semantic similarity / conceptual overlap (not spelling).
- Identical or trivial synonym of the secret concept = 100.
- Unrelated = low single digits to ~15.
- Partially related themes scale between roughly 20-95.
No markdown, no explanation, JSON only.`,
          },
          {
            role: 'user',
            content: `User input: ${word.slice(0, 200)}`,
          },
        ],
      });

      const text = completion.choices[0]?.message?.content?.trim() || '';
      let score = 0;
      try {
        const parsed = JSON.parse(text.replace(/^```json\s*|\s*```$/g, ''));
        score = Math.round(Number(parsed.score));
      } catch {
        const m = text.match(/"score"\s*:\s*(\d+)/);
        if (m) score = Math.round(Number(m[1]));
      }
      if (Number.isNaN(score)) score = 0;
      score = Math.min(100, Math.max(0, score));

      return res.json({ score });
    } catch (e) {
      console.error(e);
      return res.status(500).json({ error: 'sync_failed' });
    }
  };
}

async function main() {
  const app = express();
  app.use(cors({ origin: true }));
  app.use(express.json({ limit: '8kb' }));

  // transformers.js may try same-origin `/models/...` before remote Hub URLs.
  // Without this, the SPA fallback returns index.html and JSON.parse fails on `<!DOCTYPE`.
  app.use('/models', (req, res) => {
    res.status(404).type('text/plain').send('Not found');
  });

  app.post('/api/sync', createSyncHandler());

  if (isProd) {
    const dist = path.join(__dirname, 'dist');
    app.use(express.static(dist));
    app.get('*', (req, res, next) => {
      if (req.path.startsWith('/api')) return next();
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
      /* MPA: neon-pivot.html is a second entry; 'spa' can interfere with non-index HTML + HMR. */
      appType: 'mpa',
    });
    app.use(vite.middlewares);
  }

  app.listen(PORT, '0.0.0.0', () => {
    console.log('');
    console.log(`  IKAROS  →  http://127.0.0.1:${PORT}/`);
    console.log(`            (same port: game UI + /api/sync)`);
    if (!isProd) {
      console.log('            Dev: Vite + API in one process.');
    }
    console.log('');
  });
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
