/**
 * IKAROS — upward-only solar climber (Canvas 2D).
 */

import {
  BIOME_PALETTES,
  drawScreenBackdrop,
  drawWorldBiomeLayer,
  ensureNebulaParticles,
  getBiomeIndex,
  updateGridPhase,
  updateNebulaParticles,
} from './biomes.js';
import {
  createParallaxStarfield,
  drawAtmosphericBackdrop,
  drawCaptureSparks,
  drawIonosphereOverlay,
  drawParallaxStarfield,
  spawnCaptureSparks,
  updateCaptureSparks,
  updateParallaxStarfield,
} from './atmosphere.js';
import { createNeonSoundManager } from './sound-manager.js';
import { maybeRequestAppReview } from './app-review.js';
import {
  hapticGameOver,
  hapticLightRelease,
  hapticMediumCapture,
  hapticSuccess,
} from './haptics.js';

const STORAGE_KEY = 'ikaros_web_hi';
const LEGACY_STORAGE_KEY = 'neon_pivot_web_hi';
const LUX_STORAGE_KEY = 'ikaros_web_lux';
const ORBIT_SCALE_RESET_SEC = 1.5;
const COMBO_CAPTURE_WINDOW_SEC = 0.5;

function loadHi() {
  try {
    const raw =
      localStorage.getItem(STORAGE_KEY) ||
      localStorage.getItem(LEGACY_STORAGE_KEY) ||
      '0';
    return Math.max(0, parseInt(raw, 10) || 0);
  } catch {
    return 0;
  }
}

function saveHi(n) {
  try {
    localStorage.setItem(STORAGE_KEY, String(n));
  } catch {
    /* ignore */
  }
}

function loadLux() {
  try {
    return Math.max(0, parseInt(localStorage.getItem(LUX_STORAGE_KEY) || '0', 10) || 0);
  } catch {
    return 0;
  }
}

function saveLuxBalance(n) {
  try {
    localStorage.setItem(LUX_STORAGE_KEY, String(Math.max(0, n)));
  } catch {
    /* ignore */
  }
}

const State = {
  IDLE: 0,
  ORBITING: 1,
  DASHING: 2,
  GAMEOVER: 3,
  /** Tap to start; high score shown. */
  TITLE: 5,
};

/** Why the run ended — drives game-over copy. */
let deathKind = 'other';

function dist(ax, ay, bx, by) {
  const dx = bx - ax;
  const dy = by - ay;
  return Math.hypot(dx, dy);
}

/** World radius of the player body (must match drawPlayer arc). */
const PLAYER_WORLD_R = 14;
/** Physics orbit: large enough to clear ring art + stroke + glow + player silhouette. */
const ORBIT_RADIUS = 102;
/** Absolute floor for orbit snap (see effectiveOrbitR for visual clearance). */
const MIN_ORBIT_RADIUS = 50;
/** Dash speed at score 0; further bumps only at milestones (see currentDashSpeed). */
const BASE_DASH_SPEED = 600;
/** Each crossed threshold multiplies dash speed by this factor (plateau difficulty). */
const DASH_SPEED_MILESTONE_FACTOR = 1.1;
const DASH_SPEED_MILESTONE_SCORES = [10, 25, 50];
/** Base orbit ω (rad/s); +5°/s per score point (applied in frame from live score). */
const BASE_ORBIT_RAD_PER_SEC = 0.92;
const ORBIT_RAD_PER_SCORE_POINT = (5 * Math.PI) / 180;
/** Hard cap on |ω| so high scores stay controllable (rad/s). */
const MAX_ORBIT_OMEGA_RAD_PER_SEC = 3.85;
/** Icarus melt: ring shrinks 1 → 0.2 over this many seconds (wall clock — always runs smoothly). */
const MELT_DURATION_SEC = 5;
const MELT_SCALE_MIN = 0.2;
/** After this wait on a capture, allow melt to start in the “upward launch” half-orbit if a target is in range (faster than strict ray-only). */
const MELT_PENDING_RELAX_SEC = 0.75;
/** If melt still hasn’t started, force it (anti soft-lock). */
const MELT_HOLD_FORCE_SEC = 14;

function createAnchor(x, y, scorePoints) {
  const orbitR = Math.max(MIN_ORBIT_RADIUS, ORBIT_RADIUS);
  const captureExtra = Math.max(14, 26 - Math.floor(scorePoints / 25) * 2);
  const capR = orbitR + captureExtra;
  const driftMag =
    scorePoints > 30 ? 50 * (scorePoints / 30) : 0;
  const driftVx = driftMag > 0 ? (Math.random() < 0.5 ? -1 : 1) * driftMag : 0;
  return {
    x,
    y,
    orbitR,
    captureR: capR,
    visualR: 40,
    rotDir: Math.random() < 0.5 ? 1 : -1,
    driftVx,
    /** Seconds spent melting while player is on this anchor; null = timer not started yet. */
    meltElapsed: null,
    meltPending: false,
    meltHoldSec: 0,
  };
}

/**
 * @param {HTMLCanvasElement} canvas
 * @param {{ openInfo?: () => void; onUiModeChange?: (mode: 'title' | 'game') => void }} [uiHooks]
 */
