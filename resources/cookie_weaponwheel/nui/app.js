
const wheel = document.getElementById('wheel');
const ring = document.getElementById('ring');
const holsterBtn = document.getElementById('holster');

const RES = 'cookie_weaponwheel';
let currentSlot = null;
let hoveredSlot = null;

function post(name, data) {
  fetch(`https://${RES}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data || {}),
  }).catch(() => {});
}

function render(weapons, cur) {
  ring.innerHTML = '';
  currentSlot = cur ?? null;

  const old = document.querySelector('.empty-msg');
  if (old) old.remove();

  if (!weapons.length) {
    const msg = document.createElement('div');
    msg.className = 'empty-msg';
    msg.textContent = '소지한 무기가 없습니다';
    wheel.appendChild(msg);
  }

  const n = weapons.length;
  const R = Math.min(190 + n * 14, 330);

  weapons.forEach((w, i) => {
    const ang = (i / n) * Math.PI * 2 - Math.PI / 2;
    const el = document.createElement('div');
    el.className = 'wslot' + (w.slot === currentSlot ? ' current' : '');
    el.style.left = `${Math.cos(ang) * R}px`;
    el.style.top = `${Math.sin(ang) * R}px`;

    const nm = document.createElement('div');
    nm.className = 'wname';
    nm.textContent = w.label;
    el.appendChild(nm);

    const sub = document.createElement('div');
    sub.className = 'wsub';
    const bits = [];
    if (w.slot === currentSlot) bits.push('장착 중');
    if (typeof w.ammo === 'number') bits.push(`탄약 ${w.ammo}`);
    if (typeof w.durability === 'number') bits.push(`내구 ${Math.floor(w.durability)}%`);
    sub.textContent = bits.join(' · ') || `슬롯 ${w.slot}`;
    el.appendChild(sub);

    el.addEventListener('click', () => post('select', { slot: w.slot }));

    el.addEventListener('mouseenter', () => { hoveredSlot = w.slot; });
    el.addEventListener('mouseleave', () => { if (hoveredSlot === w.slot) hoveredSlot = null; });
    ring.appendChild(el);
  });

  if (currentSlot) {
    holsterBtn.classList.remove('disabled');
  } else {
    holsterBtn.classList.add('disabled');
  }
}

holsterBtn.addEventListener('click', () => {
  if (currentSlot) post('select', { slot: currentSlot });
  else post('close');
});

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'show') {
    hoveredSlot = null;
    render(d.weapons || [], d.currentSlot);
    wheel.classList.remove('hidden');
  } else if (d.action === 'hide') {
    hoveredSlot = null;
    wheel.classList.add('hidden');
  }
});

window.addEventListener('keyup', (e) => {
  if (e.key === 'Tab') {
    e.preventDefault();
    if (hoveredSlot) post('select', { slot: hoveredSlot });
    else post('close');
  }
});
window.addEventListener('keydown', (e) => {
  if (e.key === 'Tab') e.preventDefault();
  if (e.key === 'Escape') { e.preventDefault(); post('close'); }
});
window.addEventListener('contextmenu', (e) => { e.preventDefault(); post('close'); });
