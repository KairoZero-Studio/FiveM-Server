
const screen = document.getElementById('deathScreen');
const status = document.getElementById('dsStatus');
const acts = document.getElementById('dsActs');

function post(name, data) {
  fetch('https://cookie_medic/' + name, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data || {}),
  }).catch(() => {});
}

function resetButtons() {
  acts.querySelectorAll('[data-a]').forEach((b) => b.classList.remove('used'));
}

acts.addEventListener('click', (e) => {
  const b = e.target.closest('[data-a]');
  if (!b || b.classList.contains('used')) return;

  const kind = b.dataset.a;

  if (kind === 'revive') {
    post('declare', { kind: 'revive' });
    return;
  }

  b.classList.add('used');
  post('declare', { kind: kind });
});

const reviveBox = document.getElementById('reviveBox');
const reviveNum = document.getElementById('reviveNum');
const reviveSec = document.getElementById('reviveSec');
const regenBadge = document.getElementById('regenBadge');

window.addEventListener('message', (e) => {
  const d = e.data || {};

  if (d.action === 'show') {
    resetButtons();
    status.textContent = '';
    reviveBox.classList.add('hidden');
    regenBadge.classList.add('hidden');
    screen.classList.remove('hidden');
  } else if (d.action === 'hide') {
    reviveBox.classList.add('hidden');
    screen.classList.add('hidden');
  } else if (d.action === 'status') {
    status.textContent = d.text || '';
  } else if (d.action === 'reviveMode') {
    const boosted = d.boosted === true;
    regenBadge.classList.toggle('hidden', !boosted);
    if (boosted) status.textContent = '자가재생동기가 작동합니다.';
  } else if (d.action === 'reviveCount') {

    const s = Number(d.sec) || 0;
    reviveSec.textContent = s;
    reviveNum.textContent = s;
    reviveBox.classList.remove('hidden');

    reviveNum.classList.remove('flip');
    void reviveNum.offsetWidth;
    reviveNum.classList.add('flip');
  }
});
