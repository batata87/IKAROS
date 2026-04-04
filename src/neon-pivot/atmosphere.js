/**
 * Parallax starfield, score-driven sky, ionosphere scanlines (Canvas 2D).
 */

function lerp(a, b, t) {
  return a + (b - a) * t;
}

export function createParallaxStarfield(w, h) {
  const layers = [[], [], []];
  const counts = [70, 40, 16];
  for (let L = 0; L < 3; L += 1) {
    for (let i = 0; i < counts[L]; i += 1) {
      layers[L].push({
        x: Math.random() * w,
        y: Math.random() * h,
        r:
          L === 0
            ? 0.7 + Math.random() * 1.1
            : L === 1
              ? 1.4 + Math.random() * 1.6
              : 6 + Math.random() * 14,
      });
    }
  }
  return { layers, scrollY: [0, 0, 0] };
}

export function updateParallaxStarfield(state, dt, camDeltaY, score, w, h) {
  if (!state) return;
  /* Back 10%, mid 50%, front ~115% of camera motion (depth). */
  const mul = [0.1, 0.5, 1.15];
  const deep = score <= 20;
  const driftDown = deep ? [14, 9, 22] : [3, 5, 12];
  for (let L = 0; L < 3; L += 1) {
    state.scrollY[L] += (-camDeltaY) * mul[L] + driftDown[L] * dt;
    const span = h + 80;
    while (state.scrollY[L] > span) state.scrollY[L] -= span;
    while (state.scrollY[L] < -span) state.scrollY[L] += span;
  }
}

export function drawParallaxStarfield(ctx, w, h, state, score) {
  if (!state) return;
  const deep = score <= 20;
  for (let L = 0; L < 3; L += 1) {
    const sy = state.scrollY[L];
    for (const s of state.layers[L]) {
      let y = ((s.y + sy) % h) + h;
      y %= h;
      let x = s.x;
      if (L === 2) {
        /* Avoid shadowBlur here — it is extremely expensive and causes frame drops / “jumpy” sky. */
        const a = deep ? 0.12 : 0.18;
        ctx.fillStyle = `rgba(140, 190, 255, ${a * 0.35})`;
        ctx.beginPath();
        ctx.arc(x, y, s.r * 1.55, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = `rgba(200, 230, 255, ${a})`;
        ctx.beginPath();
        ctx.arc(x, y, s.r * 0.72, 0, Math.PI * 2);
        ctx.fill();
      } else if (L === 1) {
        ctx.fillStyle = `rgba(210, 235, 255, ${deep ? 0.22 : 0.32})`;
        ctx.beginPath();
        ctx.arc(x, y, s.r, 0, Math.PI * 2);
        ctx.fill();
      } else {
        ctx.fillStyle = `rgba(200, 220, 255, ${deep ? 0.18 : 0.28})`;
        ctx.beginPath();
        ctx.arc(x, y, s.r, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  }
}

/**
 * Climbing out of the void: black → navy (0–100), burnt sun realm at 100+.
 */
export function drawAtmosphericBackdrop(ctx, w, h, score) {
  if (score >= 100) {
    const u = Math.min(1, (score - 100) / 100);
    const g = ctx.createLinearGradient(0, 0, 0, h);
    g.addColorStop(0, `rgb(${lerp(36, 52, u)}, ${lerp(14, 22, u)}, ${lerp(6, 10, u)})`);
    g.addColorStop(0.55, `rgb(${lerp(16, 32, u)}, ${lerp(6, 12, u)}, ${lerp(4, 6, u)})`);
    g.addColorStop(1, `rgb(${lerp(6, 18, u)}, ${lerp(3, 6, u)}, ${lerp(2, 4, u)})`);
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, w, h);
    return;
  }

  if (score <= 20) {
    ctx.fillStyle = '#000000';
    ctx.fillRect(0, 0, w, h);
    return;
  }

  const tNavy = Math.min(1, score / 100);
  const r0 = Math.round(lerp(0, 8, tNavy));
  const g0 = Math.round(lerp(0, 12, tNavy));
  const b0 = Math.round(lerp(0, 28, tNavy));

  if (score <= 40) {
    const u = (score - 21) / 19;
    ctx.fillStyle = '#000000';
    ctx.fillRect(0, 0, w, h);
    const g = ctx.createLinearGradient(0, 0, 0, h * 0.62);
    g.addColorStop(0, `rgba(16, 24, 56, ${0.22 + u * 0.35})`);
    g.addColorStop(0.55, `rgba(${r0},${g0},${b0},0.12)`);
    g.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, w, h);
    return;
  }

  if (score < 61) {
    const u = (score - 41) / 20;
    const g = ctx.createLinearGradient(0, 0, 0, h);
    g.addColorStop(0, `rgb(${lerp(12, 18, u)}, ${lerp(18, 28, u)}, ${lerp(42, 52, u)})`);
    g.addColorStop(0.5, `rgb(${lerp(4, 8, u)}, ${lerp(6, 12, u)}, ${lerp(18, 28, u)})`);
    g.addColorStop(1, `rgb(${r0},${g0},${b0})`);
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, w, h);
    return;
  }

  const u = Math.min(1, (score - 61) / 39);
  const g = ctx.createLinearGradient(0, 0, 0, h);
  g.addColorStop(0, `rgb(${lerp(18, 14, u)}, ${lerp(26, 20, u)}, ${lerp(52, 38, u)})`);
  g.addColorStop(0.45, `rgb(${lerp(10, 8, u)}, ${lerp(14, 10, u)}, ${lerp(28, 22, u)})`);
  g.addColorStop(1, `rgb(${lerp(6, 4, u)}, ${lerp(8, 5, u)}, ${lerp(16, 10, u)})`);
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, w, h);
}

