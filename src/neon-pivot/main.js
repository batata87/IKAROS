import { startNeonPivot } from './game.js';
import { runSplashThen } from './splash.js';

const canvas = document.getElementById('game');
const infoEl = document.getElementById('ikaros-info');
const infoBack = document.getElementById('ikaros-info-back');
const menuInfoBtn = document.getElementById('ikaros-menu-info');

function openInfo() {
  /* Splash art often includes “loading” chrome at the bottom; never show through Help. */
  const splash = document.getElementById('ikaros-splash');
  const loadRow = splash?.querySelector('.ikaros-splash__loading');
  if (loadRow) loadRow.style.visibility = 'hidden';
  if (infoEl) infoEl.hidden = false;
}

infoBack?.addEventListener('click', () => {
  if (infoEl) infoEl.hidden = true;
});

menuInfoBtn?.addEventListener('click', (e) => {
  e.preventDefault();
  e.stopPropagation();
  openInfo();
});

if (canvas) {
  runSplashThen(() => {
    /* Wait one frame so layout/viewport size is final after splash DOM removal (avoids 0×0 canvas). */
    requestAnimationFrame(() => {
      try {
        startNeonPivot(canvas, {
          openInfo,
          onUiModeChange: (mode) => {
            if (menuInfoBtn) menuInfoBtn.hidden = mode !== 'title';
          },
        });
      } catch (err) {
        console.error('IKAROS failed to start:', err);
        const pre = document.createElement('pre');
        pre.style.cssText =
          'position:fixed;inset:0;padding:16px;margin:0;background:#1a0505;color:#fcc;z-index:999999;font:12px monospace;white-space:pre-wrap;overflow:auto;';
        pre.textContent = String(err?.stack || err);
        document.body.appendChild(pre);
      }
    });
  });
} else {
  console.error('IKAROS: #game canvas not found');
}
