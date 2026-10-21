function formatMoney(n) {
  const won = Number(n).toLocaleString('en-US') + '원';
  let sub = '';
  if (n >= 10000) {
    sub = ' <span class="won-sub">(' + Math.floor(n / 10000) + '만원)</span>';
  } else if (n >= 1000) {
    sub = ' <span class="won-sub">(' + Math.floor(n / 1000) + '천원)</span>';
  }
  return won + sub;
}

const tagNodes = {};

function renderNameTags(list) {
  const wrap = document.getElementById('nametags');
  if (!wrap) return;

  const seen = {};

  (list || []).forEach((t) => {
    seen[t.id] = true;
    let el = tagNodes[t.id];

    if (!el) {
      el = document.createElement('div');
      el.className = 'ck-tag';

      el.innerHTML =
        '<div class="ck-tag-emoji"></div>' +
        '<div class="ck-tag-top">' +
          '<span class="ck-tag-org"></span>' +
          '<span class="ck-tag-duty"></span>' +
        '</div>' +
        '<div class="ck-tag-lover"></div>' +
        '<div class="ck-tag-bot">' +
          '<span class="ck-tag-badge"></span>' +
          '<span class="ck-tag-name"></span>' +
          '<span class="ck-tag-gobun"></span>' +
        '</div>';
      wrap.appendChild(el);
      tagNodes[t.id] = el;
    }

    const em = el.children[0];
    const top = el.children[1];
    const lover = el.children[2];
    const bot = el.children[3];

    em.textContent = t.emoji || '';
    em.style.display = (t.org && t.emoji) ? '' : 'none';

    top.style.display = t.org ? '' : 'none';
    top.children[0].textContent = t.org || '';
    top.children[0].style.setProperty(
      'color',
      t.jobless ? '#9b7dff' : (t.orgColor || '#FFB800'),
      'important'
    );

    const duty = top.children[1];
    duty.textContent = t.orgDuty ? (' (' + t.orgDuty + ')') : '';
    duty.className = 'ck-tag-duty' + ((t.orgDuty === '근무중' || t.orgDuty === '출근') ? ' on' : '');

    lover.textContent = t.lover ? ('♥ ' + t.lover) : '';
    lover.style.display = t.lover ? '' : 'none';

    const badge = bot.children[0];
    const badgeText = String(t.badge || '').trim();
    badge.textContent = badgeText;
    badge.style.display = badgeText ? 'inline-flex' : 'none';

    bot.children[1].textContent = t.name || '-';
    bot.children[2].textContent = t.gobun ? ('(' + t.gobun + ')') : '';

    el.style.left = (t.x * 100) + 'vw';
    el.style.top = (t.y * 100) + 'vh';
    el.style.transform = 'translate(-50%, -50%) scale(' + (t.scale || 1) + ')';
    el.style.opacity = t.alpha != null ? t.alpha : 1;
  });

  Object.keys(tagNodes).forEach((id) => {
    if (!seen[id]) {
      tagNodes[id].remove();
      delete tagNodes[id];
    }
  });
}

const VEH_MAX_RPM = 10;
const VEH_REDLINE = 0.85;
const DIAL = { cx: 120, cy: 120, r: 108, rNum: 88, start: -135, sweep: 270 };

const vehTickEls = [];
let vehArcLen = 0;

function dialPoint(v, radius) {
  const a = (DIAL.start + (v / VEH_MAX_RPM) * DIAL.sweep) * Math.PI / 180;
  return {
    x: DIAL.cx + radius * Math.sin(a),
    y: DIAL.cy - radius * Math.cos(a)
  };
}

function buildDial() {
  const ticks = document.getElementById('vehTicks');
  const labels = document.getElementById('vehLabels');
  const arc = document.getElementById('vehArc');
  if (!ticks || !labels || !arc) return;

  const NS = 'http://www.w3.org/2000/svg';
  const step = 0.25;

  for (let v = 0; v <= VEH_MAX_RPM + 0.0001; v += step) {
    const isMajor = Math.abs(v - Math.round(v)) < 0.001;
    const p = dialPoint(v, DIAL.r);

    const dot = document.createElementNS(NS, 'circle');
    dot.setAttribute('cx', p.x.toFixed(2));
    dot.setAttribute('cy', p.y.toFixed(2));
    dot.setAttribute('r', isMajor ? 2.6 : 1.4);
    dot.setAttribute('class', 'ck-veh-tick' + (isMajor ? ' major' : '') +
      (v / VEH_MAX_RPM >= VEH_REDLINE ? ' redline' : ''));
    ticks.appendChild(dot);
    vehTickEls.push({ el: dot, v: v });

    if (isMajor) {
      const n = dialPoint(v, DIAL.rNum);
      const t = document.createElementNS(NS, 'text');
      t.setAttribute('x', n.x.toFixed(2));
      t.setAttribute('y', (n.y + 5).toFixed(2));
      t.setAttribute('text-anchor', 'middle');
      t.setAttribute('class', 'ck-veh-num');
      t.textContent = String(Math.round(v));
      labels.appendChild(t);
    }
  }

  vehArcLen = arc.getTotalLength();
  arc.style.strokeDasharray = vehArcLen;
  arc.style.strokeDashoffset = vehArcLen;
}

