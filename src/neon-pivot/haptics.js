/**
 * Haptics: Vibration API on web; optional native bridge on iOS (window.IkarosNative).
 */

function nativeBridge() {
  return typeof window !== 'undefined' ? window.IkarosNative : null;
}

/** Light impact — release / jump from anchor. */
export function hapticLightRelease() {
  const n = nativeBridge();
  if (n?.lightImpact) {
    n.lightImpact();
    return;
  }
  if (typeof navigator !== 'undefined' && navigator.vibrate) {
    navigator.vibrate(12);
  }
}

/** Medium impact — successful anchor capture. */
export function hapticMediumCapture() {
  const n = nativeBridge();
  if (n?.mediumImpact) {
    n.mediumImpact();
    return;
  }
  if (typeof navigator !== 'undefined' && navigator.vibrate) {
    navigator.vibrate(28);
  }
}

/** Success notification — new personal best at end of run. */
export function hapticSuccess() {
  const n = nativeBridge();
  if (n?.successNotification) {
    n.successNotification();
    return;
  }
  if (typeof navigator !== 'undefined' && navigator.vibrate) {
    navigator.vibrate([35, 55, 35]);
  }
}

export function hapticGameOver(kind) {
  const n = nativeBridge();
  if (kind === 'sun' && n?.heavyImpact) {
    n.heavyImpact();
    return;
  }
  if (typeof navigator !== 'undefined' && navigator.vibrate) {
    navigator.vibrate(kind === 'sun' ? 100 : 80);
  }
}
