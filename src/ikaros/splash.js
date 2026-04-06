const DISPLAY_MS = 2000;
const FADE_MS = 700;

/**
 * Shows the splash DOM for DISPLAY_MS, fades to black, then removes it and runs the callback.
 */
export function runSplashThen(onDone) {
  const el = document.getElementById('ikaros-splash');
  if (!el) {
    onDone();
    return;
  }

  let done = false;
  const finish = () => {
    if (done) return;
    done = true;
    el.remove();
    onDone();
  };

  window.setTimeout(() => {
    const veil = el.querySelector('.ikaros-splash__veil');
    const onEnd = (e) => {
      if (e.propertyName !== 'opacity') return;
      veil?.removeEventListener('transitionend', onEnd);
      finish();
    };
    veil?.addEventListener('transitionend', onEnd);
    el.classList.add('ikaros-splash--exit');
    window.setTimeout(finish, FADE_MS + 200);
  }, DISPLAY_MS);
}
