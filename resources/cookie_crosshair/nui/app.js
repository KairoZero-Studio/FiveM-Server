
const $ = (id) => document.getElementById(id);

function defaultCfg() {
  return {
    custom: true, base: false, adsOnly: true,
    r: 255, g: 255, b: 255, a: 255,
    outline: true, outlineW: 1, outlineA: 255,
    dot: true, dotW: 4, dotA: 255,
    inner: true, inW: 2, inL: 8, inO: 4,
    outer: false, outW: 2, outL: 4, outO: 12,
    ring: false, ringR: 6, ringW: 2,
    top: true,
  };
}
let cfg = defaultCfg();
let PRESETS = [];

const ovCv = $('ovCanvas'), ovCtx = ovCv.getContext('2d');
const prCv = $('prevCanvas'), prCtx = prCv.getContext('2d');

function drawHair(ctx, w, h, c, scale) {
  ctx.clearRect(0, 0, w, h);
  if (!c.custom) return;
  const cx = w / 2, cy = h / 2, S = scale || 1;
  const main = `rgba(${c.r},${c.g},${c.b},${c.a / 255})`;
  const out = `rgba(0,0,0,${c.outlineA / 255})`;
  const ow = (c.outline ? c.outlineW : 0) * S;

  const seg = (x, y, ww, hh) => {
    if (ow > 0) { ctx.fillStyle = out; ctx.fillRect(x - ow, y - ow, ww + 2 * ow, hh + 2 * ow); }
    ctx.fillStyle = main; ctx.fillRect(x, y, ww, hh);
  };
  if (c.inner) {
    const t = c.inW * S, L = c.inL * S, o = c.inO * S;
    if (c.top !== false) seg(cx - t / 2, cy - o - L, t, L);
    seg(cx - t / 2, cy + o, t, L);
    seg(cx - o - L, cy - t / 2, L, t);
    seg(cx + o, cy - t / 2, L, t);
  }
  if (c.outer) {
    const t = c.outW * S, L = c.outL * S, o = c.outO * S;
    if (c.top !== false) seg(cx - t / 2, cy - o - L, t, L);
    seg(cx - t / 2, cy + o, t, L);
    seg(cx - o - L, cy - t / 2, L, t);
    seg(cx + o, cy - t / 2, L, t);
  }
  if (c.ring && c.ringR > 0) {
    const rr = c.ringR * S, rw = (c.ringW || 1) * S;
    if (ow > 0) {
      ctx.beginPath(); ctx.arc(cx, cy, rr, 0, Math.PI * 2);
      ctx.strokeStyle = out; ctx.lineWidth = rw + 2 * ow; ctx.stroke();
    }
    ctx.beginPath(); ctx.arc(cx, cy, rr, 0, Math.PI * 2);
    ctx.strokeStyle = main; ctx.lineWidth = rw; ctx.stroke();
  }
  if (c.dot) {
    const d = c.dotW * S, dc = `rgba(${c.r},${c.g},${c.b},${c.dotA / 255})`;
    if (ow > 0) { ctx.fillStyle = out; ctx.fillRect(cx - d / 2 - ow, cy - d / 2 - ow, d + 2 * ow, d + 2 * ow); }
    ctx.fillStyle = dc; ctx.fillRect(cx - d / 2, cy - d / 2, d, d);
  }
}

function paintOverlay() { drawHair(ovCtx, ovCv.width, ovCv.height, cfg, 1); }
function paintPreview() { drawHair(prCtx, prCv.width, prCv.height, cfg, 1); }

const hx = (n) => ('0' + Math.round(n).toString(16)).slice(-2).toUpperCase();
function paintSwatch() {
  $('swatch').style.background = `rgb(${cfg.r},${cfg.g},${cfg.b})`;
  $('hex').textContent = `#${hx(cfg.r)}${hx(cfg.g)}${hx(cfg.b)}`;
}

