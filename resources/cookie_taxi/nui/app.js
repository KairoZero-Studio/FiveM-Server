

let LINES = {};
let VEHICLES = [];
let ST = null;
let MET = null;
let pane = null;

const $ = (id) => document.getElementById(id);

function post(name, data) {
  fetch(`https://cookie_taxi/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data || {}),
  }).catch(() => {});
}

function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}

function comma(n) {
  return String(Math.floor(Number(n) || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

function say(text) {
  $('dlgSub').textContent = text || '';
}

function renderProfile() {
  const box = $('profile');

  if (!ST) {
    box.innerHTML = `<p class="tx-pf-h">택시 기사</p>
      <p class="tx-pf-muted">불러오는 중</p>`;
    return;
  }

  if (!ST.hired) {
    box.innerHTML =
      `<p class="tx-pf-h">택시 기사</p>
       <p class="tx-pf-name">${esc(ST.nick || '-')}${ST.gobun ? ` <i>(${esc(ST.gobun)})</i>` : ''}</p>
       <p class="tx-pf-muted">${ST.faction ? '이미 몸담은 곳이 있다' : '아직 택시 회사 소속이 아니다'}</p>`;

    return;
  }

  const s = ST.skill || {};
  const cur = (s.exp || 0) - (s.levelExp || 0);
  const span = s.nextExp ? (s.nextExp - (s.levelExp || 0)) : 0;
  const pct = span > 0 ? Math.min(100, Math.round((cur / span) * 100)) : 100;
  const b = s.bonus || {};

  const myVeh = ST.assigned
    ? (VEHICLES.find((v) => v.key === ST.assigned.vehKey) || {}).label
    : null;

  box.innerHTML =
    `<p class="tx-pf-h">택시 기사</p>
     <p class="tx-pf-name">${esc(ST.nick || '-')}${ST.gobun ? ` <i>(${esc(ST.gobun)})</i>` : ''}</p>

     <div class="tx-pf-lv"><span class="tx-pf-duty ${ST.onDuty ? 'on' : ''}">${ST.onDuty ? '근무중' : '퇴근'}</span></div>

     <div class="tx-pf-rows">
       <div><span>요금 배수</span><b>${(b.fare || 1).toFixed(2)}배</b></div>

       <div><span>팁 확률</span><b>${Math.round((b.tip || 0) * 100)}%</b></div>

       <div><span>누적 운행</span><b>${comma(s.total_job)}회</b></div>

       <div><span>누적 수익</span><b>${comma(s.total_pay)}원</b></div>

       <div><span>배정 차량</span><b>${myVeh ? esc(myVeh) : '없음'}</b></div>

       ${ST.assigned ? `<div><span>번호판</span><b>${esc(ST.assigned.plate)}</b></div>` : ''}
     </div>

     ${ST.debt > 0
        ? `<p class="tx-pf-debt">미납 변상금 ${comma(ST.debt)}원</p>`
        : ''}`;
}

function renderActs() {
  const acts = [];

  if (ST && ST.faction && !ST.hired) {
    acts.push({ k: 'close', label: '나가기' });
  } else if (!ST || !ST.hired) {
    acts.push({ k: 'hire', label: '콜택시에서 일하고 싶습니다' });
    acts.push({ k: 'close', label: '나가기' });
  } else {

    acts.push({
      k: 'assign',
      label: (ST.assigned ? '택시를 반납하고 싶습니다' : '택시를 배정 받고 싶습니다'),
    });
    acts.push({ k: 'duty', label: ST.onDuty ? '퇴근하겠습니다' : '출근하겠습니다' });
    if (ST.debt > 0) acts.push({ k: 'debt', label: '변상금을 갚겠습니다' });
    acts.push({ k: 'quit', label: '그만두겠습니다' });
    acts.push({ k: 'close', label: '나가기' });
  }

  $('acts').innerHTML = acts.map((a) =>
    `<button class="tx-act${a.k === 'quit' ? ' danger' : ''}` +
      `${a.k === pane ? ' on' : ''}" data-k="${a.k}">${esc(a.label)}</button>`).join('');

}

