/**
 * One-time “rate this app” hook after a qualifying game over (StoreKit / Capacitor / native bridge).
 */

const STORAGE_KEY = 'ikaros_store_review_prompted_v1';

export function maybeRequestAppReview(score) {
  if (score < 50) return;
  try {
    if (localStorage.getItem(STORAGE_KEY)) return;
    localStorage.setItem(STORAGE_KEY, '1');
  } catch {
    return;
  }
  const w = typeof window !== 'undefined' ? window : null;
  if (!w) return;
  if (typeof w.IkarosNative?.requestReview === 'function') {
    w.IkarosNative.requestReview();
    return;
  }
  const store = w.Capacitor?.Plugins?.StoreReview ?? w.Capacitor?.Plugins?.AppReview;
  if (store && typeof store.requestReview === 'function') {
    void store.requestReview();
  }
}
