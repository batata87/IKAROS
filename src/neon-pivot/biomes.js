/**
 * Score-based visual biomes: Void (0–49), Grid (50–99), Nebula (100+).
 */

export function getBiomeIndex(score) {
  if (score < 50) return 0;
  if (score < 100) return 1;
  return 2;
}

/** Per-biome colors for gameplay + HUD. */
export const BIOME_PALETTES = [
  {
    id: 'void',
    label: 'The Void',
    screenFill: '#000000',
    anchorRing: 'rgba(0,255,255,0.85)',
    anchorGlow: 'rgba(0,255,255,0.9)',
    anchorCore: 'rgba(255,0,255,0.38)',
    playerFill: 'rgba(255,90,255,0.98)',
    playerStroke: 'rgba(100,255,255,0.95)',
    playerGlow: 'rgba(255,80,255,0.95)',
    trailRgb: '255,100,255',
    traj: 'rgba(255,255,255,0.22)',
    hudHi: 'rgba(180,255,255,0.95)',
    hudScore: 'rgba(200,255,255,0.88)',
    hudCombo: 'rgba(255,160,255,0.92)',
  },
  {
    id: 'grid',
    label: 'The Grid',
    screenTop: '#020806',
    screenBot: '#051812',
    anchorRing: 'rgba(52,211,153,0.9)',
    anchorGlow: 'rgba(16,185,129,0.95)',
    anchorCore: 'rgba(245,196,72,0.45)',
    playerFill: 'rgba(252,211,77,0.98)',
    playerStroke: 'rgba(52,211,153,0.95)',
    playerGlow: 'rgba(250,204,21,0.9)',
    trailRgb: '250,204,21',
    traj: 'rgba(167,243,208,0.28)',
    hudHi: 'rgba(167,243,208,0.95)',
    hudScore: 'rgba(253,230,138,0.9)',
    hudCombo: 'rgba(52,211,153,0.92)',
  },
  {
    id: 'nebula',
    label: 'The Nebula',
    screenTop: '#0a0518',
    screenBot: '#1a0b32',
    anchorRing: 'rgba(196,181,253,0.9)',
    anchorGlow: 'rgba(233,213,255,0.85)',
    anchorCore: 'rgba(250,250,255,0.5)',
    playerFill: 'rgba(248,250,255,0.98)',
    playerStroke: 'rgba(167,139,250,0.95)',
    playerGlow: 'rgba(237,233,254,0.95)',
    trailRgb: '196,181,253',
    traj: 'rgba(255,255,255,0.26)',
    hudHi: 'rgba(221,214,254,0.95)',
    hudScore: 'rgba(237,233,254,0.88)',
    hudCombo: 'rgba(192,132,252,0.92)',
  },
];

export function drawScreenBackdrop(ctx, w, h, biomeIndex) {
  const p = BIOME_PALETTES[biomeIndex];
  if (biomeIndex === 0) {
    ctx.fillStyle = p.screenFill;
    ctx.fillRect(0, 0, w, h);
    return;
  }
  const g = ctx.createLinearGradient(0, 0, 0, h);
  g.addColorStop(0, p.screenTop);
  g.addColorStop(1, p.screenBot);
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, w, h);
}

/**
 * World-space decorative layer (scrolls with camera). Call inside translate(0,-camTop).
 */
export function drawWorldBiomeLayer(ctx, w, h, camTop, biomeIndex, gridPhase, nebulaParticles) {
  if (biomeIndex === 0) return;

  const pad = 120;
  const left = -pad;
  const right = w + pad;
  const top = camTop - pad;
  const bot = camTop + h + pad;

  if (biomeIndex === 1) {
    const step = 44;
    const oy = gridPhase % step;
    const ox = (gridPhase * 0.35) % step;
    ctx.lineWidth = 1;
    for (let y = Math.floor(top / step) * step + oy; y <= bot; y += step) {
      const gold = Math.abs(Math.floor(y / step)) % 6 === 0;
      ctx.strokeStyle = gold ? 'rgba(245,196,72,0.2)' : 'rgba(16,185,129,0.14)';
      ctx.beginPath();
      ctx.moveTo(left, y);
      ctx.lineTo(right, y);
      ctx.stroke();
    }
    for (let x = Math.floor(left / step) * step + ox; x <= right; x += step) {
      const gold = Math.abs(Math.floor(x / step)) % 7 === 0;
      ctx.strokeStyle = gold ? 'rgba(245,196,72,0.16)' : 'rgba(52,211,153,0.11)';
      ctx.beginPath();
      ctx.moveTo(x, top);
      ctx.lineTo(x, bot);
      ctx.stroke();
    }
    return;
  }

  /* Nebula soft clouds — solid fills only (no per-blob radial gradients = much less GC + jank). */
  for (const q of nebulaParticles) {
    if (q.y < top - 200 || q.y > bot + 200) continue;
    ctx.fillStyle = `rgba(120,80,170,${q.a * 0.2})`;
    ctx.beginPath();
    ctx.arc(q.x, q.y, q.r * 1.02, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = `rgba(210,200,255,${q.a * 0.42})`;
    ctx.beginPath();
    ctx.arc(q.x, q.y, q.r * 0.38, 0, Math.PI * 2);
    ctx.fill();
  }
}

export function updateGridPhase(gridPhase, dt) {
  let v = gridPhase + dt * 52;
  /* Keep magnitude bounded so (gridPhase * 0.35) % step stays numerically stable during long runs. */
  while (v > 50000) v -= 50000;
  return v;
}

export function updateNebulaParticles(parts, dt, camTop, w, h) {
  const margin = 500;
  const left = -margin;
  const right = w + margin;
  const top = camTop - margin;
  const bot = camTop + h + margin;
  for (const q of parts) {
    q.x += q.vx * dt;
    q.y += q.vy * dt;
    if (q.x < left) q.x = right - 20;
    if (q.x > right) q.x = left + 20;
    if (q.y < top) q.y = bot - 20;
    if (q.y > bot) q.y = top + 20;
  }
}

export function ensureNebulaParticles(parts, w, h, camTop) {
  if (parts.length > 0) return;
  const n = 42;
  const x0 = -320;
  const x1 = w + 320;
  const y0 = camTop - 600;
  const y1 = camTop + h + 900;
  for (let i = 0; i < n; i += 1) {
    parts.push({
      x: x0 + Math.random() * (x1 - x0),
      y: y0 + Math.random() * (y1 - y0),
      r: 55 + Math.random() * 140,
      a: 0.045 + Math.random() * 0.09,
      vx: (Math.random() - 0.5) * 18,
      vy: (Math.random() - 0.35) * 12,
    });
  }
}