function renderAssign() {
  const lv = (ST && ST.level) || 1;

  if (!ST || !ST.hired) { say(LINES.needHire); return; }
  if (ST.debt > 0) say(LINES.hasDebt);
  else if (lv >= 5) say(LINES.assignHigh);
  else if (lv >= 3) say(LINES.assignMid);
  else say(LINES.assignLow);

  const images = (ST && ST.images) || {};
  const mine = ST.assigned && ST.assigned.vehKey;

  const cards = VEHICLES.map((v) => {
    const locked = lv < v.level;
    const isMine = mine === v.key;
    const img = images[v.model];

    return `<div class="tx-card${locked ? ' locked' : ''}${isMine ? ' mine' : ''}">
        <div class="tx-card-img">
          ${img
            ? `<img src="${img}" alt="">`
            : `<span class="tx-card-noimg">미리보기 없음</span>`}

        </div>

        <div class="tx-card-body">
          <div class="tx-card-top">
            <b class="tx-card-n">${esc(v.label)}</b>

            <span class="tx-card-lv${locked ? ' lock' : ''}">${
              locked ? `LV${v.level} 필요` : `LV${v.level}`}</span>

          </div>

          <div class="tx-card-fee">파손 시 최대 ${comma(v.repairFee)}원, 분실 시 ${comma(v.lossFee)}원</div>

          ${isMine
            ? `<button class="tx-cta ghost" data-ret="1">반납하기</button>`
            : `<button class="tx-cta" data-a="${esc(v.key)}"${locked ? ' disabled' : ''}>${
                locked ? '아직 이르네' : '배정 받기'}</button>`}
        </div>

      </div>`;

  }).join('');

  $('paneTitle').textContent = (ST.assigned ? '차량 반납' : '차량 배정');
  $('paneBody').innerHTML =
    `<div class="tx-cards">${cards}</div>` +
    `<p class="tx-note">차량은 무상으로 지급된다. 다만 부수면 자네가 문다.</p>` +
    (ST.onDuty ? '' : `<p class="tx-warn">출근해야 차를 내준다</p>`);
}

function renderPane() {
  const el = $('pane');
  if (pane !== 'assign') { el.classList.add('hidden'); return; }
  el.classList.remove('hidden');
  renderAssign();
}

$('acts').addEventListener('click', (e) => {
  const b = e.target.closest('[data-k]');
  if (!b) return;
  const k = b.dataset.k;

  if (k === 'close') { post('close'); return; }
  if (k === 'hire') { post('hire'); return; }
  if (k === 'quit') { post('quit'); pane = null; renderPane(); return; }
  if (k === 'debt') { post('payDebt'); return; }
  if (k === 'duty') { post('duty', { on: !(ST && ST.onDuty) }); return; }

  pane = (pane === k) ? null : k;
  renderActs();
  renderPane();
});

$('pane').addEventListener('click', (e) => {
  const a = e.target.closest('[data-a]');
  if (a && !a.disabled) { post('assign', { key: a.dataset.a }); return; }

  const r = e.target.closest('[data-ret]');
  if (r) post('returnVeh');
});

$('meter').addEventListener('click', (e) => {
  if (!$('meter').classList.contains('live')) return;

  const b = e.target.closest('[data-m]');
  if (!b || b.disabled) return;

  const m = b.dataset.m;

  if (m === 'drive') post('meterStart', { intercity: !!(MET && MET.intercity) });

  if (m === 'inter') post('meterStart', { intercity: !(MET && MET.intercity), only: !(MET && MET.started) });

  if (m === 'pay')   post('meterPay');
  if (m === 'empty') post('setAvailable', { on: !(MET && MET.available) });
  if (m === 'npc')   post('setNpcCall', { on: !(MET && MET.npcCall) });
});

document.addEventListener('keydown', (e) => {
  const live = $('meter').classList.contains('live');

  if (e.key === 'F2' && live) {
    e.preventDefault();
    post('meterCursorOff');
    return;
  }

  if (e.key !== 'Escape') return;
  if (!$('dlg').classList.contains('hidden')) { post('close'); return; }
  if (live) post('meterCursorOff');
});

