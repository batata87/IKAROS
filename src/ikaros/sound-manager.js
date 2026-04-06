/**
 * Web Audio: looping BGM with low-pass "muffle" that opens with combo multiplier,
 * plus short synthesized "neon pluck" SFX.
 */

const PLUCK_DURATION_SEC = 0.2;

/** C major diatonic from C4: semitone offsets within each octave. */
const C_MAJOR_OFFSETS = [0, 2, 4, 5, 7, 9, 11];

export function scaleIndexToMidi(index) {
  const oct = Math.floor(index / 7);
  const deg = index % 7;
  return 60 + oct * 12 + C_MAJOR_OFFSETS[deg];
}

export function midiToHz(midi) {
  return 440 * Math.pow(2, (midi - 69) / 12);
}

export function createNeonSoundManager(options = {}) {
  const bgmUrl = options.bgmUrl ?? '/sounds/the-steepest-path.mp3';
  const bgmGain = options.bgmGain ?? 0.32;

  let ctx = null;
  let bgmElement = null;
  /** Pre-created while on title screen so the first tap hits a warm cache. */
  let bgmPrewarmElement = null;
  let mediaSource = null;
  let lowpass = null;
  let masterGain = null;
  let bgmStarted = false;
  let targetCutoffHz = 900;
  let comboMultiplierRef = 1;
  /** Visual pulse (~120 BPM) for scanlines / UI. */
  let beatVisualPhase = 0;

  function ensureContext() {
    if (ctx) return ctx;
    const AC = window.AudioContext || window.webkitAudioContext || null;
    if (!AC) return null;
    ctx = new AC();
    masterGain = ctx.createGain();
    masterGain.gain.value = 1;
    masterGain.connect(ctx.destination);

    lowpass = ctx.createBiquadFilter();
    lowpass.type = 'lowpass';
    lowpass.Q.value = 0.85;
    lowpass.frequency.value = 900;
    lowpass.connect(masterGain);

    return ctx;
  }

  function multiplierToCutoffHz(m) {
    const clamped = Math.max(1, Math.min(m, 4.5));
    const t = (clamped - 1) / 3.5;
    const minF = 520;
    const maxF = 14000;
    return minF * Math.pow(maxF / minF, t);
  }

  function prewarmBgm() {
    if (bgmPrewarmElement || bgmElement) return;
    try {
      const a = new Audio(bgmUrl);
      a.preload = 'auto';
      a.crossOrigin = 'anonymous';
      a.load();
      bgmPrewarmElement = a;
    } catch {
      /* ignore */
    }
  }

  function setupBgm() {
    if (bgmElement || !ctx) return;
    bgmElement = bgmPrewarmElement || new Audio(bgmUrl);
    bgmPrewarmElement = null;
    bgmElement.loop = true;
    bgmElement.crossOrigin = 'anonymous';
    bgmElement.preload = 'auto';

    const trackGain = ctx.createGain();
    trackGain.gain.value = bgmGain;

    try {
      mediaSource = ctx.createMediaElementSource(bgmElement);
      mediaSource.connect(trackGain);
      /* BGM only through low-pass; SFX connect straight to master (full brightness). */
      trackGain.connect(lowpass);
    } catch {
      bgmElement.volume = bgmGain;
    }
  }

  return {
    /** Start fetching/decoding BGM before any user gesture (title screen). */
    prewarmBgm,

    /** Call after a user gesture (pointer/touch). Starts AudioContext + BGM. */
    async resume() {
      const c = ensureContext();
      if (!c) return;
      if (c.state === 'suspended') {
        await c.resume();
      }
      setupBgm();
      targetCutoffHz = multiplierToCutoffHz(comboMultiplierRef);
      if (lowpass) {
        lowpass.frequency.setValueAtTime(Math.max(80, targetCutoffHz), c.currentTime);
      }
      if (bgmElement && !bgmStarted) {
        bgmStarted = true;
        bgmElement.play().catch(() => {
          bgmStarted = false;
        });
      }
    },

    /** Combo multiplier 1+ — brighter BGM as value increases. */
    setComboMultiplier(m) {
      comboMultiplierRef = m;
      targetCutoffHz = multiplierToCutoffHz(m);
    },

    getBeatVisualPhase() {
      return beatVisualPhase;
    },

    /** Per-frame smoothing (exponentialRamp is discrete; this eases continuous motion). */
    tickFilter(dt) {
      beatVisualPhase += dt * (Math.PI * 4);
      if (!lowpass || !ctx) return;
      const cur = lowpass.frequency.value;
      const tgt = targetCutoffHz;
      const a = 1 - Math.exp(-10 * Math.min(dt, 0.05));
      const next = cur + (tgt - cur) * a;
      if (Math.abs(next - tgt) < 12) {
        lowpass.frequency.value = tgt;
      } else {
        lowpass.frequency.value = next;
      }
    },

    /**
     * Short neon pluck at the given step in the C-major ladder (0 = C, 1 = D, …).
     */
    playNeonPluck(scaleStepIndex) {
      const c = ensureContext();
      if (!c) return;
      const midi = scaleIndexToMidi(scaleStepIndex);
      const freq = midiToHz(midi);
      const t0 = c.currentTime;
      const dur = PLUCK_DURATION_SEC;

      const osc = c.createOscillator();
      osc.type = 'triangle';
      osc.frequency.setValueAtTime(freq, t0);

      const osc2 = c.createOscillator();
      osc2.type = 'sine';
      osc2.frequency.setValueAtTime(freq * 2.01, t0);

      const gain = c.createGain();
      gain.gain.setValueAtTime(0.0001, t0);
      gain.gain.exponentialRampToValueAtTime(0.22, t0 + 0.012);
      gain.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);

      const g2 = c.createGain();
      g2.gain.value = 0.06;

      osc.connect(gain);
      osc2.connect(g2);
      g2.connect(gain);

      gain.connect(masterGain);

      osc.start(t0);
      osc2.start(t0);
      osc.stop(t0 + dur + 0.02);
      osc2.stop(t0 + dur + 0.02);
    },

    pauseBgm() {
      if (bgmElement) {
        bgmElement.pause();
        bgmStarted = false;
      }
    },

    resumeBgmIfPossible() {
      if (!bgmElement || !ctx) return;
      bgmElement.play().catch(() => {});
      bgmStarted = true;
    },
  };
}