function renderGallery() {
  const g = $('xhGallery');
  g.innerHTML = PRESETS.map((p) =>
    `<button class="xh-cell" data-id="${p.id}">
       <canvas width="52" height="52"></canvas>
       <span>${p.label}</span>
     </button>`).join('');

  g.querySelectorAll('.xh-cell').forEach((cell) => {
    const p = PRESETS.find((x) => x.id === cell.dataset.id);
    const tc = Object.assign(defaultCfg(), p.set, {
      custom: true, outline: false, r: 255, g: 255, b: 255, a: 255,
      dotA: 255,
    });
    const cv = cell.querySelector('canvas');
    drawHair(cv.getContext('2d'), 52, 52, tc, 1.3);
  });
}
$('xhGallery').addEventListener('click', (e) => {
  const b = e.target.closest('[data-id]'); if (!b) return;
  const p = PRESETS.find((x) => x.id === b.dataset.id); if (!p) return;
  Object.assign(cfg, p.set);
  syncEditor();
});

const SLIDERS = ['outlineW', 'outlineA', 'r', 'g', 'b', 'a', 'dotW', 'dotA', 'inW', 'inL', 'inO', 'outW', 'outL', 'outO', 'ringR', 'ringW'];
const TOGGLES = ['base', 'custom', 'adsOnly', 'outline', 'dot', 'inner', 'top', 'outer', 'ring'];

function syncEditor() {
  SLIDERS.forEach((k) => {
    const s = $('s_' + k), n = $('n_' + k);
    if (s) { s.value = cfg[k]; n.textContent = cfg[k]; }
  });
  TOGGLES.forEach((k) => {
    const t = document.querySelector(`.toggle[data-k="${k}"]`);
    if (!t) return;
    const v = t.querySelector('.val');
    v.textContent = cfg[k] ? '켜짐' : '꺼짐';
    v.className = 'val ' + (cfg[k] ? 'on' : 'off');
  });
  paintSwatch(); paintPreview();
}

SLIDERS.forEach((k) => {
  const s = $('s_' + k), n = $('n_' + k);
  if (!s) return;
  s.addEventListener('input', () => {
    cfg[k] = parseInt(s.value, 10); n.textContent = s.value;
    if (k === 'r' || k === 'g' || k === 'b') paintSwatch();
    paintPreview();
  });
});
document.querySelectorAll('.toggle').forEach((t) => {
  t.addEventListener('click', () => {
    const k = t.dataset.k; cfg[k] = !cfg[k];
    const v = t.querySelector('.val');
    v.textContent = cfg[k] ? '켜짐' : '꺼짐';
    v.className = 'val ' + (cfg[k] ? 'on' : 'off');
    paintPreview();
  });
});

let prevOn = true;
$('prevToggle').addEventListener('click', () => {
  prevOn = !prevOn;
  $('prevState').textContent = prevOn ? '켜짐' : '꺼짐';
  $('prevState').style.color = prevOn ? '#b6975a' : '#9a8f79';
  $('prevStage').style.opacity = prevOn ? '1' : '0';
});

$('xhSave').addEventListener('click', () => {
  post('save', cfg);
  $('editor').classList.add('hidden');
});
$('xhClose').addEventListener('click', closeEditor);
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeEditor(); });

function closeEditor() {
  $('editor').classList.add('hidden');
  post('closeEditor', {});
}

function post(name, data) {
  fetch(`https://cookie_crosshair/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data || {}),
  }).catch(() => {});
}

window.addEventListener('message', (ev) => {
  const d = ev.data || {};

  if (d.action === 'apply') {
    cfg = Object.assign(defaultCfg(), d.cfg || {});
    paintOverlay();
    return;
  }
  if (d.action === 'overlay') {
    $('overlay').classList.toggle('hidden', !d.show);
    if (d.show) paintOverlay();
    return;
  }
  if (d.action === 'openEditor') {
    cfg = Object.assign(defaultCfg(), d.cfg || {});
    if (Array.isArray(d.presets)) PRESETS = d.presets;
    $('editor').classList.remove('hidden');
    prevOn = true; $('prevStage').style.opacity = '1';
    $('prevState').textContent = '켜짐'; $('prevState').style.color = '#b6975a';
    renderGallery();
    syncEditor();
    return;
  }
  if (d.action === 'closeEditor') {
    $('editor').classList.add('hidden');
    return;
  }
});
