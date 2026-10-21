(() => {
  const pane = document.getElementById('paneDoors');
  const tab = document.getElementById('rtabDoors');
  const list = document.getElementById('doorAdminList');
  const modal = document.getElementById('doorAdminModal');
  if (!pane || !tab || !list || !modal) return;

  let rows = [];
  let editId = null;
  let draftLeaves = null;
  let permissionOptions = [];

  const post = (name, data = {}) => fetch('https://cookie_admin/' + name, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  }).catch(() => null);

  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[c]));

  const jobsText = (door) => {
    const jobs = Array.isArray(door.jobs) ? door.jobs : [];
    if (!jobs.length) return '관리자만';
    if (jobs.length === 1 && jobs[0] === '*') return '모든 플레이어';
    const labels = new Map(permissionOptions.map((p) => [String(p.key), String(p.label || p.key)]));
    return jobs.map((j) => labels.get(String(j)) || j).join(', ');
  };

  function requestDoorAdminList() {
    list.innerHTML = '<div class="ck-zone-empty">문 목록을 불러오는 중입니다</div>';
    post('doorAdminRequest');
  }
  window.requestDoorAdminList = requestDoorAdminList;

  function renderDoorAdminList(state = {}) {
    if (state.unavailable) {
      list.innerHTML = '<div class="ck-zone-empty">cookie_doorlock 리소스가 실행 중이 아닙니다.</div>';
      return;
    }
    if (state.denied) {
      list.innerHTML = '<div class="ck-zone-empty">문 관리 권한이 없습니다. 관리자 근무 상태를 확인해주세요.</div>';
      return;
    }
    if (!rows.length) {
      list.innerHTML = '<div class="ck-zone-empty">등록된 문이 없습니다.</div>';
      return;
    }

    list.innerHTML = rows.map((d) => {
      const leafCount = Array.isArray(d.leaves) ? d.leaves.length : 0;
      const locked = !!d.locked;
      const duty = d.requireDuty ? ' · 근무중만' : '';
      return `
        <div class="ck-door-card" data-id="${Number(d.id) || 0}">
          <div class="ck-door-card-main">
            <div class="ck-door-card-title">
              <span class="ck-door-state ${locked ? 'locked' : 'open'}">${locked ? '🔒 잠김' : '🔓 열림'}</span>
              <b>${esc(d.label || ('문 #' + d.id))}</b>
              <small>#${Number(d.id) || 0}</small>
            </div>
            <div class="ck-door-card-meta">
              <span>${leafCount === 2 ? '양문' : '단일문'}</span>
              <span>직업: ${esc(jobsText(d))}</span>
              <span>최소 직급: ${Number(d.minGrade) || 0}${duty}</span>
              <span>거리: ${(Number(d.interactDistance) || 2).toFixed(1)}m</span>
            </div>
          </div>
          <div class="ck-door-card-actions">
            <button class="ck-door-btn state" data-door-action="state" data-id="${Number(d.id) || 0}" data-locked="${locked ? '1' : '0'}">${locked ? '잠금 해제' : '잠그기'}</button>
            <button class="ck-door-btn" data-door-action="edit" data-id="${Number(d.id) || 0}">수정</button>
            <button class="ck-door-btn danger" data-door-action="delete" data-id="${Number(d.id) || 0}">삭제</button>
          </div>
        </div>`;
    }).join('');
  }

  function renderPermissionOptions(selected = []) {
    const box = document.getElementById('doorPermissionOptions');
    if (!box) return;
    const chosen = new Set((selected || []).map(String));
    const all = [{ key: '*', label: '모든 플레이어', kind: 'special' }].concat(permissionOptions || []);
    box.innerHTML = all.map((p) => `
      <label class="ck-door-permission-chip">
        <input type="checkbox" data-door-permission="${esc(p.key)}" ${chosen.has(String(p.key)) ? 'checked' : ''}>
        <span>${esc(p.label || p.key)}</span>
      </label>`).join('');
  }

  function selectedPermissions() {
    const checked = Array.from(document.querySelectorAll('#doorPermissionOptions [data-door-permission]:checked')).map((el) => String(el.dataset.doorPermission || ''));
    if (checked.includes('*')) return ['*'];
    return checked.filter((v) => v && v !== '*');
  }

  function setVal(id, value) {
    const el = document.getElementById(id);
    if (el) el.value = value ?? '';
  }
  function setChecked(id, value) {
    const el = document.getElementById(id);
    if (el) el.checked = !!value;
  }

  function openCreateModal(leaves) {
    editId = null;
    draftLeaves = Array.isArray(leaves) ? leaves : [];
    document.getElementById('doorModalTitle').textContent = draftLeaves.length === 2 ? '양문 등록' : '단일 문 등록';
    document.getElementById('doorModalMeta').textContent = `선택된 문 ${draftLeaves.length}개`;
    setVal('doorFormLabel', '');
    renderPermissionOptions([]);
    setVal('doorFormGrade', 0);
    setVal('doorFormDistance', 2.0);
    setChecked('doorFormDuty', false);
    setChecked('doorFormLocked', true);
    document.getElementById('doorFormLockedRow')?.classList.remove('hidden');
    modal.classList.remove('hidden');
    setTimeout(() => document.getElementById('doorFormLabel')?.focus(), 50);
  }

  function openEditModal(door) {
    editId = Number(door.id);
    draftLeaves = null;
    document.getElementById('doorModalTitle').textContent = '문 설정 수정';
    document.getElementById('doorModalMeta').textContent = `#${editId} · ${(door.leaves || []).length === 2 ? '양문' : '단일문'}`;
    setVal('doorFormLabel', door.label || '');
    renderPermissionOptions(Array.isArray(door.jobs) ? door.jobs : []);
    setVal('doorFormGrade', Number(door.minGrade) || 0);
    setVal('doorFormDistance', Number(door.interactDistance) || 2.0);
    setChecked('doorFormDuty', !!door.requireDuty);
    document.getElementById('doorFormLockedRow')?.classList.add('hidden');
    modal.classList.remove('hidden');
  }

  function closeModal() {
    modal.classList.add('hidden');
    editId = null;
    draftLeaves = null;
  }

  function collectForm() {
    const label = String(document.getElementById('doorFormLabel')?.value || '').trim();
    if (!label) {
      if (typeof showToast === 'function') showToast('문 이름을 입력하세요.', true);
      return null;
    }
    let distance = Number(document.getElementById('doorFormDistance')?.value || 2);
    distance = Math.max(1, Math.min(6, Number.isFinite(distance) ? distance : 2));
    let grade = Math.floor(Number(document.getElementById('doorFormGrade')?.value || 0));
    grade = Math.max(0, Math.min(99, Number.isFinite(grade) ? grade : 0));
    return {
      label,
      jobs: selectedPermissions(),
      minGrade: grade,
      requireDuty: !!document.getElementById('doorFormDuty')?.checked,
      interactDistance: distance,
    };
  }

  document.getElementById('doorRefreshBtn')?.addEventListener('click', requestDoorAdminList);
  document.getElementById('doorAddSingleBtn')?.addEventListener('click', () => post('doorAdminCapture', { mode: 'single' }));
  document.getElementById('doorAddDoubleBtn')?.addEventListener('click', () => post('doorAdminCapture', { mode: 'double' }));
  document.getElementById('doorMergeDoubleBtn')?.addEventListener('click', () => post('doorAdminMergeCapture'));

  list.addEventListener('click', (e) => {
    const btn = e.target.closest('[data-door-action]');
    if (!btn) return;
    const id = Number(btn.dataset.id);
    const door = rows.find((d) => Number(d.id) === id);
    if (!door) return;

    if (btn.dataset.doorAction === 'state') {
      post('doorAdminSetState', { id, locked: !door.locked });
      return;
    }
    if (btn.dataset.doorAction === 'edit') {
      openEditModal(door);
      return;
    }
    if (btn.dataset.doorAction === 'delete') {
      if (confirm(`'${door.label || ('문 #' + id)}' 문 설정을 삭제할까요?`)) {
        post('doorAdminDelete', { id });
      }
    }
  });

  document.getElementById('doorModalClose')?.addEventListener('click', closeModal);
  document.getElementById('doorModalCancel')?.addEventListener('click', closeModal);
  document.getElementById('doorModalSave')?.addEventListener('click', () => {
    const data = collectForm();
    if (!data) return;

    if (editId) {
      data.id = editId;
      post('doorAdminUpdate', data);
    } else {
      if (!Array.isArray(draftLeaves) || !draftLeaves.length) {
        if (typeof showToast === 'function') showToast('선택된 문 정보가 없습니다.', true);
        return;
      }
      data.leaves = draftLeaves;
      data.locked = !!document.getElementById('doorFormLocked')?.checked;
      post('doorAdminCreate', data);
    }
    closeModal();
  });

  document.querySelectorAll('#rightTabs .ck-rtab').forEach((t) => {
    t.addEventListener('click', () => {
      const on = t.dataset.pane === 'doors';
      pane.classList.toggle('hidden', !on);
      if (on) requestDoorAdminList();
    });
  });

  window.addEventListener('message', (e) => {
    const d = e.data || {};
    if (d.action === 'open') {
      const level = Number(d.me?.effectiveLevel || 0);
      tab.classList.toggle('hidden', level < 3);
      pane.classList.add('hidden');
      modal.classList.add('hidden');
      document.body.classList.remove('ck-door-capturing');
    } else if (d.action === 'close') {
      pane.classList.add('hidden');
      modal.classList.add('hidden');
      document.body.classList.remove('ck-door-capturing');
    } else if (d.action === 'doorAdminData') {
      rows = Array.isArray(d.rows) ? d.rows : [];
      permissionOptions = Array.isArray(d.permissions) ? d.permissions : permissionOptions;
      renderDoorAdminList(d);
    } else if (d.action === 'doorCaptureFocus') {
      document.body.classList.toggle('ck-door-capturing', d.active === true);
    } else if (d.action === 'doorCaptureResult') {
      document.body.classList.remove('ck-door-capturing');
      openCreateModal(d.leaves || []);
    }
  });
})();