function vehShow(on) {
  const el = document.getElementById('vehHud');
  if (el) el.style.display = on ? 'flex' : 'none';
}

function vehSetBar(barId, fillId, value, lowAt) {
  const v = Math.max(0, Math.min(100, Number(value) || 0));
  const bar = document.getElementById(barId);
  const fill = document.getElementById(fillId);
  if (fill) fill.style.width = v + '%';
  if (bar) bar.classList.toggle('low', v <= lowAt);
}

function vehUpdate(d) {
  const speed = Math.max(0, Number(d.speed) || 0);
  const rpm = Math.max(0, Math.min(1, (Number(d.rpm) || 0) / 100));
  const hud = document.getElementById('vehHud');

  const sp = document.getElementById('vehSpeed');
  if (sp) sp.textContent = speed;

  const arc = document.getElementById('vehArc');
  if (arc && vehArcLen) arc.style.strokeDashoffset = vehArcLen * (1 - rpm);

  const cur = rpm * VEH_MAX_RPM;
  for (let i = 0; i < vehTickEls.length; i++) {
    vehTickEls[i].el.classList.toggle('on', vehTickEls[i].v <= cur + 0.001);
  }

  if (hud) hud.classList.toggle('redline', rpm >= VEH_REDLINE);

  vehSetBar('vehFuelBar', 'vehFuelFill', d.fuel, 20);
  vehSetBar('vehEngBar', 'vehEngFill', d.engine, 30);

  const belt = document.getElementById('vehBelt');
  if (belt) {
    belt.textContent = d.belt ? '벨트 착용' : '벨트 해제';
    belt.className = 'ck-veh-chip belt ' + (d.belt ? 'on' : 'off');
  }

  const gear = document.getElementById('vehGear');
  const g = Number(d.gear);
  if (gear) gear.textContent = (g === 0) ? 'R' : (speed < 1 ? 'N' : String(g));
  if (hud) hud.classList.toggle('rev', g === 0);
}

window.addEventListener('load', buildDial);

let noticeTimer = null;
let noticeTick = null;

function noticeHide() {
  const box = document.getElementById('noticeBox');
  if (!box || box.classList.contains('hidden')) return;
  box.classList.add('out');
  setTimeout(() => {
    box.classList.add('hidden');
    box.classList.remove('out');
  }, 250);
}

function showNotice(d) {
  const box = document.getElementById('noticeBox');
  const body = document.getElementById('noticeBody');
  const cnt = document.getElementById('noticeCount');
  if (!box || !body || !cnt) return;

  if (noticeTimer) { clearTimeout(noticeTimer); noticeTimer = null; }
  if (noticeTick) { clearInterval(noticeTick); noticeTick = null; }

  body.textContent = d.text || '';
  box.classList.remove('hidden', 'out');
  void box.offsetWidth;

  const secs = Number(d.seconds) || 0;

  if (secs > 0) {

    let left = secs;

    const paint = () => {
      cnt.textContent = String(left);

      cnt.style.animation = 'none';
      void cnt.offsetWidth;
      cnt.style.animation = '';
    };

    cnt.classList.remove('hidden');
    paint();

    noticeTick = setInterval(() => {
      left -= 1;
      if (left <= 0) {
        clearInterval(noticeTick);
        noticeTick = null;
        noticeHide();
        return;
      }
      paint();
    }, 1000);
  } else {

    cnt.classList.add('hidden');
    noticeTimer = setTimeout(noticeHide, (Number(d.hold) || 6) * 1000);
  }
}

function setGauge(barId, pctId, value) {
  const v = Math.max(0, Math.min(100, Math.round(Number(value) || 0)));
  const bar = document.getElementById(barId);
  if (bar) bar.style.width = v + '%';
  const pct = document.getElementById(pctId);
  if (pct) pct.textContent = v + '%';
}

