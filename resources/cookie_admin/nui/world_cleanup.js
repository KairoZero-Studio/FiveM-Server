/* COOKIE F3 entity cleanup V2 — use an in-page confirmation modal.
 * NUI/CEF should not rely on window.confirm() or window.prompt().
 */
(() => {
  'use strict';
  const resultEl = document.getElementById('ckCleanupResult');
  const vehicleButton = document.getElementById('ckCleanupVehicles');
  const objectButton = document.getElementById('ckCleanupObjects');
  if (!vehicleButton && !objectButton) return;

  const style = document.createElement('style');
  style.textContent = `
    #ckWorldCleanupConfirm {position:fixed; inset:0; display:none; align-items:center;
      justify-content:center; background:rgba(0,0,0,.62); z-index:2147483000;
      font-family:inherit; color:#2a2a2a;}
    #ckWorldCleanupConfirm.ck-visible {display:flex;}
    #ckWorldCleanupConfirm .ckwc-box {width:min(450px,calc(100vw - 50px));
      background:#fff; border-radius:15px; box-shadow:0 20px 60px rgba(0,0,0,.4);
      padding:24px; box-sizing:border-box;}
    #ckWorldCleanupConfirm h3 {font-size:19px; color:#1b1b1b; margin:0 0 12px; font-weight:750;}
    #ckWorldCleanupConfirm p {font-size:14px; color:#666; line-height:1.65;
      margin:0 0 20px; white-space:pre-line;}
    #ckWorldCleanupConfirm .ckwc-actions {display:flex; justify-content:flex-end; gap:10px;}
    #ckWorldCleanupConfirm button {border-radius:8px; border:1px solid #ddd;
      font-size:14px; font-family:inherit; cursor:pointer; padding:10px 22px;}
    #ckWorldCleanupConfirm .ckwc-cancel {background:#f6f6f6; color:#333;}
    #ckWorldCleanupConfirm .ckwc-delete {background:#d63e35; border-color:#d63e35;
      color:#fff; font-weight:700;}
    #ckWorldCleanupConfirm button:focus-visible {outline:3px solid #e4ab32; outline-offset:2px;}
  `;
  document.head.appendChild(style);

  const modal = document.createElement('div');
  modal.id = 'ckWorldCleanupConfirm';
  modal.setAttribute('role', 'dialog');
  modal.setAttribute('aria-modal', 'true');
  modal.setAttribute('aria-labelledby', 'ckwcTitle');
  modal.setAttribute('aria-describedby', 'ckwcDesc');
  modal.innerHTML = `
    <div class="ckwc-box">
      <h3 id="ckwcTitle">차량을 삭제하시겠습니까?</h3>
      <p id="ckwcDesc">월드에서 빈 차량을 정리합니다.</p>
      <div class="ckwc-actions">
        <button type="button" class="ckwc-cancel" id="ckwcCancel">취소</button>
        <button type="button" class="ckwc-delete" id="ckwcDelete">삭제</button>
      </div>
    </div>
  `;
  document.body.appendChild(modal);
  const title = document.getElementById('ckwcTitle');
  const description = document.getElementById('ckwcDesc');
  const cancel = document.getElementById('ckwcCancel');
  const confirm = document.getElementById('ckwcDelete');

  let mode = null;
  let busy = false;
  let replyTimer = null;
  let previousFocus = null;

  function setStatus(text) { if (resultEl) resultEl.textContent = String(text || ''); }
  function toggleButtons(disabled) {
    if (vehicleButton) vehicleButton.disabled = disabled;
    if (objectButton) objectButton.disabled = disabled;
  }
  function closeModal() {
    modal.classList.remove('ck-visible');
    const previous = previousFocus;
    mode = null;
    previousFocus = null;
    if (previous && typeof previous.focus === 'function') previous.focus();
  }
  function openModal(requestedMode) {
    if (busy) { setStatus('현재 다른 삭제 요청을 처리 중입니다.'); return; }
    mode = requestedMode;
    previousFocus = document.activeElement;
    if (mode === 'vehicles') {
      title.textContent = '차량을 삭제하시겠습니까?';
      description.textContent = '서버 월드에 생성된 탑승자 없는 차량을 삭제합니다.\n차량 소유 DB는 삭제하지 않습니다. 이 작업은 되돌릴 수 없습니다.';
    } else {
      title.textContent = '오브젝트를 삭제하시겠습니까?';
      description.textContent = '서버의 네트워크 오브젝트를 삭제합니다.\n설치형 가구나 작업용 물체도 사라질 수 있습니다. 이 작업은 되돌릴 수 없습니다.';
    }
    modal.classList.add('ck-visible');
    cancel.focus();
  }
  function clearPending() {
    if (replyTimer) { clearTimeout(replyTimer); replyTimer = null; }
    busy = false;
    toggleButtons(false);
  }
  async function execute() {
    if (!mode || busy) return;
    const requestedMode = mode;
    closeModal();
    busy = true;
    toggleButtons(true);
    setStatus('삭제 요청을 서버에 전달하는 중...');
    const phrase = requestedMode === 'vehicles' ? '차량삭제' : '오브젝트삭제';
    try {
      const resource = typeof GetParentResourceName === 'function'
        ? GetParentResourceName() : 'cookie_admin';
      const response = await fetch(`https://${resource}/ckCleanupRequest`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: JSON.stringify({mode: requestedMode, confirm: phrase})
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      if (!data || !data.ok) {
        setStatus(data?.error || '삭제 요청이 거부되었습니다.');
        clearPending();
        return;
      }
      // The server result may arrive before the NUI callback resolves.
      if (!busy) return;
      setStatus('서버에서 차량/오브젝트를 정리하는 중...');
      replyTimer = setTimeout(() => {
        setStatus('처리 결과가 도착하지 않았습니다. 서버 콘솔을 확인해 주세요.');
        clearPending();
      }, 45000);
    } catch (error) {
      setStatus('삭제 요청 연결 실패: 리소스 실행 상태를 확인해 주세요.');
      clearPending();
    }
  }

  vehicleButton?.addEventListener('click', () => openModal('vehicles'));
  objectButton?.addEventListener('click', () => openModal('objects'));
  cancel.addEventListener('click', closeModal);
  confirm.addEventListener('click', execute);
  modal.addEventListener('click', (event) => { if (event.target === modal) closeModal(); });
  document.addEventListener('keydown', (event) => {
    if (!modal.classList.contains('ck-visible')) return;
    if (event.key === 'Escape') {
      event.preventDefault(); event.stopImmediatePropagation(); closeModal();
    } else if (event.key === 'Tab') {
      // Keep focus inside confirmation dialog.
      event.preventDefault();
      (document.activeElement === cancel ? confirm : cancel).focus();
    }
  }, true);
  window.addEventListener('message', (event) => {
    if (event.data?.action !== 'ckCleanupResult') return;
    clearPending();
    setStatus(event.data.message || '정리 작업이 완료되었습니다.');
  });
})();
