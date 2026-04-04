import { startNeonPivot } from './game.js';
import { runSplashThen } from './splash.js';

const canvas = document.getElementById('game');
const infoEl = document.getElementById('ikaros-info');
const infoBack = document.getElementById('ikaros-info-back');
const menuInfoBtn = document.getElementById('ikaros-menu-info');
const menuStoreBtn = document.getElementById('ikaros-menu-store');
const menuFeedbackBtn = document.getElementById('ikaros-menu-feedback');

const feedbackModal = document.getElementById('ikaros-feedback-modal');
const feedbackBackdrop = feedbackModal?.querySelector('.ikaros-modal__backdrop');
const feedbackCloseX = document.getElementById('ikaros-feedback-close-x');
const feedbackClose = document.getElementById('ikaros-feedback-close');
const feedbackName = document.getElementById('ikaros-feedback-name');
const feedbackMessage = document.getElementById('ikaros-feedback-message');
const feedbackSubmit = document.getElementById('ikaros-feedback-submit');
const feedbackStatus = document.getElementById('ikaros-feedback-status');

const storeModal = document.getElementById('ikaros-store-modal');
const storeBackdrop = storeModal?.querySelector('.ikaros-modal__backdrop');
const storeCloseX = document.getElementById('ikaros-store-close-x');
const storeClose = document.getElementById('ikaros-store-close');

/** @type {{ primeAudio?: () => void } | null} */
let gameApi = null;

function openInfo() {
  /* Splash art often includes “loading” chrome at the bottom; never show through Help. */
  const splash = document.getElementById('ikaros-splash');
  const loadRow = splash?.querySelector('.ikaros-splash__loading');
  if (loadRow) loadRow.style.visibility = 'hidden';
  if (infoEl) infoEl.hidden = false;
}

function closeInfo() {
  if (infoEl) infoEl.hidden = true;
}

function primeAudioFromUi() {
  gameApi?.primeAudio?.();
}

function openFeedbackModal() {
  if (!feedbackModal) return;
  feedbackModal.hidden = false;
  if (feedbackStatus) feedbackStatus.textContent = '';
  if (feedbackSubmit) feedbackSubmit.disabled = false;
  feedbackMessage?.focus();
}

function closeFeedbackModal() {
  if (feedbackModal) feedbackModal.hidden = true;
}

function openStoreModal() {
  if (!storeModal) return;
  storeModal.hidden = false;
}

function closeStoreModal() {
  if (storeModal) storeModal.hidden = true;
}

function setTitleMenuVisible(title) {
  if (menuInfoBtn) menuInfoBtn.hidden = !title;
  if (menuStoreBtn) menuStoreBtn.hidden = !title;
  if (menuFeedbackBtn) menuFeedbackBtn.hidden = !title;
}

infoBack?.addEventListener('click', () => {
  closeInfo();
});

menuInfoBtn?.addEventListener('click', (e) => {
  e.preventDefault();
  e.stopPropagation();
  primeAudioFromUi();
  openInfo();
});

menuStoreBtn?.addEventListener('click', (e) => {
  e.preventDefault();
  e.stopPropagation();
  primeAudioFromUi();
  openStoreModal();
});

menuFeedbackBtn?.addEventListener('click', (e) => {
  e.preventDefault();
  e.stopPropagation();
  primeAudioFromUi();
  openFeedbackModal();
});

function wireModalClose(closeModal, elements) {
  for (const el of elements) {
    el?.addEventListener('click', (e) => {
      e.preventDefault();
      e.stopPropagation();
      closeModal();
    });
  }
}

wireModalClose(closeFeedbackModal, [feedbackBackdrop, feedbackCloseX, feedbackClose]);
wireModalClose(closeStoreModal, [storeBackdrop, storeCloseX, storeClose]);

feedbackSubmit?.addEventListener('click', async (e) => {
  e.preventDefault();
  e.stopPropagation();
  const message = feedbackMessage?.value.trim() ?? '';
  if (!message) {
    if (feedbackStatus) feedbackStatus.textContent = 'Please enter a message.';
    return;
  }
  const name = feedbackName?.value.trim() ?? '';
  if (feedbackSubmit) feedbackSubmit.disabled = true;
  if (feedbackStatus) feedbackStatus.textContent = 'Sending...';

  const body = new URLSearchParams();
  body.set('form-name', 'ikaros-feedback');
  body.set('message', message);
  if (name) body.set('name', name);

  const submitUrl = `${window.location.origin}/`;

  try {
    const res = await fetch(submitUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString(),
    });
    if (res.ok) {
      if (feedbackStatus) feedbackStatus.textContent = 'Thank you!';
      if (feedbackMessage) feedbackMessage.value = '';
      if (feedbackName) feedbackName.value = '';
    } else {
      if (feedbackStatus) feedbackStatus.textContent = `Something went wrong (${res.status}).`;
    }
  } catch {
    if (feedbackStatus) feedbackStatus.textContent = 'Network error.';
  } finally {
    if (feedbackSubmit) feedbackSubmit.disabled = false;
  }
});

if (canvas) {
  runSplashThen(() => {
    /* Wait one frame so layout/viewport size is final after splash DOM removal (avoids 0×0 canvas). */
    requestAnimationFrame(() => {
      try {
        gameApi = startNeonPivot(canvas, {
          openInfo,
          onUiModeChange: (mode) => {
            setTitleMenuVisible(mode === 'title');
          },
        });

        /* First pointer anywhere unlocks audio before the canvas handler runs (welcome screen + faster BGM start). */
        document.addEventListener(
          'pointerdown',
          () => {
            gameApi?.primeAudio?.();
          },
          { capture: true },
        );
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
