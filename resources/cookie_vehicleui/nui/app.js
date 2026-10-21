const seatPanel = document.getElementById('seatPanel');
const seatVehicleName = document.getElementById('seatVehicleName');
const seatCount = document.getElementById('seatCount');
const seatGrid = document.getElementById('seatGrid');
const engineState = document.getElementById('engineState');
const lockState = document.getElementById('lockState');
const beltState = document.getElementById('beltState');

const doorPanel = document.getElementById('doorPanel');
const doorVehicleName = document.getElementById('doorVehicleName');
const doorGrid = document.getElementById('doorGrid');
const closeDoorMenu = document.getElementById('closeDoorMenu');
const closeAllDoors = document.getElementById('closeAllDoors');

const resource = typeof GetParentResourceName === 'function'
  ? GetParentResourceName()
  : 'cookie_vehicleui';


async function post(name, body = {}) {
  try {
    const response = await fetch(`https://${resource}/${name}`, {
      method: 'POST',
      headers: {'Content-Type':'application/json; charset=UTF-8'},
      body: JSON.stringify(body)
    });
    return await response.json();
  } catch (_) {
    return null;
  }
}

function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, ch => ({
    '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'
  })[ch]);
}

function setQuick(el, label, active, warning = false) {
  el.textContent = `● ${label}`;
  el.className = `quick ${active ? 'on' : warning ? 'warn' : ''}`;
}

function renderSeats(data) {
  if (!data) return;

  seatVehicleName.textContent = data.vehicle || '차량 좌석';
  seatCount.textContent = `${Number(data.seatCount || 0)} SEATS`;

  setQuick(engineState, data.engineOn ? '시동 ON' : '시동 OFF', !!data.engineOn, !data.engineOn);
  setQuick(lockState, data.unlocked ? '잠금 해제' : '잠금', !!data.unlocked, !data.unlocked);
  setQuick(beltState, data.seatbelt ? '벨트 ON' : '벨트 OFF', !!data.seatbelt, !data.seatbelt);

  seatGrid.innerHTML = (data.seats || []).map(seat => `
    <div
      class="seat ${esc(seat.status)}"
      data-seat-slot="${Number(seat.slot || 1)}"
      data-seat-status="${esc(seat.status)}"
    >
      <div class="seat-icon">${Number(seat.slot || 0)}</div>
      <div class="seat-copy">
        <div class="seat-name">${esc(seat.label)}</div>
        <div class="seat-status">${esc(
          seat.status === 'empty' ? '클릭해서 이동' : seat.statusText
        )}</div>
      </div>
    </div>
  `).join('');

  seatGrid.querySelectorAll('.seat.empty').forEach(seatEl => {
    seatEl.addEventListener('click', async (event) => {
      event.preventDefault();
      event.stopPropagation();

      const slot = Number(seatEl.dataset.seatSlot);
      if (!Number.isInteger(slot) || slot < 1) return;
      if (seatGrid.dataset.moving === '1') return;

      seatGrid.dataset.moving = '1';

      const allSeats = seatGrid.querySelectorAll('.seat');
      allSeats.forEach(el => el.classList.add('input-locked'));
      seatEl.classList.add('moving');

      const result = await post('seatMove', { slot });

      seatGrid.dataset.moving = '0';

      if (result?.data) {
        renderSeats(result.data);
      } else {
        allSeats.forEach(el => {
          el.classList.remove('input-locked');
          el.classList.remove('moving');
        });
      }
    });
  });
}

function renderDoors(data) {
  if (!data) return;

  doorVehicleName.textContent = data.vehicle || '차량 문 제어';

  doorGrid.innerHTML = (data.controls || []).map(control => `
    <button class="door-btn ${control.open ? 'open' : ''}" data-door="${Number(control.id)}">
      <span class="door-name">${esc(control.label)}</span>
      <span class="door-action">${control.open ? '닫기' : '열기'}</span>
    </button>
  `).join('');

  doorGrid.querySelectorAll('.door-btn').forEach(button => {
    button.addEventListener('click', async () => {
      const result = await post('doorToggle', {
        id: Number(button.dataset.door)
      });
      if (result?.data) renderDoors(result.data);
    });
  });
}

window.addEventListener('message', event => {
  const msg = event.data || {};

  if (msg.action === 'seatOpen') {
    renderSeats(msg.data);
    seatPanel.classList.remove('hidden');
  }

  if (msg.action === 'seatUpdate') {
    renderSeats(msg.data);
  }

  if (msg.action === 'seatClose') {
    seatPanel.classList.add('hidden');
  }

  if (msg.action === 'doorOpen') {
    renderDoors(msg.data);
    doorPanel.classList.remove('hidden');
  }

  if (msg.action === 'doorClose') {
    doorPanel.classList.add('hidden');
  }
});

closeDoorMenu.addEventListener('click', () => post('doorMenuClose'));

closeAllDoors.addEventListener('click', async () => {
  const result = await post('doorCloseAll');
  if (result?.data) renderDoors(result.data);
});

window.addEventListener('keydown', async event => {
  const key = event.key.toLowerCase();
  const seatOpen = !seatPanel.classList.contains('hidden');
  const doorOpen = !doorPanel.classList.contains('hidden');

  if (seatOpen && (key === 'm' || event.key === 'Escape')) {
    event.preventDefault();
    await post('seatMenuClose');
    return;
  }

  if (doorOpen && (key === 'j' || event.key === 'Escape')) {
    event.preventDefault();
    await post('doorMenuClose');
  }
});
