const panel = document.getElementById('panel');
const tabs = [...document.querySelectorAll('nav button[data-tab]')];
let selfData = null;
let adminData = { players: [], catalog: [] };

function post(name, data = {}) {
  return fetch('https://' + GetParentResourceName() + '/' + name, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data)
  }).then(r => r.json()).catch(() => ({}));
}

function esc(v) {
  return String(v ?? '')
    .replaceAll('&','&amp;')
    .replaceAll('<','&lt;')
    .replaceAll('>','&gt;')
    .replaceAll('"','&quot;');
}

function setTab(id) {
  tabs.forEach(b => b.classList.toggle('active', b.dataset.tab === id));
  document.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t.id === id));
}

function renderMine() {
  if (!selfData) return;
  document.getElementById('profile').textContent = (selfData.displayName || '') + ' · 보유한 항목에서 하나씩 장착할 수 있습니다.';

  const maps = {
    chat_title: document.getElementById('chatList'),
    overhead_title: document.getElementById('headList'),
    killfeed_skin: document.getElementById('feedList')
  };

  Object.values(maps).forEach(el => el.innerHTML = '');

  (selfData.owned || []).forEach(item => {
    const root = maps[item.type];
    if (!root) return;
    const div = document.createElement('div');
    div.className = 'card' + (item.active ? ' active' : '');
    div.innerHTML =
      '<div><span class="tag" style="color:' + esc(item.color) + '">' + esc(item.label) + '</span>' +
      '<div style="font-size:11px;opacity:.45">' + esc(item.code) + '</div></div>' +
      '<button>' + (item.active ? '장착중' : '장착') + '</button>';
    div.querySelector('button').onclick = () => post('equip', { type: item.type, code: item.code });
    root.appendChild(div);
  });

  document.getElementById('adminTab').classList.toggle('hidden', !selfData.admin);
}

function renderAdmin() {
  const select = document.getElementById('targetPlayer');
  const prev = select.value;
  select.innerHTML = '';
  (adminData.players || []).forEach(p => {
    const o = document.createElement('option');
    o.value = p.source;
    o.textContent = '[' + p.source + '] ' + p.name + ' · ' + p.citizenid;
    select.appendChild(o);
  });
  if ([...select.options].some(o => o.value === prev)) select.value = prev;

  const catalog = document.getElementById('catalog');
  catalog.innerHTML = '';
  (adminData.catalog || []).forEach(item => {
    const row = document.createElement('div');
    row.className = 'catalog-row';
    row.innerHTML =
      '<strong style="color:' + esc(item.color) + '">' + esc(item.label) + '</strong>' +
      '<div style="font-size:11px;opacity:.5">' + esc(item.type) + ' · ' + esc(item.code) + '</div>' +
      '<div class="actions"><button data-a="grant">지급</button><button data-a="revoke">회수</button></div>';
    row.querySelector('[data-a="grant"]').onclick = () => {
      const target = Number(select.value);
      if (target) post('adminGrant', { target, code: item.code });
    };
    row.querySelector('[data-a="revoke"]').onclick = () => {
      const target = Number(select.value);
      if (target) post('adminRevoke', { target, code: item.code });
    };
    catalog.appendChild(row);
  });
}

function addKill(data) {
  const feed = document.getElementById('feed');
  const row = document.createElement('div');
  const theme = ['default','gold','pink','ice'].includes(data.theme) ? data.theme : 'default';
  row.className = 'kill ' + theme;
  row.style.setProperty('--accent', data.accent || '#fff');

  const head = data.headshot ? 'HEADSHOT · ' : '';
  row.innerHTML =
    '<div class="killer">' + esc(data.killer) + '</div>' +
    '<div class="middle"><div class="weapon">' + esc(data.weapon) + '</div>' +
    '<div class="detail">' + head + esc(data.distance) + 'm</div></div>' +
    '<div class="victim">' + esc(data.victim) + '</div>';

  feed.prepend(row);
  while (feed.children.length > 6) feed.lastChild.remove();

  setTimeout(() => {
    row.style.transition = 'opacity .25s, transform .25s';
    row.style.opacity = '0';
    row.style.transform = 'translateX(25px)';
    setTimeout(() => row.remove(), 300);
  }, Number(data.duration || 7000));
}

window.addEventListener('message', e => {
  const m = e.data || {};
  if (m.action === 'open') {
    selfData = m.data || selfData;
    panel.classList.remove('hidden');
    renderMine();
    setTab(m.mode === 'admin' && selfData && selfData.admin ? 'admin' : 'mine');
    if (m.mode === 'admin') post('refreshAdmin');
  } else if (m.action === 'selfData') {
    selfData = m.data;
    renderMine();
  } else if (m.action === 'adminData') {
    adminData = m.data || adminData;
    renderAdmin();
  } else if (m.action === 'killfeed') {
    addKill(m.data || {});
  }
});

document.getElementById('close').onclick = () => {
  panel.classList.add('hidden');
  post('close');
};

document.addEventListener('keydown', e => {
  if (e.key === 'Escape' && !panel.classList.contains('hidden')) {
    panel.classList.add('hidden');
    post('close');
  }
});

tabs.forEach(b => b.onclick = () => setTab(b.dataset.tab));

document.querySelectorAll('.unequip').forEach(b => {
  b.onclick = () => post('equip', { type: b.dataset.type, code: '' });
});

document.getElementById('refreshAdmin').onclick = () => post('refreshAdmin');

document.getElementById('createItem').onclick = () => {
  post('adminCreate', {
    type: document.getElementById('newType').value,
    code: document.getElementById('newCode').value,
    label: document.getElementById('newLabel').value,
    color: document.getElementById('newColor').value,
    theme: document.getElementById('newTheme').value
  });
};