function setNeedBar(barId, value) {
  const v = Math.max(0, Math.min(100, Math.round(Number(value) || 0)));
  const bar = document.getElementById(barId);
  if (bar) bar.style.width = v + '%';
}

window.addEventListener('message', (e) => {
  const d = e.data;
  if (d.action === 'cameraMode') {
    document.body.classList.toggle('ck-camera-hidden', !!d.active);
    return;
  }
  if (d.action === 'notice') { showNotice(d); return; }
  if (d.action === 'nametags') {
    renderNameTags(d.tags);
    return;
  }
  if (d.action === 'vehShow') { vehShow(true); return; }
  if (d.action === 'vehHide') { vehShow(false); return; }
  if (d.action === 'vehUpdate') { vehUpdate(d); return; }
  if (d.action === 'updateStatus') {
    setGauge('healthBar', 'healthPct', d.health);
    setGauge('armorBar', 'armorPct', d.armor);
    setNeedBar('staminaBar', d.stamina);
    setNeedBar('oxygenBar', d.oxygen);
    const vitals = document.getElementById('vitalsPanel');
    if (vitals) vitals.classList.toggle('low-health', Number(d.health || 0) <= 25);
  } else if (d.action === 'updateLocation') {
    const el = document.getElementById('hudLocation');
    if (el) el.textContent = d.text || '-';
  } else if (d.action === 'updateInfo') {
    document.getElementById('hudJob').textContent = d.job;
    document.getElementById('hudName').textContent = d.name;
    document.getElementById('hudCid').textContent = d.gobun;
    document.getElementById('hudCash').innerHTML = formatMoney(d.cash);
    document.getElementById('hudBank').innerHTML = formatMoney(d.bank);
  } else if (d.action === 'updateNeeds') {
    setNeedBar('hungerBar', d.hunger);
    setNeedBar('thirstBar', d.thirst);
  } else if (d.action === 'hudVisible') {
    document.getElementById('hud').style.display = d.visible ? 'block' : 'none';

    const nt = document.getElementById('nametags');
    if (nt) nt.style.display = d.visible ? '' : 'none';
  } else if (d.action === 'updateInfoBar') {
    document.getElementById('infoBar').style.display = 'flex';
    document.getElementById('ibDateTime').textContent = d.text;
    document.getElementById('ibPlayers').textContent = d.players;
  } else if (d.action === 'updateFps') {
    document.getElementById('ibFps').textContent = d.fps;
  } else if (d.action === 'updateWeather') {
    const cw = document.getElementById('clockWeather');
    if (!cw) return;
    cw.style.display = 'flex';
    document.getElementById('weatherIcon').textContent = d.icon || '';
    const tp = (d.temp === undefined || d.temp === null) ? '' : (' ' + d.temp + '°C');
    document.getElementById('weatherText').textContent = ((d.desc || '') + tp).trim();
  } else if (d.action === 'updateVoice') {
    showVoiceList(d.speakers || []);
  } else if (d.action === 'hideVoice') {
    document.getElementById('voiceWidget').classList.remove('show');
  } else if (d.action === 'voiceModeToast') {
    showVoiceToast(d.label);
  } else if (d.action === 'updateHotbar') {
    updateHotbar(d.slots || []);
  } else if (d.action === 'hotbarEquipped') {
    setHotbarEquipped(d.slot);
  } else if (d.action === 'hotbarCooldown') {
    startHotbarCooldown(d.slot, d.ms || 5000);
  } else if (d.action === 'updateAmmo') {

    const ammo = document.getElementById('ammoCounter');
    const clip = document.getElementById('ammoClip');
    if (clip) { clip.textContent = d.clip; clip.classList.toggle('empty', (d.clip || 0) <= 0); }
    const rsv = document.getElementById('ammoReserve');
    if (rsv) rsv.textContent = d.reserve;
    const aimg = document.getElementById('ammoImg');
    if (aimg) {
      if (d.ammo) {
        aimg.onerror = function () { aimg.style.display = 'none'; };
        aimg.src = 'nui://ox_inventory/web/images/' + d.ammo + '.png';
        aimg.style.display = 'block';
      } else { aimg.style.display = 'none'; aimg.removeAttribute('src'); }
    }
    if (ammo) ammo.style.display = 'flex';
  } else if (d.action === 'hideAmmo') {
    const ammo = document.getElementById('ammoCounter');
    if (ammo) ammo.style.display = 'none';
  } else if (d.action === 'setIbBottom') {

    const ib = document.getElementById('infoBar');
    if (ib) {
      const raw = String(d.value);
      const val = /(vh|px|%)$/.test(raw) ? raw : (raw + 'vh');
      ib.style.setProperty('--ck-ib-bottom', val);
    }
  }
});