export function startNeonPivot(canvas, uiHooks = {}) {
  const ctx = canvas.getContext('2d');
  if (!ctx) {
    console.error('IKAROS: canvas.getContext("2d") returned null');
    return;
  }

  const sound = createNeonSoundManager({
    bgmUrl: '/sounds/the-steepest-path.mp3',
    bgmGain: 0.3,
  });

  let dpr = Math.min(2, window.devicePixelRatio || 1);
  let w = 0;
  let h = 0;
  let cx = 0;
  let cy = 0;
  /** Must be declared before `resize()` — resize() assigns on first run. */
  let parallaxStarfield = null;

  function prefersReducedMotion() {
    return (
      typeof matchMedia !== 'undefined' &&
      matchMedia('(prefers-reduced-motion: reduce)').matches
    );
  }

  function prefersCoarsePointer() {
    return (
      typeof matchMedia !== 'undefined' && matchMedia('(pointer: coarse)').matches
    );
  }

  function resize() {
    w = Math.max(1, window.innerWidth || document.documentElement?.clientWidth || 1);
    const rawDpr = Math.min(2, window.devicePixelRatio || 1);
    const narrow = w <= 560;
    const coarse = prefersCoarsePointer();
    dpr = narrow || coarse ? Math.min(1.35, rawDpr) : rawDpr;
    h = Math.max(
      1,
      window.innerHeight || document.documentElement?.clientHeight || 1,
    );
    canvas.width = Math.floor(w * dpr);
    canvas.height = Math.floor(h * dpr);
    canvas.style.width = `${w}px`;
    canvas.style.height = `${h}px`;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    cx = w * 0.5;
    cy = h * 0.5;
    parallaxStarfield = createParallaxStarfield(w, h);
  }
  resize();
  window.addEventListener('resize', resize);

  let state = State.IDLE;
  let highScore = loadHi();
  let totalLux = loadLux();
  let score = 0;
  /** Title screen animation clock (orbit + subtitle pulse). */
  let titleMenuPhase = 0;
  let titleBgmPrewarmDone = false;
  let menuUiModePrev = /** @type {'title' | 'game' | null} */ (null);

  function syncMenuUiMode() {
    const mode = state === State.TITLE ? 'title' : 'game';
    if (mode === menuUiModePrev) return;
    menuUiModePrev = mode;
    uiHooks.onUiModeChange?.(mode);
  }
  /** Personal best at the moment the current run started (for end-of-run record haptic). */
  let highScoreAtRunStart = 0;

  function currentDashSpeed() {
    let v = BASE_DASH_SPEED;
    for (const m of DASH_SPEED_MILESTONE_SCORES) {
      if (score >= m) v *= DASH_SPEED_MILESTONE_FACTOR;
    }
    return v;
  }

  function orbitOmega() {
    const raw = BASE_ORBIT_RAD_PER_SEC + score * ORBIT_RAD_PER_SCORE_POINT;
    return Math.min(MAX_ORBIT_OMEGA_RAD_PER_SEC, raw);
  }

  /** Dashed “trajectory” line length scales with speed / score. */
  function trajectoryGhostLen() {
    let ds = currentDashSpeed();
    if (state === State.DASHING) {
      ds = Math.max(ds, Math.hypot(vx, vy));
    }
    return Math.min(
      620,
      200 + (ds - BASE_DASH_SPEED) * 0.55 + Math.min(score, 100) * 2.2,
    );
  }

  function getTrailGhostCount() {
    let spd = currentDashSpeed();
    if (state === State.DASHING) {
      spd = Math.max(spd, Math.hypot(vx, vy));
    }
    return Math.min(
      20,
      6 + Math.floor(score / 3) + Math.floor(Math.max(0, spd - BASE_DASH_SPEED) / 65),
    );
  }

  function isTerminalState() {
    return state === State.GAMEOVER;
  }

  function isTitleState() {
    return state === State.TITLE;
  }

  const anchors = [];
  let anchorIndex = 0;
  let orbitAngle = Math.PI * 0.5;
  let px = 0;
  let py = 0;
  let vx = 0;
  let vy = 0;
  /** Fixed world velocity for the current dash (set on release / melt; never rotated mid-flight). */
  let dashVelX = 0;
  let dashVelY = 0;

  /** Camera top (world Y). Y grows downward; smaller Y = higher on screen. Only moves up (never increases). */
  let camTop = 0;
  /** Best (minimum) world Y the player has reached — drives camera. */
  let peakPlayerY = Infinity;
  /** Smoothed toward peakPlayerY so camera (and parallax delta) don’t jump on capture snaps. */
  let peakSmoothed = Infinity;
  /** Successful anchor captures this run; every 10 bumps auto-scroll. */
  let jumpCount = 0;
  /** Upward camera creep (world px/s); smaller camTop = camera “rises”. */
  let autoScrollPxPerSec = 0;

  const TIME_DILATION_NEAR = 0.4;
  const TIME_DILATION_EDGE_MARGIN = 95;

  const CULL_BELOW_CAMERA = 800;
  /** Glowing pickups between anchors; persist in localStorage. */
  const LUX_SPAWN_CHANCE = 0.4;
  const LUX_COLLECT_DIST = 24;
  const HORIZONTAL_PAD = 40;
  /** Min vertical distance between anchor centers so rings, glow, and orbits don’t stack on each other. */
  const MIN_ANCHOR_CENTER_GAP_Y = 168;

  let shakeRemain = 0;
  let shakeDuration = 0;
  let shakeMag = 0;

  /** Previous camera top for parallax (world px). */
  let prevCamTop = null;
  /** Previous player Y for parallax blend during upward dash (avoids “frozen stars” when cam lags). */
  let prevPyParallax = null;
  /** Cyan spark burst on anchor catch (world space). */
  const sparkParticles = [];
  let ionosphereScroll = 0;
  /** Smoothed squash/stretch for player dot. */
  let playerVisSX = 1;
  let playerVisSY = 1;

  const posHistory = [];
  /** Downward launch (vy > 0): no anchor capture until next orbit. */
  let downwardDashNoCapture = false;
  /** World Y of anchor left when dashing (keeps one-way gate if that anchor was removed). */
  let dashPrevAnchorWorldY = null;

  /** Seconds (performance.now / 1000) when player last released a dash — for capture combo. */
  let lastReleaseTimeSec = -1e9;
  let comboPopupRemain = 0;

  /** World-space LUX sparks (spawned between anchors). */
  const luxPickups = [];

  /** C-major ladder step for next pluck (0 = C, 1 = D, …). Reset after long orbit. */
  let scaleCatchIndex = 0;
  /** Time on current anchor while orbiting — resets on capture. */
  let orbitTimeSec = 0;
  /** Drives BGM low-pass opening (quick-chain captures). */
  let comboMultiplier = 1;

  /** Seconds spent in current dash — avoids soft-lock when no anchor is hittable. */
  let dashAgeSec = 0;
  /** Debounce restart so pointer + click + touch don't triple-fire. */
  let restartCooldownSec = 0;
  let shakePhase = 0;

  let gridPhase = 0;
  /** Slow drift for sun glow. */
  let sunPhase = 0;
  const nebulaParticles = [];

  /** Seconds of ring flash on the anchor just captured (decays at frame start). */
  let captureFlashRemain = 0;

  function meltProgressU(a) {
    if (a == null || a.meltElapsed == null) return 0;
    return Math.max(0, Math.min(1, a.meltElapsed / MELT_DURATION_SEC));
  }

  /** Melt timer running (not waiting for a fair jump window). */
  function meltTimerActive(a) {
    return a != null && a.meltElapsed != null && !a.meltPending;
  }

  /**
   * One-hop spacing for spawn (anchor-center to anchor-center): ghost chord + capture + orbit slack.
   */
  function estimateJumpReachFromAnchor(refA) {
    const ghost = trajectoryGhostLen();
    const cap = refA ? effectiveCaptureR(refA) : 90;
    const orbitSlack = refA ? effectiveOrbitR(refA) * 0.45 + 32 : 95;
    return ghost + cap + orbitSlack;
  }

  /**
   * Reach from current player position while orbiting `fromA` (accounts for orbit offset vs anchor center).
   */
  function playerJumpReachPx(fromA) {
    const ghost = trajectoryGhostLen();
    const orbitSlack = fromA ? effectiveOrbitR(fromA) * 0.72 + PLAYER_WORLD_R + 32 : 115;
    return ghost * 1.08 + orbitSlack;
  }

  function getTopAnchor() {
    if (anchors.length === 0) return null;
    let best = anchors[0];
    for (const a of anchors) {
      if (a.y < best.y) best = a;
    }
    return best;
  }

  /**
   * True when the **current** orbit tangent matches a real release: upward-only dash allowed,
   * and the straight dash ray passes through some higher anchor’s capture disk (same rules as
   * launchFromOrbit + tryCapture). Avoids starting the shrink while the player is in a “dead”
   * half-orbit or aimed away from the next ring.
   */
  function hasFairJumpWindowNow(fromA) {
    if (!fromA || anchors.length < 2) return false;
    let { x: tx, y: ty } = getOrbitTangentUnit();
    const tn = Math.hypot(tx, ty) || 1;
    tx /= tn;
    ty /= tn;
    if (ty > 0) return false;

    const reach = playerJumpReachPx(fromA);
    const maxAlong = trajectoryGhostLen() * 1.5;

    for (const b of anchors) {
      if (b === fromA) continue;
      if (b.y >= fromA.y - 2) continue;
      const cap = effectiveCaptureR(b);
      const d = dist(px, py, b.x, b.y);
      if (d > reach + cap * 1.06) continue;

      const tAlong = (b.x - px) * tx + (b.y - py) * ty;
      if (tAlong < 10 || tAlong > maxAlong) continue;
      const perp = Math.abs((b.x - px) * ty - (b.y - py) * tx);
      if (perp <= cap * 1.18) return true;
    }
    return false;
  }

  /** Loose reach check: any higher anchor within jump distance from px/py (no ray alignment). */
  function hasReachableTargetDistanceOnly(fromA) {
    if (!fromA || anchors.length < 2) return false;
    const reach = playerJumpReachPx(fromA);
    for (const b of anchors) {
      if (b === fromA) continue;
      if (b.y >= fromA.y - 2) continue;
      const d = dist(px, py, b.x, b.y);
      if (d <= reach + effectiveCaptureR(b) * 1.05) return true;
    }
    return false;
  }

  function smoothstep01(t) {
    const x = Math.max(0, Math.min(1, t));
    return x * x * (3 - 2 * x);
  }

  /** Ring + stroke: cyan → bright red as melt completes (u = 0…1). */
  function meltRingColors(uSmooth) {
    const t = smoothstep01(uSmooth);
    const r = Math.round(lerp(0, 255, t));
    const g = Math.round(lerp(255, 55, t));
    const b = Math.round(lerp(255, 65, t));
    const a = lerp(0.9, 1, t);
    return { r, g, b, a };
  }

  function meltVisualScale(a) {
    if (!meltTimerActive(a)) return 1;
    const u = meltProgressU(a);
    return 1 + (MELT_SCALE_MIN - 1) * u;
  }

  /** Orbit radius for player physics — fixed circle (melt is visual-only on the ring). */
  function effectiveOrbitR(a) {
    if (!a) return MIN_ORBIT_RADIUS;
    const clearOfRingArt = a.visualR + 2 + 20 + PLAYER_WORLD_R + 14;
    return Math.max(MIN_ORBIT_RADIUS, a.orbitR, clearOfRingArt);
  }

  function effectiveCaptureR(a) {
    if (!a) return 0;
    return a.captureR;
  }

  function oneWayPrevWorldY() {
    if (dashPrevAnchorWorldY != null) return dashPrevAnchorWorldY;
    const p = anchors[anchorIndex];
    return p != null ? p.y : NaN;
  }

  function updateAnchorDrift(dt) {
    const minAx = HORIZONTAL_PAD + ORBIT_RADIUS;
    const maxAx = w - HORIZONTAL_PAD - ORBIT_RADIUS;
    if (minAx > maxAx) return;
    /* Moving the anchor you’re orbiting slides the whole circle; combined with rotation
       that summed to long stretches of velocity opposing the visible spin (~“backward”). */
    const locked =
      state === State.ORBITING ? anchors[anchorIndex] : null;
    for (const a of anchors) {
      if (locked != null && a === locked) continue;
      let dv = a.driftVx ?? 0;
      if (dv === 0) continue;
      a.x += dv * dt;
      if (a.x <= minAx) {
        a.x = minAx;
        a.driftVx = Math.abs(dv);
      } else if (a.x >= maxAx) {
        a.x = maxAx;
        a.driftVx = -Math.abs(dv);
      }
    }
  }

  /** —— AnchorManager (spawn / cull) —— */

  function getHighestAnchorWorldY() {
    if (anchors.length === 0) return py;
    let best = Infinity;
    for (const a of anchors) {
      if (a.y < best) best = a.y;
    }
    return best;
  }

  /**
   * Adaptive spawn: easy early (nearby + under the player’s X), harder as score rises.
   * t ∈ [0,1] ~ first ~40 points then stays maxed.
   */
  function getSpawnDifficultyT() {
    return Math.min(1, score / 40);
  }

  /** Lateral bias from the anchor you’re on (stable); avoids bogus px before init. */
  function spawnLateralRefX() {
    const cur = anchors[anchorIndex];
    if (cur) return cur.x;
    return anchors[0]?.x ?? cx;
  }

  /** AnchorManager: next anchor above the highest one; gap & lateral spread scale with difficulty. */
  function spawnNextAnchor() {
    const ref = getTopAnchor();
    const topY = ref ? ref.y : getHighestAnchorWorldY();
    const refX = ref ? ref.x : spawnLateralRefX();
    const playableW = Math.max(60, w - 2 * HORIZONTAL_PAD);
    const jumpMax = Math.max(
      MIN_ANCHOR_CENTER_GAP_Y,
      ref ? estimateJumpReachFromAnchor(ref) * 0.96 : 320,
    );

    /* First target after the tutorial anchor: almost straight up, tiny sideways offset. */
    const onlyStarter = score === 0 && anchors.length === 1;

    function clampSpawnToJumpRange(nx, ny) {
      if (!ref) return { nx, ny };
      const d0 = Math.hypot(nx - ref.x, ny - ref.y);
      if (d0 <= jumpMax || d0 < 1) return { nx, ny };
      const s = jumpMax / d0;
      return {
        nx: ref.x + (nx - ref.x) * s,
        ny: ref.y + (ny - ref.y) * s,
      };
    }

    if (onlyStarter) {
      const a0 = anchors[0];
      const spreadY = Math.min(72, Math.max(8, jumpMax - MIN_ANCHOR_CENTER_GAP_Y));
      let offsetY = MIN_ANCHOR_CENTER_GAP_Y + Math.random() * spreadY;
      offsetY = Math.min(offsetY, jumpMax);
      offsetY = Math.max(MIN_ANCHOR_CENTER_GAP_Y, offsetY);
      const minAx = HORIZONTAL_PAD + ORBIT_RADIUS;
      const maxAx = w - HORIZONTAL_PAD - ORBIT_RADIUS;
      let nx =
        minAx <= maxAx
          ? Math.min(maxAx, Math.max(minAx, a0.x + (Math.random() - 0.5) * 72))
          : Math.min(
              w - HORIZONTAL_PAD,
              Math.max(HORIZONTAL_PAD, a0.x + (Math.random() - 0.5) * 72),
            );
      let ny = topY - offsetY;
      ({ nx, ny } = clampSpawnToJumpRange(nx, ny));
      if (minAx <= maxAx) {
        nx = Math.min(maxAx, Math.max(minAx, nx));
      } else {
        nx = Math.min(w - HORIZONTAL_PAD, Math.max(HORIZONTAL_PAD, nx));
      }
      anchors.push(createAnchor(nx, ny, score));
      maybeSpawnLuxBetweenAnchors(a0, anchors[anchors.length - 1]);
      return;
    }

    const t = getSpawnDifficultyT();

    /* Vertical gap (world px “up”): short early, long later — capped vs viewport & jump reach. */
    const gapMin = 88 + t * 255;
    const gapMax = 155 + t * 475;
    const gapCap = Math.max(gapMin + 40, h * 0.78);
    const gapHi = Math.min(gapMax, gapCap);
    let offsetY = Math.max(
      MIN_ANCHOR_CENTER_GAP_Y,
      gapMin + Math.random() * (gapHi - gapMin),
    );
    offsetY = Math.min(offsetY, jumpMax);
    offsetY = Math.max(MIN_ANCHOR_CENTER_GAP_Y, offsetY);

    /* Horizontal: early = tight band around ref; late = full width */
    let nx;
    if (t < 0.2) {
      const spread = playableW * (0.22 + t * 0.45);
      nx = refX + (Math.random() - 0.5) * spread;
    } else if (t < 0.55) {
      const spread = playableW * (0.38 + (t - 0.2) * 0.88);
      nx = refX + (Math.random() - 0.5) * spread;
    } else {
      const bias = (1 - t) * 0.35;
      const randX = HORIZONTAL_PAD + Math.random() * playableW;
      const nearX = refX + (Math.random() - 0.5) * playableW * 0.55;
      nx = nearX * bias + randX * (1 - bias);
    }
    const minAx = HORIZONTAL_PAD + ORBIT_RADIUS;
    const maxAx = w - HORIZONTAL_PAD - ORBIT_RADIUS;
    if (minAx <= maxAx) {
      nx = Math.min(maxAx, Math.max(minAx, nx));
    } else {
      nx = Math.min(w - HORIZONTAL_PAD, Math.max(HORIZONTAL_PAD, nx));
    }

    let ny = topY - offsetY;
    ({ nx, ny } = clampSpawnToJumpRange(nx, ny));
    if (minAx <= maxAx) {
      nx = Math.min(maxAx, Math.max(minAx, nx));
    } else {
      nx = Math.min(w - HORIZONTAL_PAD, Math.max(HORIZONTAL_PAD, nx));
    }
    anchors.push(createAnchor(nx, ny, score));
    maybeSpawnLuxBetweenAnchors(ref, anchors[anchors.length - 1]);
  }

  function grantLux(amount) {
    if (amount <= 0) return;
    totalLux += amount;
    saveLuxBalance(totalLux);
  }

  function maybeSpawnLuxBetweenAnchors(fromA, toA) {
    if (!fromA || !toA) return;
    if (Math.random() > LUX_SPAWN_CHANCE) return;
    const u = 0.2 + Math.random() * 0.58;
    let lx = fromA.x + (toA.x - fromA.x) * u;
    let ly = fromA.y + (toA.y - fromA.y) * u;
    lx += (Math.random() - 0.5) * 100;
    ly += (Math.random() - 0.5) * 82;
    luxPickups.push({ x: lx, y: ly });
  }

  function cullLuxPickupsFarBelow() {
    const threshold = camTop + h + CULL_BELOW_CAMERA;
    for (let i = luxPickups.length - 1; i >= 0; i--) {
      if (luxPickups[i].y > threshold) {
        luxPickups.splice(i, 1);
      }
    }
  }

  function updateLuxPickups() {
    if (isTerminalState()) return;
    if (state !== State.ORBITING && state !== State.DASHING) return;
    for (let i = luxPickups.length - 1; i >= 0; i--) {
      const p = luxPickups[i];
      if (dist(px, py, p.x, p.y) <= LUX_COLLECT_DIST) {
        grantLux(1);
        sound.playNeonPluck(14);
        luxPickups.splice(i, 1);
      }
    }
  }

  function drawLuxPickups() {
    if (luxPickups.length === 0) return;
    const t = performance.now() * 0.003;
    ctx.save();
    ctx.globalCompositeOperation = 'screen';
    for (const p of luxPickups) {
      const pulse = 0.78 + 0.22 * Math.sin(t + p.x * 0.02 + p.y * 0.015);
      const rGlow = 13 * pulse;
      ctx.fillStyle = `rgba(255,248,200,${0.32 * pulse})`;
      ctx.beginPath();
      ctx.arc(p.x, p.y, rGlow * 1.35, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = `rgba(255,220,100,${0.5 * pulse})`;
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(p.x, p.y, rGlow, 0, Math.PI * 2);
      ctx.stroke();
      ctx.fillStyle = `rgba(255,235,150,${0.95 * pulse})`;
      ctx.beginPath();
      ctx.arc(p.x, p.y, 5, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }

  function cullAnchorsFarBelowCamera() {
    const threshold = camTop + h + CULL_BELOW_CAMERA;
    const cur =
      state === State.DASHING || state === State.ORBITING ? anchors[anchorIndex] : null;
    const filtered = anchors.filter((a) => a.y <= threshold || a === cur);
    const had = anchors.length;
    anchors.length = 0;
    anchors.push(...filtered);
    if (had !== filtered.length) {
      const idx = cur ? anchors.indexOf(cur) : -1;
      if (idx >= 0) anchorIndex = idx;
      else if (anchorIndex >= anchors.length) anchorIndex = Math.max(0, anchors.length - 1);
    }
  }

  function initWorld() {
    score = 0;
    highScoreAtRunStart = highScore;
    anchors.length = 0;
    luxPickups.length = 0;
    camTop = 0;
    peakPlayerY = Infinity;
    peakSmoothed = Infinity;
    lastReleaseTimeSec = -1e9;
    comboPopupRemain = 0;

    const startY = h * 0.62;
    const minAx0 = HORIZONTAL_PAD + ORBIT_RADIUS;
    const maxAx0 = w - HORIZONTAL_PAD - ORBIT_RADIUS;
    const startX =
      minAx0 <= maxAx0
        ? Math.min(maxAx0, Math.max(minAx0, cx))
        : Math.min(w - HORIZONTAL_PAD, Math.max(HORIZONTAL_PAD, cx));
    anchors.push(createAnchor(startX, startY, score));
    anchorIndex = 0;
    orbitAngle = Math.PI * 0.5;
    const a = anchors[0];
    const r0 = effectiveOrbitR(a);
    px = a.x + Math.cos(orbitAngle) * r0;
    py = a.y + Math.sin(orbitAngle) * r0;
    /* Must run after px/py (and anchor) exist — otherwise spawn used px=0 and pinned X to the left edge. */
    spawnNextAnchor();
    peakPlayerY = py;
    peakSmoothed = py;
    camTop = peakPlayerY - h * 0.48;
    vx = vy = 0;
    dashVelX = dashVelY = 0;
    state = State.ORBITING;
    shakeRemain = 0;
    posHistory.length = 0;
    dashAgeSec = 0;
    restartCooldownSec = 0;
    shakePhase = 0;
    scaleCatchIndex = 0;
    orbitTimeSec = 0;
    comboMultiplier = 1;
    sound.setComboMultiplier(1);
    sound.resumeBgmIfPossible();
    gridPhase = 0;
    nebulaParticles.length = 0;
    jumpCount = 0;
    autoScrollPxPerSec = 0;
    captureFlashRemain = 0;
    downwardDashNoCapture = false;
    dashPrevAnchorWorldY = null;
    if (anchors[0]) {
      anchors[0].meltPending = true;
      anchors[0].meltElapsed = null;
      anchors[0].meltHoldSec = 0;
    }
    sparkParticles.length = 0;
    prevCamTop = camTop;
    prevPyParallax = py;
    playerVisSX = 1;
    playerVisSY = 1;
  }

  state = State.TITLE;

  /** Fixed juice shake on every successful catch (toned down on mobile / a11y). */
  function triggerCaptureShake() {
    if (prefersReducedMotion()) return;
    shakeMag = prefersCoarsePointer() ? 2 : 2.6;
    shakeDuration = 0.065;
    shakeRemain = 0.065;
    shakePhase = 0;
  }

  function getShakeOffset(dtReal) {
    if (prefersReducedMotion()) {
      shakeRemain = 0;
      return { x: 0, y: 0 };
    }
    if (shakeRemain <= 0) {
      shakeRemain = 0;
      return { x: 0, y: 0 };
    }
    shakeRemain -= dtReal;
    const rem = Math.max(0, shakeRemain);
    const falloff = shakeDuration > 0 ? rem / shakeDuration : 0;
    const m = shakeMag * falloff;
    /* Smooth oscillation — avoids per-frame random jitter that reads as “jumpy”. */
    shakePhase += dtReal * 48;
    return {
      x: Math.sin(shakePhase) * m,
      y: Math.sin(shakePhase * 1.37 + 1.1) * m * 0.85,
    };
  }

  function minEdgeDistanceToAnchors(skipIndex) {
    let best = Infinity;
    for (let i = 0; i < anchors.length; i++) {
      if (i === skipIndex) continue;
      const a = anchors[i];
      const d = dist(px, py, a.x, a.y) - effectiveCaptureR(a);
      if (d < best) best = d;
    }
    return best;
  }

  function pushPositionHistory() {
    posHistory.unshift({ x: px, y: py });
    const cap = getTrailGhostCount() + 1;
    if (posHistory.length > cap) {
      posHistory.length = cap;
    }
  }

  /**
   * Horizontal edge bounce while dashing.
   * Screen wrap (0 ↔ w) teleported the dot past anchors in one frame, skipped capture disks, and could
   * re-trigger wrap every frame — felt like an endless in/out loop on mostly-horizontal arcs.
   */
  function bouncePlayerXDuringDash() {
    const pad = Math.max(HORIZONTAL_PAD, PLAYER_WORLD_R + 12);
    if (px < pad) {
      px = pad;
      if (dashVelX < 0) {
        dashVelX *= -0.9;
        vx = dashVelX;
      }
    } else if (px > w - pad) {
      px = w - pad;
      if (dashVelX > 0) {
        dashVelX *= -0.9;
        vx = dashVelX;
      }
    }
  }

  function drawPlayerGhostTrail() {
    const rgb = currentPalette().trailRgb;
    const n = getTrailGhostCount();
    for (let g = n; g >= 1; g--) {
      if (g >= posHistory.length) continue;
      const p = posHistory[g];
      const age = g / n;
      const alpha = 0.08 + (1 - age) * 0.32;
      const radius = 11 + (1 - age) * 3;
      ctx.save();
      ctx.translate(p.x, p.y);
      ctx.fillStyle = `rgba(${rgb},${alpha * 0.28})`;
      ctx.beginPath();
      ctx.arc(0, 0, radius * 1.35, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = `rgba(${rgb},${alpha})`;
      ctx.beginPath();
      ctx.arc(0, 0, radius, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }
  }

  function failRun(kind) {
    deathKind = kind;
    const beatPersonalBest = score > highScoreAtRunStart;
    if (score > highScore) {
      highScore = score;
    }
    saveHi(highScore);
    if (beatPersonalBest) {
      hapticSuccess();
    } else {
      hapticGameOver(kind);
    }
    state = State.GAMEOVER;
    sound.pauseBgm();
    maybeRequestAppReview(score);
  }

  function gameOver() {
    failRun('other');
  }

  function updateCamera(dt) {
    peakPlayerY = Math.min(peakPlayerY, py);
    let peakK = 1 - Math.exp(-10 * Math.min(dt, 0.05));
    if (state === State.DASHING && dashVelY < 0) {
      peakK = 1 - Math.exp(-24 * Math.min(dt, 0.05));
    }
    if (!Number.isFinite(peakSmoothed)) peakSmoothed = peakPlayerY;
    else peakSmoothed += (peakPlayerY - peakSmoothed) * peakK;
    const idealTop = peakSmoothed - h * 0.48;
    /* Smooth follow; hard rule: camTop never increases (no scrolling “down”). */
    const alpha = 1 - Math.exp(-11 * Math.min(dt, 0.05));
    const nextTop = camTop + (idealTop - camTop) * alpha;
    if (nextTop < camTop) {
      camTop = nextTop;
    }
    camTop -= autoScrollPxPerSec * dt;
    /* Kill-plane: bottom of camera view + margin (world Y grows downward). */
    if (py > camTop + h + 100) {
      failRun('sun');
    }
    /* Flew too far above the frame — same soft-lock as endless dash */
    if (py < camTop - h * 0.22) {
      failRun('other');
    }
  }

  /**
   * Unit tangent = (Player − Anchor).rotated(π/2), normalized, signed with rotDir.
   * Matches Godot-style perpendicular; dash velocity is this × currentDashSpeed() only.
   */
  function getOrbitTangentUnit() {
    const a = anchors[anchorIndex];
    if (!a) return { x: 0, y: -1 };
    const dx = px - a.x;
    const dy = py - a.y;
    const len = Math.hypot(dx, dy) || 1;
    const rx = dx / len;
    const ry = dy / len;
    const dir = a.rotDir < 0 ? -1 : 1;
    const tx = dir * -ry;
    const ty = dir * rx;
    return { x: tx, y: ty };
  }

  function launchFromOrbit() {
    if (state !== State.ORBITING) return false;
    const a = anchors[anchorIndex];
    if (!a) return false;

    let { x: ux, y: uy } = getOrbitTangentUnit();
    const un = Math.hypot(ux, uy) || 1;
    ux /= un;
    uy /= un;

    if (uy > 0) {
      console.log('Downward Launch Prevented');
      return false;
    }

    lastReleaseTimeSec = performance.now() * 0.001;
    dashPrevAnchorWorldY = a.y;

    const dashSpeed = currentDashSpeed();
    dashVelX = ux * dashSpeed;
    dashVelY = uy * dashSpeed;
    vx = dashVelX;
    vy = dashVelY;

    downwardDashNoCapture = false;

    state = State.DASHING;
    dashAgeSec = 0;
    return true;
  }

  function releaseDash() {
    if (!launchFromOrbit()) return;
    hapticLightRelease();
  }

  /** Melt complete: anchor vanishes; player drops with no captures until next orbit. */
  function meltDropPlayer() {
    if (state !== State.ORBITING) return;
    const idx = anchorIndex;
    const gone = anchors[idx];
    if (!gone) return;
    const yLeave = gone.y;
    anchors.splice(idx, 1);
    anchorIndex = Math.min(idx, Math.max(0, anchors.length - 1));
    dashPrevAnchorWorldY = yLeave;
    downwardDashNoCapture = true;
    dashVelX = 0;
    dashVelY = 720;
    vx = 0;
    vy = 720;
    state = State.DASHING;
    dashAgeSec = 0;
    lastReleaseTimeSec = performance.now() * 0.001;
    hapticLightRelease();
  }

  function tryCapture() {
    if (downwardDashNoCapture) return;
    /* Screen Y grows downward — only snap while moving up (negative vy). */
    if (dashVelY >= 0) return;
    const prevY = oneWayPrevWorldY();
    for (let i = 0; i < anchors.length; i++) {
      if (i === anchorIndex) continue;
      const a = anchors[i];
      if (Number.isFinite(prevY) && a.y >= prevY) continue;
      if (dist(px, py, a.x, a.y) <= effectiveCaptureR(a)) {
        captureFrom(i, a);
        return;
      }
    }
  }

  function captureFrom(i, a) {
    triggerCaptureShake();
    spawnCaptureSparks(sparkParticles, a.x, a.y, 18);

    const nowSec = performance.now() * 0.001;
    const sinceRelease = nowSec - lastReleaseTimeSec;
    const quickCombo = sinceRelease >= 0 && sinceRelease <= COMBO_CAPTURE_WINDOW_SEC;

    anchorIndex = i;
    orbitAngle = Math.atan2(py - a.y, px - a.x);
    const snapR = effectiveOrbitR(a);
    px = a.x + Math.cos(orbitAngle) * snapR;
    py = a.y + Math.sin(orbitAngle) * snapR;
    vx = vy = 0;
    dashVelX = dashVelY = 0;
    captureFlashRemain = 0.11;

    let gained = 1;
    if (quickCombo) {
      gained = 2;
      comboPopupRemain = 0.7;
      comboMultiplier = Math.min(comboMultiplier + 0.35, 4);
    } else {
      comboMultiplier = 1;
    }
    sound.setComboMultiplier(comboMultiplier);

    sound.playNeonPluck(scaleCatchIndex);
    scaleCatchIndex += 1;

    score += gained;
    if (score > highScore) {
      highScore = score;
      saveHi(highScore);
    }

    jumpCount += 1;
    autoScrollPxPerSec = Math.floor(jumpCount / 10) * 14;

    hapticMediumCapture();
    state = State.ORBITING;
    orbitTimeSec = 0;
    downwardDashNoCapture = false;
    dashPrevAnchorWorldY = null;
    a.meltPending = true;
    a.meltElapsed = null;
    a.meltHoldSec = 0;

    spawnNextAnchor();
  }

  function currentPalette() {
    return BIOME_PALETTES[getBiomeIndex(score)];
  }

  function drawAnchor(a, anchorListIndex) {
    const pal = currentPalette();
    const u = meltProgressU(a);
    const showMeltCountdown =
      anchorListIndex === anchorIndex && (a.meltPending || a.meltElapsed != null);
    const uColor = meltTimerActive(a) ? u : 0;
    const mc = meltRingColors(uColor);
    const mscale = showMeltCountdown ? meltVisualScale(a) : 1;
    const vr = a.visualR * mscale;
    const flash = captureFlashRemain > 0 && anchorListIndex === anchorIndex;
    const flashT = flash ? Math.min(1, captureFlashRemain / 0.11) : 0;
    ctx.save();
    ctx.translate(a.x, a.y);
    const useMeltColor = showMeltCountdown;
    ctx.strokeStyle = useMeltColor
      ? `rgba(${mc.r},${mc.g},${mc.b},${mc.a})`
      : pal.anchorRing;
    ctx.lineWidth = 3;
    ctx.shadowColor = useMeltColor
      ? `rgba(${mc.r},${Math.round(mc.g * 0.75)},${Math.round(mc.b * 0.65)},0.72)`
      : pal.anchorGlow;
    ctx.shadowBlur = 14;
    ctx.beginPath();
    ctx.arc(0, 0, vr, 0, Math.PI * 2);
    ctx.stroke();
    if (showMeltCountdown) {
      const rem = meltTimerActive(a) ? 1 - u : 1;
      const pr = vr + 11;
      ctx.beginPath();
      ctx.arc(0, 0, pr, -Math.PI * 0.5, -Math.PI * 0.5 + rem * Math.PI * 2);
      ctx.strokeStyle = `rgba(${mc.r},${mc.g},${mc.b},${lerp(0.95, 1, uColor)})`;
      ctx.lineWidth = 4;
      ctx.lineCap = 'round';
      ctx.shadowBlur = 10;
      ctx.shadowColor = `rgba(${mc.r},${mc.g},${mc.b},0.55)`;
      ctx.stroke();
      ctx.shadowBlur = 0;
      ctx.lineCap = 'butt';
    }
    if (flashT > 0) {
      ctx.shadowBlur = 18 + flashT * 22;
      ctx.shadowColor = 'rgba(180, 255, 255, 0.95)';
      ctx.strokeStyle = `rgba(220, 255, 255, ${0.45 + flashT * 0.5})`;
      ctx.lineWidth = 4 + flashT * 5;
      ctx.beginPath();
      ctx.arc(0, 0, vr, 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.shadowBlur = 0;
    const cr = Math.round(lerp(0, 255, uColor));
    const cg = Math.round(lerp(255, 55, uColor));
    const cb = Math.round(lerp(255, 65, uColor));
    ctx.fillStyle = useMeltColor ? `rgba(${cr},${cg},${cb},0.55)` : pal.anchorCore;
    ctx.beginPath();
    ctx.arc(0, 0, Math.max(0.5, vr * 0.12), 0, Math.PI * 2);
    ctx.fill();
    if (score >= 100 && !showMeltCountdown) {
      for (let hi = 1; hi <= 3; hi += 1) {
        ctx.strokeStyle = `rgba(0, 255, 255, ${0.14 / hi})`;
        ctx.lineWidth = 2;
        ctx.shadowColor = `rgba(255, 140, 60, ${0.15 / hi})`;
        ctx.shadowBlur = 6 + hi * 2;
        ctx.beginPath();
        ctx.arc(0, 0, vr + hi * 5, 0, Math.PI * 2);
        ctx.stroke();
        ctx.shadowBlur = 0;
      }
    }
    ctx.restore();
  }

  function lerp(aa, bb, t) {
    return aa + (bb - aa) * t;
  }

  /** Trajectory predictor: only while orbiting an anchor. */
  function drawTrajectoryPredictor() {
    if (state !== State.ORBITING) return;
    const a = anchors[anchorIndex];
    if (!a) return;
    const { x: tx, y: ty } = getOrbitTangentUnit();
    ctx.save();
    ctx.translate(px, py);
    ctx.strokeStyle = currentPalette().traj;
    ctx.lineWidth = 2;
    ctx.setLineDash([6, 10]);
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.lineTo(tx * trajectoryGhostLen(), ty * trajectoryGhostLen());
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.restore();
  }

  function updatePlayerMorph(dt) {
    let tx = 1;
    let ty = 1;
    if (state === State.DASHING && (dashVelX !== 0 || dashVelY !== 0)) {
      tx = 1.42;
      ty = 0.78;
    } else if (state === State.ORBITING) {
      tx = 0.9;
      ty = 1.08;
    }
    const k = 1 - Math.exp(-12 * Math.min(dt, 0.05));
    playerVisSX += (tx - playerVisSX) * k;
    playerVisSY += (ty - playerVisSY) * k;
  }

  function drawPlayer() {
    const pal = currentPalette();
    ctx.save();
    ctx.translate(px, py);
    if (state === State.DASHING && (dashVelX !== 0 || dashVelY !== 0)) {
      ctx.rotate(Math.atan2(dashVelY, dashVelX));
    }
    ctx.scale(playerVisSX, playerVisSY);
    ctx.fillStyle = pal.playerFill;
    ctx.globalAlpha = 0.22;
    ctx.beginPath();
    ctx.arc(0, 0, PLAYER_WORLD_R * 1.42, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;
    ctx.beginPath();
    ctx.arc(0, 0, PLAYER_WORLD_R, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = pal.playerStroke;
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.restore();
  }

  const TITLE_STR = 'IKAROS';
  const TITLE_O_INDEX = 4;

  /**
   * Main menu: IKAROS title, pink dot orbiting the “O”, pulsing “Tap to ascend”.
   */
  function drawTitleScreen(menuTimeSec) {
    const titleBaselineY = cy * 0.72;
    const reduceMotion =
      typeof matchMedia !== 'undefined' &&
      matchMedia('(prefers-reduced-motion: reduce)').matches;

    ctx.save();
    ctx.textAlign = 'center';
    ctx.font = '900 56px system-ui, "Segoe UI", sans-serif';
    const totalW = ctx.measureText(TITLE_STR).width;
    const leftX = cx - totalW / 2;
    const beforeO = TITLE_STR.slice(0, TITLE_O_INDEX);
    const oChar = TITLE_STR[TITLE_O_INDEX];
    const wBefore = ctx.measureText(beforeO).width;
    const wO = ctx.measureText(oChar).width;
    const oCenterX = leftX + wBefore + wO / 2;
    const mO = ctx.measureText(oChar);
    const asc = mO.actualBoundingBoxAscent ?? 40;
    const desc = mO.actualBoundingBoxDescent ?? 10;
    const oCenterY = titleBaselineY - asc * 0.42 + desc * 0.12;

    ctx.fillStyle = '#00fff7';
    ctx.shadowColor = 'rgba(0,255,255,0.85)';
    ctx.shadowBlur = 28;
    ctx.fillText(TITLE_STR, cx, titleBaselineY);
    ctx.shadowBlur = 0;

    const orbitR = Math.min(42, 26 + totalW * 0.048);
    const dotR = 4.5;
    const ang = reduceMotion ? -Math.PI * 0.5 : menuTimeSec * 0.92;
    const ox = oCenterX + Math.cos(ang) * orbitR;
    const oy = oCenterY + Math.sin(ang) * orbitR * 0.58;

    ctx.beginPath();
    ctx.arc(ox, oy, dotR, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(255, 80, 235, 0.98)';
    ctx.shadowColor = 'rgba(255, 0, 210, 0.9)';
    ctx.shadowBlur = 18;
    ctx.fill();
    ctx.shadowBlur = 0;

    const subA = reduceMotion
      ? 0.72
      : 0.5 + 0.42 * (0.5 + 0.5 * Math.sin(menuTimeSec * 1.55));
    const subGlow = reduceMotion ? 10 : 8 + 10 * (subA - 0.5);
    ctx.font = '500 17px system-ui, sans-serif';
    ctx.fillStyle = `rgba(0,255,247,${subA})`;
    ctx.shadowColor = 'rgba(0,255,255,0.35)';
    ctx.shadowBlur = subGlow;
    ctx.fillText('Tap to ascend', cx, titleBaselineY + 44);
    ctx.shadowBlur = 0;
    ctx.font = '500 13px system-ui, sans-serif';
    ctx.fillStyle = 'rgba(255,220,150,0.78)';
    ctx.fillText('Collect golden LUX between the stars', cx, titleBaselineY + 72);
    ctx.restore();
  }

  /** Sun fixed to top of viewport (screen space). */
  function drawSunScreenTop() {
    ctx.save();
    const gx = cx + Math.sin(sunPhase) * 18;
    const gy = 78;
    const g = ctx.createRadialGradient(gx, gy, 4, gx, gy, 140);
    g.addColorStop(0, 'rgba(255,252,235,0.5)');
    g.addColorStop(0.25, 'rgba(255,220,120,0.18)');
    g.addColorStop(0.55, 'rgba(255,160,60,0.08)');
    g.addColorStop(1, 'rgba(255,120,40,0)');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, w, 160);
    ctx.restore();
  }

  /**
   * Sun locked to **screen** space (not world + shake) so it reads as a distant goal, not glued to the climb.
   */
  function drawSunScreen(comboMul, scoreRun) {
    const ascentBoost = scoreRun >= 21 && scoreRun <= 40 ? 1.1 : 1;
    const comboPulse = 1 + Math.min(0.5, Math.max(0, comboMul - 1) * 0.16);
    const R = 160 * ascentBoost * comboPulse;
    const inner = 6 * ascentBoost * comboPulse;
    const wobble =
      prefersReducedMotion() ? 0 : prefersCoarsePointer() || w < 640 ? 7 : 18;
    ctx.save();
    const gx = cx + Math.sin(sunPhase * 0.65) * wobble;
    const gy = 72;
    ctx.globalCompositeOperation = 'screen';
    ctx.fillStyle = 'rgba(255,150,70,0.07)';
    ctx.beginPath();
    ctx.arc(gx, gy, R, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = 'rgba(255,200,120,0.11)';
    ctx.beginPath();
    ctx.arc(gx, gy, R * 0.55, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = 'rgba(255,248,220,0.26)';
    ctx.beginPath();
    ctx.arc(gx, gy, Math.max(inner * 2.2, 14), 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  function drawHud(dt) {
    const hudPad = 20;
    const hudTop = 14;

    if (isTitleState()) {
      ctx.save();
      ctx.textBaseline = 'top';
      ctx.textAlign = 'left';
      let y = hudTop;
      ctx.font = '700 13px system-ui, sans-serif';
      ctx.fillStyle = 'rgba(0,255,255,0.9)';
      ctx.shadowColor = 'rgba(0,255,255,0.45)';
      ctx.shadowBlur = 10;
      ctx.fillText('Your Best Score', hudPad, y);
      y += 17;
      ctx.font = '800 32px system-ui, sans-serif';
      ctx.fillText(String(highScore), hudPad, y);
      ctx.shadowBlur = 0;

      ctx.textAlign = 'right';
      ctx.font = '700 13px system-ui, sans-serif';
      ctx.fillStyle = 'rgba(255,210,120,0.92)';
      ctx.shadowColor = 'rgba(255,180,60,0.4)';
      ctx.shadowBlur = 8;
      ctx.fillText('LUX', w - hudPad, hudTop);
      ctx.font = '800 32px system-ui, sans-serif';
      ctx.fillText(String(totalLux), w - hudPad, hudTop + 17);
      ctx.shadowBlur = 0;
      ctx.restore();
      return;
    }

    if (comboPopupRemain > 0) {
      comboPopupRemain = Math.max(0, comboPopupRemain - dt);
    }
    const pal = currentPalette();
    ctx.save();
    ctx.shadowBlur = 0;
    ctx.textBaseline = 'top';
    ctx.textAlign = 'left';
    let hy = hudTop;
    ctx.fillStyle = 'rgba(0,255,255,0.92)';
    ctx.font = '700 12px system-ui, sans-serif';
    ctx.fillText('Your Best Score', hudPad, hy);
    hy += 16;
    ctx.font = '800 22px system-ui, sans-serif';
    ctx.fillText(String(highScore), hudPad, hy);
    hy += 26;
    ctx.fillStyle = pal.hudScore;
    ctx.font = '600 18px system-ui, sans-serif';
    ctx.fillText(`Score: ${score}`, hudPad, hy);
    hy += 24;
    if (comboMultiplier > 1) {
      ctx.fillStyle = pal.hudCombo;
      ctx.font = '600 17px system-ui, sans-serif';
      ctx.fillText(`×${comboMultiplier.toFixed(2)} streak`, hudPad, hy);
    }
    ctx.textAlign = 'right';
    ctx.fillStyle = 'rgba(255,215,100,0.95)';
    ctx.font = '700 11px system-ui, sans-serif';
    ctx.fillText('LUX', w - hudPad, hudTop);
    ctx.font = '800 20px system-ui, sans-serif';
    ctx.fillText(String(totalLux), w - hudPad, hudTop + 13);
    ctx.font = '600 11px system-ui, sans-serif';
    ctx.fillStyle = 'rgba(255,255,255,0.65)';
    ctx.fillText(pal.label.toUpperCase(), w - hudPad, hudTop + 38);
    if (comboPopupRemain > 0 && comboMultiplier > 1) {
      const pulse = 0.85 + 0.15 * Math.sin(performance.now() * 0.02);
      ctx.fillStyle = `rgba(255,220,100,${0.75 * pulse})`;
      ctx.font = '800 28px system-ui, sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText('STREAK!', cx, cy * 0.35);
    }
    if (isTerminalState()) {
      ctx.textAlign = 'center';
      ctx.textBaseline = 'alphabetic';
      ctx.fillStyle = 'rgba(255,240,220,0.95)';
      ctx.font = '800 26px system-ui, sans-serif';
      ctx.shadowColor = 'rgba(255,180,80,0.5)';
      ctx.shadowBlur = 16;
      const headline =
        deathKind === 'sun' ? 'FELL FROM THE SUN' : 'GAME OVER';
      ctx.fillText(headline, cx, cy - 28);
      ctx.shadowBlur = 0;
      ctx.fillStyle = 'rgba(255,255,255,0.78)';
      ctx.font = '500 17px system-ui, sans-serif';
      ctx.fillText(`Score ${score}  —  Tap, touch, or Space to retry`, cx, cy + 12);
      ctx.fillStyle = 'rgba(255,210,130,0.88)';
      ctx.font = '600 15px system-ui, sans-serif';
      ctx.fillText(`LUX ${totalLux}`, cx, cy + 38);
    }
    ctx.restore();
  }

  let lastT = performance.now();
  function frame(now) {
    /* Delta-time sim; rAF matches display refresh (e.g. 120 Hz ProMotion). Cap avoids spiral of death. */
    let dt = Math.min(0.05, (now - lastT) / 1000);
    lastT = now;
    sunPhase +=
      dt *
      (prefersReducedMotion() ? 0.05 : prefersCoarsePointer() || w < 640 ? 0.12 : 0.22);
    captureFlashRemain = Math.max(0, captureFlashRemain - dt);
    restartCooldownSec = Math.max(0, restartCooldownSec - dt);
    sound.tickFilter(dt);
    syncMenuUiMode();

    if (isTitleState()) {
      titleMenuPhase += dt;
      if (!titleBgmPrewarmDone) {
        titleBgmPrewarmDone = true;
        sound.prewarmBgm();
      }
      drawScreenBackdrop(ctx, w, h, 0);
      drawSunScreenTop();
      drawTitleScreen(titleMenuPhase);
      drawHud(dt);
      requestAnimationFrame(frameSafe);
      return;
    }

    if (!isTerminalState()) {
      updateAnchorDrift(dt);
    }

    let simDt = dt;
    if (state === State.DASHING) {
      const edgeDist = minEdgeDistanceToAnchors(anchorIndex);
      if (edgeDist < TIME_DILATION_EDGE_MARGIN) {
        simDt = dt * TIME_DILATION_NEAR;
      }
    }

    if (state === State.ORBITING) {
      orbitTimeSec += dt;
      if (orbitTimeSec > ORBIT_SCALE_RESET_SEC) {
        scaleCatchIndex = 0;
        comboMultiplier = 1;
        sound.setComboMultiplier(1);
      }
      const a = anchors[anchorIndex];
      if (a) {
        const dir = a.rotDir >= 0 ? 1 : -1;
        const omega = orbitOmega();
        orbitAngle += omega * dir * dt;
        if (!isTerminalState()) {
          const r = effectiveOrbitR(a);
          px = a.x + Math.cos(orbitAngle) * r;
          py = a.y + Math.sin(orbitAngle) * r;
        }
      }
      /* After px/py match this frame’s orbit — melt “fair start” uses real player offset from anchor. */
      const meltA = anchors[anchorIndex];
      if (meltA && (meltA.meltPending || meltA.meltElapsed != null)) {
        if (meltA.meltPending) {
          meltA.meltHoldSec = (meltA.meltHoldSec || 0) + dt;
          const { y: tyTan } = getOrbitTangentUnit();
          const upwardHalf = tyTan <= 0;
          const strictStart = hasFairJumpWindowNow(meltA);
          const relaxedStart =
            meltA.meltHoldSec >= MELT_PENDING_RELAX_SEC &&
            upwardHalf &&
            hasReachableTargetDistanceOnly(meltA);
          if (
            strictStart ||
            relaxedStart ||
            meltA.meltHoldSec >= MELT_HOLD_FORCE_SEC
          ) {
            meltA.meltPending = false;
            meltA.meltElapsed = 0;
          }
        } else if (meltA.meltElapsed != null) {
          meltA.meltElapsed += dt;
          if (meltA.meltElapsed >= MELT_DURATION_SEC) {
            meltA.meltElapsed = MELT_DURATION_SEC;
            meltDropPlayer();
          }
        }
      }
    } else if (state === State.DASHING) {
      /* dashVel* set only when entering DASHING — never altered until capture / game over. */
      dashAgeSec += dt;
      px += dashVelX * simDt;
      py += dashVelY * simDt;
      bouncePlayerXDuringDash();
      tryCapture();
      /* Missed everything / tunneling — don’t leave the loop running forever */
      const maxDash = 4.2;
      if (dashAgeSec > maxDash) {
        gameOver();
      }
    }

    if (!isTerminalState()) {
      updateCamera(dt);
    }

    if (state === State.ORBITING && (!anchors[anchorIndex] || anchors.length === 0)) {
      gameOver();
    }

    cullAnchorsFarBelowCamera();
    updateLuxPickups();
    cullLuxPickupsFarBelow();

    if (!isTerminalState()) {
      pushPositionHistory();
    }

    const biome = getBiomeIndex(score);
    if (biome === 2) {
      ensureNebulaParticles(nebulaParticles, w, h, camTop);
      updateNebulaParticles(nebulaParticles, dt, camTop, w, h);
    }
    if (biome === 1) {
      gridPhase = updateGridPhase(gridPhase, dt);
    }

    const camDeltaY = prevCamTop == null ? 0 : camTop - prevCamTop;
    prevCamTop = camTop;
    let parallaxCamDelta = camDeltaY;
    if (prevPyParallax != null) {
      const dpy = py - prevPyParallax;
      if (state === State.DASHING && dashVelY < 0 && dpy < 0) {
        parallaxCamDelta = Math.min(camDeltaY, dpy);
      }
    }
    prevPyParallax = py;

    const reduced = prefersReducedMotion();
    const coarse = prefersCoarsePointer();
    const mobileLike = coarse || w < 640;
    const paraTuning = {
      layerMulScale: reduced ? 0.38 : mobileLike ? 0.72 : 1,
      driftScale: reduced ? 0.35 : mobileLike ? 0.68 : 1,
    };
    if (parallaxStarfield) {
      updateParallaxStarfield(
        parallaxStarfield,
        dt,
        parallaxCamDelta,
        score,
        w,
        h,
        paraTuning,
      );
    }
    updateCaptureSparks(sparkParticles, dt);
    updatePlayerMorph(dt);
    ionosphereScroll += dt * 0.42;

    const { x: shx, y: shy } = getShakeOffset(dt);

    drawAtmosphericBackdrop(ctx, w, h, score);
    if (parallaxStarfield) {
      drawParallaxStarfield(ctx, w, h, parallaxStarfield, score);
    }
    if (score >= 41 && score <= 60 && !prefersReducedMotion()) {
      const beatPh =
        typeof sound.getBeatVisualPhase === 'function'
          ? sound.getBeatVisualPhase()
          : 0;
      drawIonosphereOverlay(ctx, w, h, beatPh, ionosphereScroll);
    }

    drawSunScreen(comboMultiplier, score);

    ctx.save();
    ctx.translate(0, -camTop);
    ctx.translate(shx, shy);
    drawWorldBiomeLayer(ctx, w, h, camTop, biome, gridPhase, nebulaParticles);
    drawTrajectoryPredictor();
    drawPlayerGhostTrail();
    drawPlayer();
    for (let ai = 0; ai < anchors.length; ai += 1) {
      drawAnchor(anchors[ai], ai);
    }
    drawLuxPickups();
    drawCaptureSparks(ctx, sparkParticles);
    ctx.restore();

    drawHud(dt);

    requestAnimationFrame(frameSafe);
  }

  function frameSafe(now) {
    try {
      frame(now);
    } catch (err) {
      console.error('IKAROS frame error:', err);
      state = State.GAMEOVER;
      requestAnimationFrame(frameSafe);
    }
  }

  function tryRestartOrDash(e) {
    if (e.cancelable) e.preventDefault();
    void sound.resume();
    if (restartCooldownSec > 0) return;
    if (isTitleState()) {
      restartCooldownSec = 0.35;
      /* Defer heavy init so BGM play() can start in the same gesture before decode + sim spike. */
      requestAnimationFrame(() => {
        initWorld();
      });
      return;
    }
    if (isTerminalState()) {
      restartCooldownSec = 0.4;
      requestAnimationFrame(() => {
        initWorld();
      });
      return;
    }
    releaseDash();
  }

  canvas.addEventListener('pointerdown', tryRestartOrDash, { passive: false });
  canvas.addEventListener(
    'touchend',
    (e) => {
      if (!isTerminalState() && !isTitleState()) return;
      tryRestartOrDash(e);
    },
    { passive: false },
  );
  window.addEventListener('keydown', (e) => {
    if (e.code !== 'Space') return;
    e.preventDefault();
    void sound.resume();
    if (restartCooldownSec > 0) return;
    if (isTitleState()) {
      restartCooldownSec = 0.35;
      requestAnimationFrame(() => {
        initWorld();
      });
      return;
    }
    if (isTerminalState()) {
      restartCooldownSec = 0.4;
      requestAnimationFrame(() => {
        initWorld();
      });
      return;
    }
    if (state === State.ORBITING) {
      releaseDash();
    }
  });

  /* Paint immediately so the first frame is not delayed until the next display refresh. */
  frameSafe(performance.now());
  requestAnimationFrame(frameSafe);

  return {
    /** Use on any UI pointer gesture so BGM can start on the welcome screen (autoplay policy). */
    primeAudio() {
      void sound.resume();
    },
  };
}