/** The Ionosphere: scanlines + faint grid pulse (score 41–60). */
export function drawIonosphereOverlay(ctx, w, h, beatPhase, scrollPhase) {
  const pulse = 0.5 + 0.5 * Math.sin(beatPhase);
  const baseA = 0.028 + pulse * 0.038;
  ctx.save();
  ctx.globalCompositeOperation = 'screen';
  const step = 4;
  const off = (scrollPhase * 18) % step;
  ctx.strokeStyle = `rgba(120, 200, 255, ${baseA})`;
  ctx.lineWidth = 1;
  for (let y = off; y <= h; y += step) {
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(w, y);
    ctx.stroke();
  }
  const gx = 48 + pulse * 6;
  ctx.strokeStyle = `rgba(52, 180, 200, ${0.04 + pulse * 0.03})`;
  for (let x = (scrollPhase * 22) % gx; x <= w; x += gx) {
    ctx.beginPath();
    ctx.moveTo(x, 0);
    ctx.lineTo(x, h);
    ctx.stroke();
  }
  ctx.restore();
}

export function spawnCaptureSparks(list, wx, wy, n = 16) {
  for (let i = 0; i < n; i += 1) {
    const ang = Math.random() * Math.PI * 2;
    const spd = 160 + Math.random() * 280;
    const life = 0.18 + Math.random() * 0.22;
    list.push({
      x: wx,
      y: wy,
      vx: Math.cos(ang) * spd,
      vy: Math.sin(ang) * spd,
      life,
      maxLife: life,
    });
  }
}

export function updateCaptureSparks(list, dt) {
  for (let i = list.length - 1; i >= 0; i -= 1) {
    const p = list[i];
    p.life -= dt;
    p.x += p.vx * dt;
    p.y += p.vy * dt;
    p.vx *= Math.exp(-dt * 5.5);
    p.vy *= Math.exp(-dt * 5.5);
    if (p.life <= 0) list.splice(i, 1);
  }
}

export function drawCaptureSparks(ctx, list) {
  for (const p of list) {
    const t = Math.max(0, p.life / p.maxLife);
    const a = t * 0.85;
    ctx.fillStyle = `rgba(160, 255, 255, ${a * 0.35})`;
    ctx.beginPath();
    ctx.arc(p.x, p.y, 3.4 + (1 - t) * 2.2, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = `rgba(100, 255, 255, ${a})`;
    ctx.beginPath();
    ctx.arc(p.x, p.y, 2.2 + (1 - t) * 2, 0, Math.PI * 2);
    ctx.fill();
  }
}
