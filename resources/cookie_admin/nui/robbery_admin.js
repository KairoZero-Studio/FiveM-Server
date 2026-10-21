(() => {
  let DATA = null;
  let SELECTED = null;
  let DRAFT = null;

  const $ = (id) => document.getElementById(id);
  const post = (name, body) => fetch(`https://cookie_admin/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body || {})
  }).then(r => r.json()).catch(() => null);

  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, c => ({
    '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'
  }[c]));

  const n = (v, fallback=0) => {
    const x = Number(v);
    return Number.isFinite(x) ? x : fallback;
  };

  function defaults() {
    return Object.assign({
      id: null,
      type: 'convenience',
      label: '소형 RP',
      x: 0, y: 0, z: 0, heading: 0,
      interactDistance: 2.5,
      crewRadius: 12,
      combatRadius: 45,
      failRadius: 55,
      threatSeconds: 8,
      responseWaitSeconds: 90,
      lootSeconds: 30,
      cooldownSeconds: 600,
      cashMin: 2500000,
      cashMax: 3500000,
      requiredLootAmount: 0,
      minCrew: 1,
      dispatchText: '강도 연락 · 통무방으로 이동 후 현장 대응 바랍니다.',
      enabled: true,
      rewards: [],
      bankLootPoints: [],
      requirements: [],
      boundaryMode: 'circle',
      boundaryPoints: []
    }, DATA?.defaults || {});
  }

  function clone(v) {
    return JSON.parse(JSON.stringify(v));
  }

  function selectedFromData() {
    if (!DATA || !Array.isArray(DATA.locations)) return null;
    return DATA.locations.find(x => Number(x.id) === Number(SELECTED)) || null;
  }

  function select(id) {
    SELECTED = id;
    const row = selectedFromData();
    DRAFT = row ? clone(row) : defaults();
    render();
  }

  function rewardRow(row={}) {
    return `
      <div class="ck-rob-reward-row" data-reward-row>
        <input class="ck-rob-r-item" value="${esc(row.item || '')}" placeholder="아이템명 예: goldbar">
        <input class="ck-rob-r-label" value="${esc(row.label || '')}" placeholder="표시명 예: 금괴">
        <label><span>최소</span><input class="ck-rob-r-min" type="number" min="1" value="${n(row.min,1)}"></label>
        <label><span>최대</span><input class="ck-rob-r-max" type="number" min="1" value="${n(row.max,1)}"></label>
        <label><span>확률 %</span><input class="ck-rob-r-chance" type="number" min="0" max="100" step="0.1" value="${n(row.chance,100)}"></label>
        <button class="ck-rob-r-del" type="button">×</button>
      </div>`;
  }


  function typeLabel(type) {
    if (type === 'emptyhouse') return '빈집';
    if (type === 'bank') return '대형 RP';
    return '소형 RP';
  }

  function factionLabel(f) {
    const names = {
      police:'경찰',
      security:'보안',
      corrections:'교정',
      fire:'소방',
      private:'사설팩션',
      crime:'범죄조직',
      civil:'시민직'
    };
    return `[${names[String(f?.type||'')] || String(f?.type||'팩션')}] ${f?.name || `#${f?.id||'?'}`}`;
  }

  function boundaryPointRow(point={},index=0) {
    return `
      <div class="ck-rob-boundary-point" data-boundary-point>
        <strong class="ck-rob-point-index">${index+1}</strong>
        <label><span>X</span><input class="ck-rob-point-x" type="number" step="0.001" value="${n(point.x,0)}"></label>
        <label><span>Y</span><input class="ck-rob-point-y" type="number" step="0.001" value="${n(point.y,0)}"></label>
        <label><span>Z</span><input class="ck-rob-point-z" type="number" step="0.001" value="${n(point.z,0)}"></label>
        <button class="ck-rob-point-up" type="button">↑</button>
        <button class="ck-rob-point-down" type="button">↓</button>
        <button class="ck-rob-point-del" type="button">×</button>
      </div>`;
  }

  function renumberBoundaryPoints() {
    document.querySelectorAll('[data-boundary-point]').forEach((row,index)=>{
      const badge=row.querySelector('.ck-rob-point-index');
      if(badge) badge.textContent=String(index+1);
    });
  }

  function bindBoundaryPoints() {
    document.querySelectorAll('[data-boundary-point]').forEach(row=>{
      row.querySelector('.ck-rob-point-del')?.addEventListener('click',()=>{row.remove();renumberBoundaryPoints();});
      row.querySelector('.ck-rob-point-up')?.addEventListener('click',()=>{const p=row.previousElementSibling;if(p)row.parentElement.insertBefore(row,p);renumberBoundaryPoints();});
      row.querySelector('.ck-rob-point-down')?.addEventListener('click',()=>{const n=row.nextElementSibling;if(n)row.parentElement.insertBefore(n,row);renumberBoundaryPoints();});
    });
  }

  function updateBoundaryModeUI() {
    const polygon=field('robBoundaryMode')==='polygon';
    $('robCircleBoundary')?.classList.toggle('hidden',polygon);
    $('robPolygonBoundary')?.classList.toggle('hidden',!polygon);
  }

  function requirementRow(row={}) {
    const factions = Array.isArray(DATA?.factions) ? DATA.factions : [];
    const selected = Number(row.factionId || 0);

    return `
      <div class="ck-rob-requirement-row" data-requirement-row>
        <div class="ck-rob-req-main">
          <span class="ck-rob-req-label">대응 팩션</span>
          <select class="ck-rob-req-faction">
            <option value="">팩션 선택</option>
            ${factions.map(f => `<option value="${Number(f.id)}" ${Number(f.id)===selected?'selected':''}>${esc(factionLabel(f))}</option>`).join('')}
          </select>
        </div>
        <div class="ck-rob-req-count-wrap">
          <span class="ck-rob-req-label">최소 출근</span>
          <div class="ck-rob-req-count-box">
            <input class="ck-rob-req-count" type="number" min="1" max="100" value="${Math.max(1,Math.floor(n(row.minDuty,1)))}">
            <b>명</b>
          </div>
        </div>
        <button class="ck-rob-req-del" type="button" title="삭제">×</button>
      </div>`;
  }

  function bindRequirementRows() {
    document.querySelectorAll('[data-requirement-row]').forEach(row => {
      row.querySelector('.ck-rob-req-del')?.addEventListener('click', () => row.remove());
    });
  }

  function bankPointRow(row={}) {
    return `
      <div class="ck-bank-point-row" data-bank-point-row>
        <div class="ck-bank-point-main">
          <input class="ck-bank-p-label" value="${esc(row.label || '')}" placeholder="비콘 이름 예: 중앙 금고">
          <input class="ck-bank-p-item" value="${esc(row.item || '')}" placeholder="아이템명 예: bank_cash_bundle">
          <input class="ck-bank-p-itemlabel" value="${esc(row.itemLabel || '')}" placeholder="표시명 예: 현금 다발">
        </div>
        <div class="ck-bank-point-coords">
          <input class="ck-bank-p-x" type="number" step="0.001" value="${n(row.x,0).toFixed(3)}" placeholder="X">
          <input class="ck-bank-p-y" type="number" step="0.001" value="${n(row.y,0).toFixed(3)}" placeholder="Y">
          <input class="ck-bank-p-z" type="number" step="0.001" value="${n(row.z,0).toFixed(3)}" placeholder="Z">
          <button class="ck-bank-p-capture" type="button">현재 위치</button>
        </div>
        <div class="ck-bank-point-settings">
          <label><span>최소</span><input class="ck-bank-p-min" type="number" min="1" value="${n(row.min,1)}"></label>
          <label><span>최대</span><input class="ck-bank-p-max" type="number" min="1" value="${n(row.max,1)}"></label>
          <label><span>회수시간</span><input class="ck-bank-p-seconds" type="number" min="1" max="180" value="${n(row.lootSeconds,10)}"><small>초</small></label>
          <button class="ck-bank-p-del" type="button">비콘 삭제</button>
        </div>
      </div>`;
  }

  function bindBankPointRows() {
    document.querySelectorAll('[data-bank-point-row]').forEach(row => {
      row.querySelector('.ck-bank-p-del')?.addEventListener('click', () => row.remove());
      row.querySelector('.ck-bank-p-capture')?.addEventListener('click', async () => {
        const d = await post('captureRobberyCoords', {});
        if (!d?.ok) return;
        row.querySelector('.ck-bank-p-x').value = n(d.x).toFixed(3);
        row.querySelector('.ck-bank-p-y').value = n(d.y).toFixed(3);
        row.querySelector('.ck-bank-p-z').value = n(d.z).toFixed(3);
      });
    });
  }

  function bindRewardRows() {
    document.querySelectorAll('[data-reward-row]').forEach(row => {
      row.querySelector('.ck-rob-r-del')?.addEventListener('click', () => row.remove());
    });
  }

  function field(id) {
    return $(id)?.value ?? '';
  }

  function collect() {
    return {
      id: DRAFT?.id || null,
      type: field('robType') || 'convenience',
      label: field('robLabel').trim(),
      x: n(field('robX')),
      y: n(field('robY')),
      z: n(field('robZ')),
      heading: n(field('robHeading')),
      interactDistance: n(field('robInteract'), 2.5),
      crewRadius: n(field('robCrewRadius'), 12),
      combatRadius: n(field('robCombatRadius'), 45),
      failRadius: n(field('robFailRadius'), 55),
      boundaryMode: field('robBoundaryMode') === 'polygon' ? 'polygon' : 'circle',
      boundaryPoints: [...document.querySelectorAll('[data-boundary-point]')].map(row=>({
        x:n(row.querySelector('.ck-rob-point-x')?.value),
        y:n(row.querySelector('.ck-rob-point-y')?.value),
        z:n(row.querySelector('.ck-rob-point-z')?.value)
      })),
      threatSeconds: Math.floor(n(field('robThreat'), 8)),
      responseWaitSeconds: Math.floor(n(field('robResponse'), 90)),
      lootSeconds: Math.floor(n(field('robLoot'), 30)),
      cooldownSeconds: Math.max(60, Math.floor(n(field('robCooldownMin'), 10) * 60)),
      cashMin: Math.floor(n(field('robCashMin'), 0)),
      cashMax: Math.floor(n(field('robCashMax'), 0)),
      requiredLootAmount: Math.floor(n(field('robBankRequiredLoot'), 0)),
      minCrew: Math.floor(n(field('robBankMinCrew'), 1)),
      dispatchText: field('robDispatch').trim(),
      enabled: !!$('robEnabled')?.checked,
      requirements: [...document.querySelectorAll('[data-requirement-row]')].map(row => ({
        factionId: Number(row.querySelector('.ck-rob-req-faction')?.value || 0),
        minDuty: Math.max(1, Math.floor(n(row.querySelector('.ck-rob-req-count')?.value, 1)))
      })).filter(x => x.factionId > 0),
      bankLootPoints: [...document.querySelectorAll('[data-bank-point-row]')].map(row => ({
        label: row.querySelector('.ck-bank-p-label')?.value.trim() || '',
        x: n(row.querySelector('.ck-bank-p-x')?.value),
        y: n(row.querySelector('.ck-bank-p-y')?.value),
        z: n(row.querySelector('.ck-bank-p-z')?.value),
        item: row.querySelector('.ck-bank-p-item')?.value.trim() || '',
        itemLabel: row.querySelector('.ck-bank-p-itemlabel')?.value.trim() || '',
        min: Math.max(1, Math.floor(n(row.querySelector('.ck-bank-p-min')?.value, 1))),
        max: Math.max(1, Math.floor(n(row.querySelector('.ck-bank-p-max')?.value, 1))),
        lootSeconds: Math.max(1, Math.floor(n(row.querySelector('.ck-bank-p-seconds')?.value, 10)))
      })).filter(x => x.item),
      rewards: [...document.querySelectorAll('[data-reward-row]')].map(row => ({
        item: row.querySelector('.ck-rob-r-item')?.value.trim() || '',
        label: row.querySelector('.ck-rob-r-label')?.value.trim() || '',
        min: Math.max(1, Math.floor(n(row.querySelector('.ck-rob-r-min')?.value, 1))),
        max: Math.max(1, Math.floor(n(row.querySelector('.ck-rob-r-max')?.value, 1))),
        chance: Math.max(0, Math.min(100, n(row.querySelector('.ck-rob-r-chance')?.value, 100))),
        enabled: true
      })).filter(x => x.item)
    };
  }

  function render() {
    const body = $('robberyAdminBody');
    if (!body) return;

    if (!DATA) {
      body.innerHTML = '<div class="ck-skin-empty">설정을 불러오는 중…</div>';
      return;
    }

    if (!DRAFT) {
      if (DATA.locations?.length) {
        SELECTED = DATA.locations[0].id;
        DRAFT = clone(DATA.locations[0]);
      } else {
        SELECTED = null;
        DRAFT = defaults();
      }
    }

    const locations = DATA.locations || [];

    body.innerHTML = `
      <div class="ck-robbery-layout">
        <aside class="ck-robbery-list">
          <div class="ck-robbery-list-title">등록된 강도 장소 <b>${locations.length}</b></div>
          <div class="ck-robbery-list-scroll">
            ${locations.length ? locations.map(x => `
              <button class="ck-robbery-loc ${Number(x.id)===Number(SELECTED)?'active':''}" data-rob-id="${x.id}" type="button">
                <span>${x.enabled ? '●' : '○'}</span>
                <div><b>${esc(x.label)}</b><small>${esc(typeLabel(x.type))} · 쿨타임 ${Math.round(n(x.cooldownSeconds,600)/60)}분</small></div>
              </button>`).join('') :
              '<div class="ck-robbery-empty">아직 등록된 강도 장소가 없습니다.<br>위의 + 강도 장소 추가를 눌러주세요.</div>'}
          </div>
        </aside>

        <main class="ck-robbery-editor">
          <div class="ck-robbery-editor-top">
            <div><b>${DRAFT.id ? 'RP 장소 수정' : '새 RP 장소'}</b><small>RP 종류별 전투·침입·대응 설정</small></div>
            <label class="ck-robbery-enabled"><input id="robEnabled" type="checkbox" ${DRAFT.enabled!==false?'checked':''}><span>활성화</span></label>
          </div>

          <div class="ck-robbery-grid cols2">
            <label><span>종류</span><select id="robType">
              <option value="convenience" ${(DRAFT.type||'convenience')==='convenience'?'selected':''}>소형 RP</option>
              <option value="emptyhouse" ${(DRAFT.type||'')==='emptyhouse'?'selected':''}>빈집 · 근접무기 전용</option>
              <option value="bank" ${(DRAFT.type||'')==='bank'?'selected':''}>대형 RP</option>
            </select></label>
            <label><span>장소 이름</span><input id="robLabel" maxlength="80" value="${esc(DRAFT.label||'')}" placeholder="예: 바인우드 24/7"></label>
          </div>

          <div id="robTypeHint" class="ck-robbery-type-hint"></div>

          <div class="ck-robbery-section">
            <div class="ck-robbery-section-head"><b>📍 RP 시작 비콘 위치</b><button id="robCapture" type="button">현재 위치 적용</button></div>
            <div class="ck-robbery-grid cols4">
              <label><span>X</span><input id="robX" type="number" step="0.001" value="${n(DRAFT.x).toFixed(3)}"></label>
              <label><span>Y</span><input id="robY" type="number" step="0.001" value="${n(DRAFT.y).toFixed(3)}"></label>
              <label><span>Z</span><input id="robZ" type="number" step="0.001" value="${n(DRAFT.z).toFixed(3)}"></label>
              <label><span>Heading</span><input id="robHeading" type="number" step="0.1" value="${n(DRAFT.heading).toFixed(1)}"></label>
            </div>
          </div>

          <div class="ck-robbery-section ck-rob-requirement-section">
            <div class="ck-robbery-section-head">
              <div>
                <b>👥 RP 시작 필수 출근 팩션</b>
                <small>선택한 팩션별 최소 출근 인원을 모두 충족해야 시작</small>
              </div>
              <button id="robAddRequirement" class="ck-rob-add-requirement" type="button">+ 조건 추가</button>
            </div>
            <div id="robRequirementRows" class="ck-rob-requirement-list">${(DRAFT.requirements||[]).map(requirementRow).join('')}</div>
            <div class="ck-robbery-tip">조건을 비워두면 기존 장소 보호용으로 경찰/보안국 합산 1명 조건이 적용됩니다.</div>
          </div>

          <div class="ck-robbery-section">
            <div class="ck-robbery-section-head"><b>⚔️ 전멸전 설정</b><small>강도팀 전멸 = 실패 / 경찰이 점원 비콘에서 승·패 직접 확정</small></div>
            <div class="ck-robbery-grid cols4">
              <label><span>상호작용 거리</span><input id="robInteract" type="number" min="1" max="6" step="0.1" value="${n(DRAFT.interactDistance,2.5)}"><small>m</small></label>
              <label><span>공범 자동 편입</span><input id="robCrewRadius" type="number" min="3" max="30" step="1" value="${n(DRAFT.crewRadius,12)}"><small>m</small></label>
              <label><span>범위 모양</span><select id="robBoundaryMode">
                <option value="circle" ${(DRAFT.boundaryMode||'circle')==='circle'?'selected':''}>원형</option>
                <option value="polygon" ${(DRAFT.boundaryMode||'circle')==='polygon'?'selected':''}>다각형</option>
              </select></label>
              <label><span>강도팀 이탈 실패 반경</span><input id="robFailRadius" type="number" min="15" max="160" step="1" value="${n(DRAFT.failRadius,55)}"><small>m</small></label>
            </div>

            <div id="robCircleBoundary" class="ck-rob-boundary-mode-panel">
              <div class="ck-robbery-grid cols2">
                <label><span>교전 반경</span><input id="robCombatRadius" type="number" min="15" max="120" step="1" value="${n(DRAFT.combatRadius,45)}"><small>m</small></label>
                <div class="ck-rob-boundary-note">원형은 RP 시작 비콘을 중심으로 반경을 지정합니다.</div>
              </div>
            </div>

            <div id="robPolygonBoundary" class="ck-rob-boundary-mode-panel hidden">
              <div class="ck-rob-polygon-head">
                <div><b>다각형 꼭짓점</b><small>원하는 모서리로 이동한 뒤 현재 위치를 추가하세요.</small></div>
                <div class="ck-rob-polygon-buttons">
                  <button id="robWorldBoundaryCapture" type="button">◎ 월드에서 꼭짓점 찍기</button>
                  <button id="robAddBoundaryPoint" type="button">+ 현재 위치</button>
                  <button id="robClearBoundaryPoints" type="button">전체 삭제</button>
                </div>
              </div>
              <div id="robBoundaryPoints" class="ck-rob-boundary-points">${(DRAFT.boundaryPoints||[]).map((p,i)=>boundaryPointRow(p,i)).join('')}</div>
              <div class="ck-robbery-tip">최소 <b>3개</b>. 입력 순서대로 빨간 벽이 연결되고 마지막 점은 첫 점과 자동 연결됩니다.</div>
            </div>

            <div class="ck-robbery-grid cols4">
              <label><span>점원 위협</span><input id="robThreat" type="number" min="1" max="60" value="${n(DRAFT.threatSeconds,8)}"><small>초</small></label>
              <label><span>결과 미입력 자동 해제</span><input id="robResponse" type="number" min="10" max="900" value="${n(DRAFT.responseWaitSeconds,90)}"><small>초</small></label>
              <label><span>전리품 회수</span><input id="robLoot" type="number" min="1" max="180" value="${n(DRAFT.lootSeconds,30)}"><small>초</small></label>
              <label><span>장소 쿨타임</span><input id="robCooldownMin" type="number" min="1" max="1440" value="${Math.round(n(DRAFT.cooldownSeconds,600)/60)}"><small>분</small></label>
            </div>
          </div>

          <div id="robBankSection" class="ck-robbery-section ${DRAFT.type==='bank'?'':'hidden'}">
            <div class="ck-robbery-section-head">
              <b>🔴 대형 RP 설정</b>
              <small>전리품 요구 수량을 먼저 채운 뒤 최종 전멸전에서 승리해야 성공</small>
            </div>
            <div class="ck-robbery-grid cols2">
              <label><span>최소 강도팀 인원</span><input id="robBankMinCrew" type="number" min="1" max="20" value="${n(DRAFT.minCrew,1)}"><small>명</small></label>
              <label><span>필수 전리품 수량</span><input id="robBankRequiredLoot" type="number" min="1" max="100000" value="${n(DRAFT.requiredLootAmount,0)}"><small>개</small></label>
            </div>

            <div class="ck-robbery-section-head ck-bank-subhead">
              <div><b>대형 RP 털이 비콘</b><small>각 비콘에서 확보한 수량의 합이 필수 수량에 도달해야 최종전 진입</small></div>
              <button id="robAddBankPoint" type="button">+ 털이 비콘 추가</button>
            </div>
            <div id="robBankPointRows">${(DRAFT.bankLootPoints||[]).map(bankPointRow).join('')}</div>
            <div class="ck-robbery-tip">
              전리품은 전멸전 승리 전까지 <b>서버 임시 보관</b>됩니다. 경찰 승리 시 지급되지 않습니다.
            </div>
          </div>

          <div class="ck-robbery-section">
            <div class="ck-robbery-section-head"><b>💵 현금 전리품</b><small>강도 성공 시 현금(cash)으로 랜덤 지급</small></div>
            <div class="ck-robbery-grid cols2">
              <label><span>최소 현금</span><input id="robCashMin" type="number" min="0" step="10000" value="${Math.floor(n(DRAFT.cashMin,2500000))}"></label>
              <label><span>최대 현금</span><input id="robCashMax" type="number" min="0" step="10000" value="${Math.floor(n(DRAFT.cashMax,3500000))}"></label>
            </div>
          </div>

          <div class="ck-robbery-section">
            <div class="ck-robbery-section-head"><b>📦 털 수 있는 물품</b><button id="robAddReward" type="button">+ 물품 추가</button></div>
            <div class="ck-robbery-reward-head"><span>아이템명</span><span>표시명</span><span>최소</span><span>최대</span><span>확률</span><span></span></div>
            <div id="robRewardRows">${(DRAFT.rewards||[]).map(rewardRow).join('')}</div>
            <div class="ck-robbery-tip">예: <b>goldbar / 금괴 / 1~2개 / 20%</b>. 성공 시 각 물품마다 확률을 따로 굴립니다.</div>
          </div>

          <div class="ck-robbery-section">
            <div class="ck-robbery-section-head"><b>🚨 경찰 신고</b><small>근무 중 경찰/보안국에게 연락만 전송 · 수락/접수 기능 없음</small></div>
            <textarea id="robDispatch" maxlength="180" placeholder="신고 문구">${esc(DRAFT.dispatchText||'')}</textarea>
            <div class="ck-robbery-tip">권장 문구: <b>강도 연락 · 통무방으로 이동 후 현장 대응 바랍니다.</b></div>
          </div>

          <div class="ck-robbery-actions">
            ${DRAFT.id ? '<button id="robDelete" class="danger" type="button">장소 삭제</button>' : '<span></span>'}
            <button id="robSave" class="primary" type="button">RP 설정 저장</button>
          </div>
        </main>
      </div>`;

    document.querySelectorAll('[data-rob-id]').forEach(btn => {
      btn.addEventListener('click', () => select(Number(btn.dataset.robId)));
    });

    bindRewardRows();
    bindBankPointRows();
    bindRequirementRows();
    bindBoundaryPoints();
    updateBoundaryModeUI();

    $('robBoundaryMode')?.addEventListener('change',updateBoundaryModeUI);

    $('robWorldBoundaryCapture')?.addEventListener('click',async()=>{
      const points=[...document.querySelectorAll('[data-boundary-point]')].map(row=>({
        x:n(row.querySelector('.ck-rob-point-x')?.value),
        y:n(row.querySelector('.ck-rob-point-y')?.value),
        z:n(row.querySelector('.ck-rob-point-z')?.value)
      }));
      const result=await post('startRobberyBoundaryCapture',{points});
      if(!result?.ok) showToast(result?.message||'월드 범위 편집을 시작하지 못했습니다.',true);
    });

    $('robAddBoundaryPoint')?.addEventListener('click',async()=>{
      const d=await post('captureRobberyCoords',{});
      if(!d?.ok)return showToast('현재 위치를 가져오지 못했습니다.',true);
      const wrap=$('robBoundaryPoints');
      if(!wrap)return;
      const index=wrap.querySelectorAll('[data-boundary-point]').length;
      const tmp=document.createElement('div');
      tmp.innerHTML=boundaryPointRow({x:n(d.x),y:n(d.y),z:n(d.z)},index);
      wrap.appendChild(tmp.firstElementChild);
      bindBoundaryPoints();
      renumberBoundaryPoints();
      showToast(`꼭짓점 ${index+1} 추가 완료`,false);
    });

    $('robClearBoundaryPoints')?.addEventListener('click',()=>{
      const wrap=$('robBoundaryPoints');
      if(wrap)wrap.innerHTML='';
      showToast('다각형 꼭짓점을 모두 삭제했습니다.',false);
    });

    $('robAddRequirement')?.addEventListener('click', () => {
      const wrap = $('robRequirementRows');
      if (!wrap) return;

      const tmp = document.createElement('div');
      tmp.innerHTML = requirementRow({minDuty:1});
      wrap.appendChild(tmp.firstElementChild);
      bindRequirementRows();
    });

    $('robAddBankPoint')?.addEventListener('click', async () => {
      const wrap = $('robBankPointRows');
      if (!wrap) return;

      const d = await post('captureRobberyCoords', {});
      const row = {
        label: `전리품 비콘 ${(wrap.querySelectorAll('[data-bank-point-row]').length || 0) + 1}`,
        x: d?.ok ? n(d.x) : 0,
        y: d?.ok ? n(d.y) : 0,
        z: d?.ok ? n(d.z) : 0,
        min: 1,
        max: 1,
        lootSeconds: 10
      };

      const tmp = document.createElement('div');
      tmp.innerHTML = bankPointRow(row);
      wrap.appendChild(tmp.firstElementChild);
      bindBankPointRows();
    });

    const typeSelect = $('robType');
    const typeHint = $('robTypeHint');
    const updateTypeHint = () => {
      if (!typeHint || !typeSelect) return;
      if (typeSelect.value === 'emptyhouse') {
        typeHint.innerHTML = '<b>🏚 빈집</b> 근접무기만 사용 가능 · 총기를 들고 있으면 시작 불가';
      } else if (typeSelect.value === 'bank') {
        typeHint.innerHTML = '<b>🔴 대형 RP</b> 여러 털이 비콘에서 필수 전리품 수량 확보 → 최종 전멸전 승리';
      } else {
        typeHint.innerHTML = '<b>🔴 소형 RP</b> 총기 필수 · 등록된 RP 범위는 평소에도 반투명 빨간 벽으로 표시';
      }

      const bankSection = $('robBankSection');
      bankSection?.classList.toggle('hidden', typeSelect.value !== 'bank');
    };
    typeSelect?.addEventListener('change', updateTypeHint);
    updateTypeHint();

    $('robAddReward')?.addEventListener('click', () => {
      const wrap = $('robRewardRows');
      if (!wrap) return;
      const tmp = document.createElement('div');
      tmp.innerHTML = rewardRow({min:1,max:1,chance:100});
      wrap.appendChild(tmp.firstElementChild);
      bindRewardRows();
    });

    $('robCapture')?.addEventListener('click', async () => {
      const d = await post('captureRobberyCoords', {});
      if (!d?.ok) return;
      $('robX').value = n(d.x).toFixed(3);
      $('robY').value = n(d.y).toFixed(3);
      $('robZ').value = n(d.z).toFixed(3);
      $('robHeading').value = n(d.heading).toFixed(1);
    });

    $('robSave')?.addEventListener('click', async () => {
      const btn = $('robSave');
      if (btn) { btn.disabled = true; btn.textContent = '저장 중…'; }
      await post('saveRobberyLocation', collect());
    });

    $('robDelete')?.addEventListener('click', async () => {
      if (!DRAFT?.id) return;
      if (!confirm(`"${DRAFT.label}" RP 장소를 삭제할까요?`)) return;
      await post('deleteRobberyLocation', {id:DRAFT.id});
    });
  }

  function load() {
    DATA = null;
    SELECTED = null;
    DRAFT = null;
    render();
    post('requestRobberyAdmin', {});
  }

  document.querySelectorAll('.ck-system-menu-btn[data-system="robbery"]').forEach(btn => {
    btn.addEventListener('click', () => setTimeout(load, 0));
  });

  $('robberyAddLocation')?.addEventListener('click', async () => {
    SELECTED = null;
    DRAFT = defaults();

    const d = await post('captureRobberyCoords', {});
    if (d?.ok) {
      DRAFT.x = n(d.x);
      DRAFT.y = n(d.y);
      DRAFT.z = n(d.z);
      DRAFT.heading = n(d.heading);
    }
    render();
  });

  window.addEventListener('message', e => {
    const d = e.data || {};
    if (d.action === 'robberyAdminData') {
      DATA = d.data || {locations:[],defaults:{}};

      if (SELECTED) {
        const found = (DATA.locations||[]).find(x => Number(x.id)===Number(SELECTED));
        DRAFT = found ? clone(found) : null;
      }
      if (!DRAFT && DATA.locations?.length) {
        SELECTED = DATA.locations[0].id;
        DRAFT = clone(DATA.locations[0]);
      }
      if (!DRAFT) DRAFT = defaults();
      render();
    }

    if (d.action === 'robberyBoundaryCaptureStart') {
      document.documentElement.classList.add('ck-boundary-world-mode');
    }

    if (d.action === 'robberyBoundaryCaptureFinish') {
      document.documentElement.classList.remove('ck-boundary-world-mode');

      if (!d.cancelled) {
        const wrap = $('robBoundaryPoints');
        if (wrap) {
          const points = Array.isArray(d.points) ? d.points : [];
          wrap.innerHTML = points.map((p,i)=>boundaryPointRow(p,i)).join('');
          bindBoundaryPoints();
          renumberBoundaryPoints();
          showToast(`다각형 꼭짓점 ${points.length}개 적용`, false);
        }
      } else {
        showToast('월드 범위 편집을 취소했습니다.', false);
      }
    }

    if (d.action === 'robberyAdminSaved') {
      if (typeof showToast === 'function') showToast(d.message || '', d.ok !== true);
      else console.log('[robbery admin]', d.message || '');

      const btn = $('robSave');
      if (btn) { btn.disabled = false; btn.textContent = 'RP 설정 저장'; }

      if (d.ok) post('requestRobberyAdmin', {});
    }
  });
})();