window.addEventListener('message', (ev) => {
  const d = ev.data || {};

  if (d.action === 'open') {
    LINES = d.lines || {};
    VEHICLES = d.vehicles || [];
    pane = null;
    ST = null;
    $('npcName').textContent = d.npc || '-';
    $('dlg').classList.remove('hidden');
    say(LINES.greet);
    renderProfile();
    renderActs();
    renderPane();
    return;
  }

  if (d.action === 'close') {
    $('dlg').classList.add('hidden');
    pane = null;
    return;
  }

  if (d.action === 'state') {
    ST = d.state || null;
    renderProfile();
    renderActs();
    renderPane();

    if (!$('dlg').classList.contains('hidden') && !pane) {
      if (ST && ST.faction) say(LINES.greetFaction);
      else if (ST && ST.hired) say(LINES.greetHired);
      else say(LINES.greet);
    }
    return;
  }

  if (d.action === 'pickBadge') {
    const el = $('pickBadge');
    if (!d.show) { el.classList.add('hidden'); return; }
    el.querySelector('.tx-badge-t').textContent = d.text || '손님 태우기';
    el.style.left = (d.x * 100) + '%';
    el.style.top = (d.y * 100) + '%';
    el.classList.remove('hidden');
    return;
  }

  if (d.action === 'status') {
    const el = $('status');
    if (!d.status) { el.classList.add('hidden'); return; }
    const driving = d.status === 'driving';
    el.classList.toggle('go', driving);
    $('statusText').textContent = driving ? '운행중' : '접수 대기중';
    el.classList.remove('hidden');
    return;
  }

  if (d.action === 'meter') {
    const el = $('meter');
    if (!d.show) { el.classList.add('hidden'); return; }

    MET = d;

    $('meterFare').textContent = comma(d.fare);
    $('meterDist').textContent = ((Number(d.meters) || 0) / 1000).toFixed(2);

    const b = (m) => el.querySelector(`[data-m="${m}"]`);
    const idle = !!d.idle;

    (function () {
      const ring = $('meterRing');
      if (!ring) return;
      const C = 2 * Math.PI * 52;
      const meters = Number(d.meters) || 0;
      const free = Number(d.free) || 1000;
      const step = Number(d.step) || 500;

      let seg = 0;
      if (d.started && meters > free && step > 0) {
        seg = ((meters - free) % step) / step;
      }
      ring.style.strokeDasharray = C;
      ring.style.strokeDashoffset = C * (1 - seg);

      const spinning = d.started && meters > free;
      $('meterRing').classList.toggle('go', spinning);
    })();

    const running = !idle && d.started && !d.arrived;
    const waiting = idle && d.available;
    $('meterStatusT').textContent =
      idle
        ? (d.available ? '배차 진행중' : '빈차')
        : (d.arrived ? '정차 결제 대기'
                     : (d.started ? (d.intercity ? '운행중 (할증)' : '운행중') : '승차 완료'));

    $('meterStatus').classList.toggle('live', running || waiting);

    $('meterState').textContent =
      idle
        ? (d.available ? '배차 대기중' : '빈차')
        : (d.arrived ? '도착 결제 대기'
                     : (d.started ? (d.intercity ? '주행중 (할증)' : '주행중') : '승차 주행 대기'));

    b('empty').classList.toggle('on', idle && d.available);
    b('empty').disabled = !idle;

    b('drive').classList.toggle('on', d.started);
    b('drive').disabled = idle || d.arrived;

    b('drive').classList.toggle('call', !idle && !d.started && !d.arrived);

    b('inter').classList.toggle('on', d.started && d.intercity);
    b('inter').disabled = idle || d.arrived;

    b('pay').classList.toggle('on', !!d.arrived);
    b('pay').disabled = !(d.started && d.arrived);

    const npc = $('meterNpc');
    npc.textContent = d.npcCall ? 'ON' : 'OFF';
    npc.classList.toggle('on', !!d.npcCall);

    $('meterHint').textContent =
      idle
        ? (d.available ? '' : '[빈차]를 눌러 배차를 받으세요')
        : (d.arrived ? '[결제]를 누르세요'
                     : (d.started ? '' : '[주행]을 눌러 미터기를 켜세요'));

    el.classList.remove('hidden');
    return;
  }

  if (d.action === 'meterCursor') {
    $('meter').classList.toggle('live', !!d.on);
    return;
  }

  if (d.action === 'receipt') {
    const now = new Date();
    const yy = String(now.getFullYear()).slice(2);
    const pad = (n) => String(n).padStart(2, '0');

    $('rcGuest').textContent = d.guest || '손님';
    $('rcDate').textContent = `${yy}/${pad(now.getMonth() + 1)}/${pad(now.getDate())}`;
    $('rcTime').textContent = `${pad(now.getHours())}:${pad(now.getMinutes())}`;

    const s = Number(d.elapsed) || 0;
    $('rcElapsed').textContent =
      `${pad(Math.floor(s / 3600))}:${pad(Math.floor((s % 3600) / 60))}:${pad(s % 60)}`;
    $('rcDist').textContent = ((Number(d.meters) || 0) / 1000).toFixed(1) + 'km';

    const inter = Number(d.intFee) || 0;
    $('rcFare').textContent = comma((d.fare || 0) - inter) + '원';
    $('rcInter').textContent = comma(inter) + '원';

    const extra = (Number(d.total) || 0) - (Number(d.fare) || 0);
    $('rcExtra').textContent = (extra >= 0 ? '' : '-') + comma(Math.abs(extra)) + '원';

    $('rcTotal').textContent = comma(d.total) + '원';
    $('rcExp').textContent = `경력 +${comma(d.exp)}`;

    const el = $('receipt');
    el.classList.remove('hidden');
    clearTimeout(el._t);
    el._t = setTimeout(() => el.classList.add('hidden'), 9000);
    return;
  }

  if (d.action === 'offer') {
    const el = $('offer');

    if (!d.show) {
      clearInterval(el._iv);
      el.classList.add('hidden');
      return;
    }

    $('offerGuest').textContent = d.guest || '손님';
    $('offerDest').textContent = d.dest || '목적지';

    const ttl = (Number(d.ttl) || 20) * 1000;
    const t0 = Date.now();
    const bar = $('offerBar');

    clearInterval(el._iv);
    bar.style.width = '100%';
    el._iv = setInterval(() => {
      const left = Math.max(0, 1 - (Date.now() - t0) / ttl);
      bar.style.width = (left * 100) + '%';
      if (left <= 0) {
        clearInterval(el._iv);
        el.classList.add('hidden');
      }
    }, 50);

    el.classList.remove('hidden');
    return;
  }

  if (d.action === 'sub') {
    const el = $('sub');
    if (!d.text) { el.classList.add('hidden'); return; }
    $('subText').textContent = d.text;
    el.classList.remove('hidden');
    clearTimeout(el._t);
    el._t = setTimeout(() => el.classList.add('hidden'), 6000);
    return;
  }

  if (d.action === 'speech') {
    const el = $('speech');
    if (!d.show) { el.classList.add('hidden'); return; }
    $('speechText').textContent = d.text || '';
    el.style.left = (d.x * 100) + '%';
    el.style.top = (d.y * 100) + '%';
    el.classList.remove('hidden');
    return;
  }

  if (d.action === 'bill') {
    const el = $('bill');
    if (d.show === false) { el.classList.add('hidden'); return; }

    const inter = Number(d.intFee) || 0;
    const fare = Number(d.fare) || 0;

    $('billGuest').textContent = d.guest || '손님';
    $('billDest').textContent = d.dest || '목적지';
    $('billDist').textContent = ((Number(d.meters) || 0) / 1000).toFixed(1) + 'km';
    $('billFare').textContent = comma(fare - inter) + '원';
    $('billInter').textContent = comma(inter) + '원';
    $('billTotal').textContent = comma(fare) + '원';

    el.classList.remove('hidden');
    return;
  }
});

document.getElementById('billPay').addEventListener('click', () => {
  post('meterPay');
});
document.getElementById('billCancel').addEventListener('click', () => {
  $('bill').classList.add('hidden');
});