function initHotbar() {
  const hb = document.getElementById('hotbar');
  if (!hb) return;
  hb.innerHTML = '';
  for (let i = 1; i <= 8; i++) {
    const card = document.createElement('div'); card.className = 'ck-hb-card ck-hb-empty'; card.dataset.slot = i;
    const num = document.createElement('span'); num.className = 'ck-hb-num'; num.textContent = i; card.appendChild(num);
    const img = document.createElement('img'); img.className = 'ck-hb-img'; img.style.display = 'none'; card.appendChild(img);
    const cnt = document.createElement('span'); cnt.className = 'ck-hb-count'; card.appendChild(cnt);

    const eq = document.createElement('span'); eq.className = 'ck-hb-equip'; eq.textContent = '장착중'; card.appendChild(eq);

    const cd = document.createElement('div'); cd.className = 'ck-hb-cd';
    const cdn = document.createElement('span'); cdn.className = 'ck-hb-cd-num'; cd.appendChild(cdn);
    card.appendChild(cd);
    hb.appendChild(card);
  }
}
function updateHotbar(slots) {
  const cards = document.querySelectorAll('#hotbar .ck-hb-card');
  for (let i = 0; i < cards.length; i++) {
    const s = slots[i];
    const img = cards[i].querySelector('.ck-hb-img');
    const cnt = cards[i].querySelector('.ck-hb-count');
    if (s) {
      cards[i].classList.remove('ck-hb-empty');

      img.onerror = function () { img.style.display = 'none'; };
      img.style.display = 'block'; img.src = s.image;
      cnt.textContent = (s.count && s.count > 1) ? s.count : '';
    } else {
      cards[i].classList.add('ck-hb-empty');
      img.style.display = 'none'; img.removeAttribute('src'); cnt.textContent = '';
    }
  }
}
initHotbar();

function setHotbarEquipped(slot) {
  document.querySelectorAll('#hotbar .ck-hb-card').forEach((c) => {
    c.classList.toggle('equipped', Number(c.dataset.slot) === Number(slot));
  });
}

const hbCdTimers = {};
function startHotbarCooldown(slot, ms) {
  const card = document.querySelector('#hotbar .ck-hb-card[data-slot="' + slot + '"]');
  if (!card) return;
  const cd = card.querySelector('.ck-hb-cd');
  const num = card.querySelector('.ck-hb-cd-num');
  if (hbCdTimers[slot]) cancelAnimationFrame(hbCdTimers[slot]);

  const end = performance.now() + ms;
  cd.classList.add('on');

  function tick(now) {
    const remain = end - now;
    if (remain <= 0) {
      cd.classList.remove('on');
      cd.style.background = '';
      num.textContent = '';
      delete hbCdTimers[slot];
      return;
    }
    const p = (remain / ms) * 100;
    cd.style.background = 'conic-gradient(from 0deg, rgba(0,0,0,0.62) ' + p + '%, transparent ' + p + '%)';
    num.textContent = Math.ceil(remain / 1000);
    hbCdTimers[slot] = requestAnimationFrame(tick);
  }
  hbCdTimers[slot] = requestAnimationFrame(tick);
}

function showVoiceList(speakers) {
  const list = document.getElementById('voiceList');
  list.innerHTML = '';
  speakers.forEach((s) => {
    const row = document.createElement('div'); row.className = 'ck-vc-row';
    const g = document.createElement('span'); g.className = 'ck-vc-gobun'; g.textContent = s.gobun;
    const sep = document.createElement('span'); sep.className = 'ck-vc-sep'; sep.textContent = '|';
    const n = document.createElement('span'); n.className = 'ck-vc-nick'; n.textContent = s.nick;
    row.appendChild(g); row.appendChild(sep); row.appendChild(n);
    list.appendChild(row);
  });
  document.getElementById('voiceWidget').classList.add('show');
}

let voiceToastTimer = null;
function showVoiceToast(label) {
  const t = document.getElementById('voiceToast');
  t.textContent = '음성: ' + label;
  t.classList.add('show');

  clearTimeout(voiceToastTimer);
  voiceToastTimer = setTimeout(() => t.classList.remove('show'), 1500);
}