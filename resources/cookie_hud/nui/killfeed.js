/* COOKIE HUD Killfeed - TURN weapon-icon set, using the existing identityfx death event.
   Rendering is independent of the standard HUD app.js to keep other HUD features safe. */
(() => {
  'use strict';
  const feed = document.getElementById('cookieKillFeed');
  if (!feed) return;
  const MAX_ROWS = 5;
  const SAFE_ICON = /^[a-z0-9_]+$/;
  const SAFE_COLOR = /^#[0-9a-fA-F]{6}$/;
  const THEMES = new Set(['default', 'gold', 'pink', 'ice']);

  function shorten(v, max = 26) {
    const s = String(v ?? '');
    return s.length > max ? s.slice(0, max - 1) + '…' : s;
  }

  function addKill(d) {
    const row = document.createElement('div');
    const theme = THEMES.has(d.theme) ? d.theme : 'default';
    row.className = 'ck-kf-row ck-kf-' + theme;
    if (SAFE_COLOR.test(String(d.accent || ''))) {
      row.style.setProperty('--ck-kf-accent', d.accent);
    }

    const killer = document.createElement('span');
    killer.className = 'ck-kf-killer';
    killer.textContent = shorten(d.killer || 'WORLD');
    killer.title = String(d.killer || 'WORLD');

    const iconWrap = document.createElement('span');
    iconWrap.className = 'ck-kf-icon-wrap';
    const icon = document.createElement('img');
    icon.className = 'ck-kf-icon';
    icon.alt = shorten(d.weapon || '무기');
    let iconName = String(d.weaponIcon || 'weapon_unarmed').toLowerCase();
    if (!SAFE_ICON.test(iconName)) iconName = 'weapon_unarmed';
    icon.src = 'weapons/' + iconName + '.webp';
    icon.onerror = () => {
      icon.onerror = null;
      icon.src = 'weapons/weapon_unarmed.webp';
    };
    iconWrap.appendChild(icon);

    const victim = document.createElement('span');
    victim.className = 'ck-kf-victim';
    victim.textContent = shorten(d.victim || 'UNKNOWN');
    victim.title = String(d.victim || 'UNKNOWN');

    row.append(killer, iconWrap, victim);
    if (d.headshot === true) {
      const headshot = document.createElement('span');
      headshot.className = 'ck-kf-headshot';
      headshot.textContent = 'HEADSHOT';
      row.appendChild(headshot);
    }

    feed.prepend(row);
    while (feed.children.length > MAX_ROWS) feed.lastElementChild.remove();
    const duration = Math.max(3000, Math.min(15000, Number(d.duration) || 7000));
    window.setTimeout(() => {
      if (!row.isConnected) return;
      row.classList.add('ck-kf-out');
      window.setTimeout(() => row.remove(), 320);
    }, duration);
  }

  window.addEventListener('message', event => {
    const msg = event.data || {};
    if (msg.action === 'cookieKillfeed' && msg.data && typeof msg.data === 'object') {
      addKill(msg.data);
    }
  });
})();
