import { env, pipeline } from '@xenova/transformers';

const SECRET_CONCEPT = 'Eternity';
const MODEL_ID = 'Xenova/all-MiniLM-L6-v2';
/** Must match installed `@xenova/transformers` — keep in sync with package.json */
const TRANSFORMERS_VERSION = '2.17.2';

// In Vite dev/prod, force model + WASM loading from remote sources.
// Never load from same-origin `/models/...` — the SPA server returns index.html (HTML, not JSON).
env.allowRemoteModels = true;
env.allowLocalModels = false;
env.remoteHost = 'https://huggingface.co/';
env.remotePathTemplate = '{model}/resolve/{revision}/';
env.useBrowserCache = true;
env.backends.onnx.wasm.wasmPaths = `https://cdn.jsdelivr.net/npm/@xenova/transformers@${TRANSFORMERS_VERSION}/dist/`;

const CACHE_PURGE_KEY = 'logios-transformers-cache-purge-v2';

/**
 * Old builds could cache HTML (SPA fallback) under transformers-cache keys for `/models/...`.
 * Purge once so JSON config/model fetches work again.
 */
async function purgeStaleTransformersCache() {
  if (typeof caches === 'undefined') return;
  try {
    if (typeof localStorage !== 'undefined' && localStorage.getItem(CACHE_PURGE_KEY) === '1') {
      return;
    }
    await caches.delete('transformers-cache');
    if (typeof localStorage !== 'undefined') {
      localStorage.setItem(CACHE_PURGE_KEY, '1');
    }
  } catch {
    // ignore
  }
}

let extractorPromise = null;
let secretEmbeddingPromise = null;

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function toVector(output) {
  if (output?.data && typeof output.data.length === 'number') {
    return Array.from(output.data);
  }
  if (Array.isArray(output)) {
    return output.flat(Infinity).map(Number);
  }
  throw new Error('embedding_output_invalid');
}

function cosineSimilarity(a, b) {
  const len = Math.min(a.length, b.length);
  if (!len) return 0;

  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (let i = 0; i < len; i += 1) {
    const av = a[i];
    const bv = b[i];
    dot += av * bv;
    normA += av * av;
    normB += bv * bv;
  }

  if (normA === 0 || normB === 0) return 0;
  return dot / (Math.sqrt(normA) * Math.sqrt(normB));
}

async function getExtractor() {
  if (!extractorPromise) {
    extractorPromise = pipeline('feature-extraction', MODEL_ID);
  }
  return extractorPromise;
}

async function embedText(text) {
  const extractor = await getExtractor();
  const output = await extractor(text, { pooling: 'mean', normalize: true });
  return toVector(output);
}

async function getSecretEmbedding() {
  if (!secretEmbeddingPromise) {
    secretEmbeddingPromise = embedText(SECRET_CONCEPT);
  }
  return secretEmbeddingPromise;
}

export async function warmupLocalSync() {
  try {
    await purgeStaleTransformersCache();
    await getSecretEmbedding();
  } catch (e) {
    // Keep details for UI/console so model boot issues are debuggable.
    console.error('LOGIOS local model warmup failed:', e);
    throw e;
  }
}

export async function scoreWordLocally(word) {
  const [wordVector, secretVector] = await Promise.all([
    embedText(word),
    getSecretEmbedding(),
  ]);

  const similarity = cosineSimilarity(wordVector, secretVector);
  // Similarity is usually [0..1] for this model with normalize=true.
  const score = Math.round(clamp(similarity, 0, 1) * 100);
  return score;
}
