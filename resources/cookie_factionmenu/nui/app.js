const root = document.getElementById('root');
const nav = document.getElementById('categoryNav');
const grid = document.getElementById('actionGrid');
const executeBtn = document.getElementById('executeBtn');
const toast = document.getElementById('toast');
const modal = document.getElementById('modal');
const modalBody = document.getElementById('modalBody');
const modalFoot = document.getElementById('modalFoot');

let categories = [];
let profile = null;
let activeCategory = '';
let selectedAction = null;
let toastTimer = null;
let busy = false;

const post = (endpoint, data = {}) => fetch(`https://${GetParentResourceName()}/${endpoint}`, {
  method: 'POST', headers: {'Content-Type':'application/json; charset=UTF-8'}, body: JSON.stringify(data)
}).then(r => r.json()).catch(() => ({ok:false, message:'NUI 통신 오류'}));

function safe(v){return String(v ?? '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));}
function fmt(v){
  if (v === null || v === undefined || v === '') return '-';
  if (typeof v === 'number') return v.toLocaleString('ko-KR');
  return String(v);
}
function showToast(message, error=false){
  toast.textContent = message || '';
  toast.classList.toggle('error', !!error);
  toast.classList.add('show'); clearTimeout(toastTimer);
  toastTimer=setTimeout(()=>toast.classList.remove('show'),2600);
}
function canRun(action){
  if (!action || action.disabled) return false;
  if (profile?.canUse !== true) return false;
  if (action.officerOnly && !(profile?.faction?.isOfficer || profile?.faction?.isLeader)) return false;
  if (action.policeOnly && profile?.faction?.type !== 'police') return false;
  return true;
}
function setProfile(p){
  profile=p||{}; const f=profile.faction||{};
  document.documentElement.style.setProperty('--accent', f.color || '#ffc629');
  document.getElementById('factionType').textContent=f.typeLabel||'팩션';
  document.getElementById('factionName').textContent=f.name||'팩션';
  document.getElementById('rankText').textContent=`${f.rank||'-'} · G${Number(f.grade||0)}`;
  document.getElementById('detailFaction').textContent=f.name||'-';
  document.getElementById('detailRank').textContent=f.rank||'-';
  document.getElementById('detailDuty').textContent=f.duty?'출근':'퇴근';
  const duty=document.getElementById('dutyChip'); duty.textContent=f.duty?'출근':'퇴근'; duty.classList.toggle('on',!!f.duty); duty.classList.toggle('off',!f.duty);
  const state=document.getElementById('actionState'); state.classList.toggle('ready',profile.canUse===true); state.classList.toggle('blocked',profile.canUse!==true); state.querySelector('b').textContent=profile.canUse?'업무 가능':'업무 제한';
  if(selectedAction) setDetail(selectedAction);
}
function renderNav(){
  nav.innerHTML=categories.map((c,i)=>`<button class="nav-btn ${c.id===activeCategory?'active':''}" data-category="${safe(c.id)}" type="button"><span class="nav-index">${String(i+1).padStart(2,'0')}</span><span class="nav-copy"><b>${safe(c.label)}</b><small>${safe(c.subtitle||'')}</small></span><span class="nav-count">${(c.actions||[]).length}</span></button>`).join('');
  nav.querySelectorAll('[data-category]').forEach(b=>b.addEventListener('click',()=>selectCategory(b.dataset.category)));
}
function selectCategory(id){
  const cat=categories.find(c=>c.id===id)||categories[0]; if(!cat)return;
  activeCategory=cat.id; document.getElementById('sectionEyebrow').textContent=cat.id.toUpperCase(); document.getElementById('sectionTitle').textContent=cat.label; document.getElementById('sectionSubtitle').textContent=cat.subtitle||'';
  renderNav(); renderGrid(cat); if((cat.actions||[]).length)setDetail(cat.actions[0]);
}
function renderGrid(cat){
  grid.innerHTML=(cat.actions||[]).map(a=>{
    const allowed=canRun(a);
    const officerLock=a.officerOnly&&!profile?.faction?.isOfficer&&!profile?.faction?.isLeader;
    const policeLock=a.policeOnly&&profile?.faction?.type!=='police';
    const mark=policeLock?'경찰청 전용':(officerLock?'간부 이상':(a.mode==='form'?'입력':'조회'));
    return `<button class="action-card ${selectedAction?.id===a.id?'selected':''} ${!allowed?'disabled':''}" data-action="${safe(a.id)}" type="button"><div class="action-top"><span class="mini-icon ${safe(a.tone||'')}">${safe(a.icon||'•')}</span><span class="quick-mark">${mark}</span></div><h3>${safe(a.label)}</h3><p>${safe(a.desc||'')}</p></button>`;
  }).join('');
  grid.querySelectorAll('[data-action]').forEach(btn=>btn.addEventListener('click',()=>{
    const a=(cat.actions||[]).find(x=>x.id===btn.dataset.action);
    if(!a)return;
    setDetail(a);
    if(canRun(a))runSelected();
  }));
}
function setDetail(action){
  selectedAction=action; document.getElementById('detailIcon').textContent=action.icon||'•'; document.getElementById('detailTitle').textContent=action.label||'기능'; document.getElementById('detailDescription').textContent=action.desc||'';
  const allowed=canRun(action);
  executeBtn.disabled=!allowed;
  executeBtn.textContent=action.disabled?'준비 중':(
    allowed?`${action.label} 열기`:(
      action.policeOnly&&profile?.faction?.type!=='police'
        ? '경찰청 전용 기능'
        : (action.officerOnly?'간부 이상 사용 가능':'출근 후 사용 가능')
    )
  );
  const cat=categories.find(c=>c.id===activeCategory); if(cat)renderGrid(cat);
}
function closeModal(){modal.classList.add('hidden');modalBody.innerHTML='';modalFoot.innerHTML='';}
function fieldHtml(f){
  const req=f.required?' required':'';
  const min=f.min!=null?` min="${Number(f.min)}"`:'';
  const max=f.max!=null?` max="${Number(f.max)}"`:'';
  const val=f.default!=null?` value="${safe(f.default)}"`:'';

  if(f.type==='textarea'){
    return `<label class="field"><span>${safe(f.label)}${f.required?'<em>*</em>':''}</span><textarea data-field="${safe(f.key)}" placeholder="${safe(f.placeholder||'')}"${req}></textarea></label>`;
  }

  if(f.type==='select'||f.type==='factionselect'){
    return `<label class="field"><span>${safe(f.label)}${f.required?'<em>*</em>':''}</span><select data-field="${safe(f.key)}"${req}>${(f.options||[]).map(o=>`<option value="${safe(o.value)}">${safe(o.label)}</option>`).join('')}</select></label>`;
  }

  return `<label class="field"><span>${safe(f.label)}${f.required?'<em>*</em>':''}</span><input data-field="${safe(f.key)}" type="${f.type==='number'?'number':'text'}" placeholder="${safe(f.placeholder||'')}"${min}${max}${val}${req}></label>`;
}
function collectForm(action){
  const payload={}; let bad='';
  (action.fields||[]).forEach(f=>{const el=modalBody.querySelector(`[data-field="${CSS.escape(f.key)}"]`);if(!el)return;let v=el.value;if(f.type==='number'&&v!=='')v=Number(v);if(f.required&&(v===''||v===null||v===undefined))bad=`${f.label} 항목을 입력하세요.`;payload[f.key]=v;});
  return {payload,bad};
}
async function openForm(action){
  document.getElementById('modalEyebrow').textContent='COOKIE MDT · INPUT';
  document.getElementById('modalTitle').textContent=action.label;

  const fields=(action.fields||[]).map(f=>({...f,options:Array.isArray(f.options)?[...f.options]:f.options}));

  if(fields.some(f=>f.type==='factionselect')){
    const optionsResult=await post('runAction',{id:'warrant_targets',payload:{}});
    if(!optionsResult?.ok){
      return showToast(optionsResult?.message||'팩션/조직 목록을 불러오지 못했습니다.',true);
    }
    const options=Array.isArray(optionsResult.options)?optionsResult.options:[];
    if(!options.length){
      return showToast('영장 대상으로 설정 가능한 팩션/조직이 없습니다.',true);
    }
    fields.forEach(f=>{
      if(f.type==='factionselect')f.options=options;
    });
  }

  const formAction={...action,fields};
  modalBody.innerHTML=`<div class="form-grid">${fields.map(fieldHtml).join('')}</div>`;
  modalFoot.innerHTML=`<button class="ghost-btn" id="cancelForm" type="button">취소</button><button class="primary-btn" id="submitForm" type="button">처리</button>`;
  modal.classList.remove('hidden');

  document.getElementById('cancelForm').onclick=closeModal;
  document.getElementById('submitForm').onclick=async()=>{
    if(busy)return;
    const {payload,bad}=collectForm(formAction);
    if(bad)return showToast(bad,true);

    busy=true;
    document.getElementById('submitForm').disabled=true;
    const r=await post('runAction',{id:action.id,payload});
    busy=false;

    if(!r?.ok){
      document.getElementById('submitForm').disabled=false;
      return showToast(r?.message||'처리하지 못했습니다.',true);
    }
    renderResult(action,r);
  };
}
function badge(text,tone=''){return `<span class="result-badge ${safe(tone)}">${safe(text)}</span>`;}
function renderProfile(data){
  const p=data.profile||{};
  const licences=Array.isArray(p.licences)?p.licences:[];
  const dl=p.driverLicense||null;
  const flags=[];

  if(p.wantedCount>0)flags.push(badge(`추격전 ${p.wantedCount}`,'red'));
  if(p.detained)flags.push(badge('구금 중','red'));
  if(dl?.suspended)flags.push(badge('운전면허 정지','red'));

  return `<div class="profile-card">
    <div class="profile-head">
      <div>
        <span>시민 프로필</span>
        <h4>${safe(p.label||`${p.gobun||'-'} / ${p.name||'-'}`)}</h4>
        <p>고번 / 이름 기준 조회</p>
      </div>
      <div class="flag-row">${flags.join('')||badge('특이사항 없음','green')}</div>
    </div>
    <div class="profile-grid">
      <div><span>전화번호</span><b>${safe(p.phone||'-')}</b></div>
      <div><span>주민번호</span><b>${safe(p.jumin||'-')}</b></div>
      <div><span>나이</span><b>${safe(p.age||'-')}</b></div>
      <div><span>성별</span><b>${safe(p.gender||'-')}</b></div>
    </div>
    <div class="license-wrap">
      <span>운전면허</span>
      <div>
        ${dl
          ? badge(`면허번호 ${dl.licenseNo||'-'}`,'blue') +
            badge(dl.suspended ? `정지 · ${Math.max(1,Math.ceil(Number(dl.remainingSeconds||0)/60))}분 남음` : '정상', dl.suspended?'red':'green') +
            (dl.suspended&&dl.reason ? badge(`사유 ${dl.reason}`,'gold') : '')
          : badge('미발급')}
      </div>
    </div>
    <div class="license-wrap">
      <span>기타 면허/자격</span>
      <div>${licences.length?licences.map(x=>badge(x,'blue')).join(''):badge('등록 정보 없음')}</div>
    </div>
    ${renderMiniList('활성 수배/도주 추격전',p.wanted)}
    ${renderMiniList('최근 벌금',p.fines)}
    ${renderMiniList('최근 구금',p.detentions)}
  </div>`;
}
function renderMiniList(title,items){if(!Array.isArray(items)||!items.length)return'';return `<div class="mini-list"><h5>${safe(title)}</h5>${items.slice(0,6).map(x=>`<div><span>${safe(x.left||x.reason||x.charge||'-')}</span><b>${safe(x.right||x.created_at||'')}</b></div>`).join('')}</div>`;}
function renderTable(result){
  const cols=result.columns||[]; const rows=result.rows||[];
  if(!rows.length)return '<div class="empty-result">조회 결과가 없습니다.</div>';
  const actions=(result.rowActions||[]);
  const actionHtml=(row,idx)=>actions.map(a=>{
    if(a.showKey && !row[a.showKey])return '';
    const disabled=a.disableKey && row[a.disableKey];
    return `<button data-result-action="${safe(a.action)}" data-row="${idx}" class="row-btn ${safe(a.tone||'')}" ${disabled?'disabled':''}>${safe((a.labelKey&&row[a.labelKey])||a.label)}</button>`;
  }).join('');
  return `<div class="table-wrap"><table><thead><tr>${cols.map(c=>`<th>${safe(c.label||c.key)}</th>`).join('')}${actions.length?'<th>처리</th>':''}</tr></thead><tbody>${rows.map((row,idx)=>`<tr>${cols.map(c=>`<td>${safe(fmt(row[c.key]))}</td>`).join('')}${actions.length?`<td class="row-actions">${actionHtml(row,idx)}</td>`:''}</tr>`).join('')}</tbody></table></div>`;
}
function renderCalculator(result){
  const rows=Array.isArray(result.offences)?result.offences:[];
  const maxLicense=Number(result.maxLicenseMinutes)||60;
  let lastCategory='';

  const offenceHtml=rows.map(x=>{
    const rawCategory=String(x.category||'기타');
    const categoryHead=lastCategory!==rawCategory
      ? `<div class="calc-category">${safe(rawCategory)}</div>`
      : '';
    lastCategory=rawCategory;

    const fine=Number(x.fine)||0;
    const jail=Number(x.jail)||0;
    const license=Number(x.license)||0;
    const score=Number(x.score)||0;
    const traffic=rawCategory.includes('교통');

    const meta=[
      `${fine.toLocaleString('ko-KR')}원`,
      `구금 ${jail}분`,
      traffic?`면허 ${license}분`:'',
      `범죄 ${score}점`
    ].filter(Boolean).join(' · ');

    const details=[x.description,x.note].filter(Boolean).map(safe).join(' · ');

    return `${categoryHead}<label class="calc-row">
      <input type="checkbox"
        data-penalty="${safe(x.id)}"
        data-fine="${fine}"
        data-jail="${jail}"
        data-license="${license}"
        data-score="${score}">
      <span>
        <b>${safe(x.label)}</b>
        <small>${details||safe(rawCategory)}</small>
      </span>
      <em>${meta}</em>
    </label>`;
  }).join('');

  return `<div class="calc-box">
    <div class="calc-target">
      <label class="field">
        <span>부과 대상 고번 / 이름</span>
        <input id="calcTarget" type="text" placeholder="예: 17 또는 김민수">
      </label>
    </div>
    <div class="calc-offences">${offenceHtml}</div>
    <div class="calc-total">
      <div><span>총 벌금</span><b id="calcFine">0원</b></div>
      <div><span>총 구금</span><b id="calcJail">0분</b></div>
      <div><span>운전면허 정지</span><b id="calcLicense">0분</b></div>
      <div><span>범죄점수</span><b id="calcCrimeScore">0점</b></div>
      <div><span>보석금 환산</span><b id="calcBail">0원</b></div>
    </div>
    <div class="calc-notice">면허정지는 교통범죄만 적용되며 여러 죄목을 선택해도 최대 ${maxLicense}분입니다.</div>
    <div class="calc-actions">
      <button id="calcApply" class="primary-btn" type="button">벌금·구금·면허 처리</button>
    </div>
  </div>`;
}
function wireCalculator(result){
  const bail=Number(result.bailPerMinute)||0;
  const maxLicense=Number(result.maxLicenseMinutes)||60;

  const update=()=>{
    let f=0,j=0,l=0,s=0;
    modalBody.querySelectorAll('[data-penalty]:checked').forEach(x=>{
      f+=Number(x.dataset.fine)||0;
      j+=Number(x.dataset.jail)||0;
      l+=Number(x.dataset.license)||0;
      s+=Number(x.dataset.score)||0;
    });
    l=Math.min(maxLicense,l);

    document.getElementById('calcFine').textContent=f.toLocaleString('ko-KR')+'원';
    document.getElementById('calcJail').textContent=j+'분';
    document.getElementById('calcLicense').textContent=l+'분';
    document.getElementById('calcCrimeScore').textContent=s.toLocaleString('ko-KR')+'점';
    document.getElementById('calcBail').textContent=(j*bail).toLocaleString('ko-KR')+'원';
  };

  modalBody.querySelectorAll('[data-penalty]').forEach(x=>x.addEventListener('change',update));

  document.getElementById('calcApply')?.addEventListener('click',async()=>{
    if(busy)return;
    const target=(document.getElementById('calcTarget')?.value||'').trim();
    const ids=[...modalBody.querySelectorAll('[data-penalty]:checked')].map(x=>x.dataset.penalty);
    if(!target)return showToast('대상 고번/이름을 입력하세요.',true);
    if(!ids.length)return showToast('죄목을 하나 이상 선택하세요.',true);
    busy=true;
    const r=await post('resultAction',{action:'penalty_apply',payload:{target,ids}});
    busy=false;
    if(!r?.ok)return showToast(r?.message||'처리에 실패했습니다.',true);
    showToast(r.message||'처리했습니다.');
    closeModal();
  });
}
function renderSummary(result){
  const metrics=result.metrics||[]; const rows=result.rows||[];
  return `<div class="metrics">${metrics.map(m=>`<div><span>${safe(m.label)}</span><b>${safe(fmt(m.value))}</b></div>`).join('')}</div>${rows.length?renderTable({columns:result.columns||[],rows,rowActions:result.rowActions||[]}):''}`;
}
function openChaseEndReason(result,action,row){
  const reasons=['RP중 디컨','도주자 측 패배','경찰/보안국 측 전멸','상황 종료','오등록','기타'];
  document.getElementById('modalEyebrow').textContent='COOKIE MDT · CHASE END';
  document.getElementById('modalTitle').textContent='도주/수배 종료 사유';
  modalBody.innerHTML=`<div class="form-grid">
    <label class="field"><span>종료 사유</span><select id="chaseEndReason">${reasons.map(x=>`<option value="${safe(x)}">${safe(x)}</option>`).join('')}</select></label>
    <label class="field"><span>기타 사유</span><textarea id="chaseEndCustom" placeholder="기타를 선택한 경우 직접 입력하세요."></textarea></label>
  </div>`;
  modalFoot.innerHTML='<button class="ghost-btn" id="chaseEndBack" type="button">뒤로</button><button class="primary-btn" id="chaseEndSubmit" type="button">추격 종료</button>';
  document.getElementById('chaseEndBack').onclick=()=>renderResult(action,result);
  document.getElementById('chaseEndSubmit').onclick=async()=>{
    if(busy)return;
    const sel=document.getElementById('chaseEndReason').value;
    const custom=(document.getElementById('chaseEndCustom').value||'').trim();
    const endReason=sel==='기타'?custom:sel;
    if(!endReason)return showToast('기타 종료 사유를 입력하세요.',true);
    busy=true;
    const r=await post('resultAction',{action:'wanted_clear',payload:{...row,endReason}});
    busy=false;
    if(!r?.ok)return showToast(r?.message||'종료하지 못했습니다.',true);
    showToast(r.message||'추격전을 종료했습니다.');
    const fresh=await post('runAction',{id:action.id,payload:{}});
    if(fresh?.ok)renderResult(action,fresh);else closeModal();
  };
}
function wireRowActions(result,action){
  modalBody.querySelectorAll('[data-result-action]').forEach(btn=>btn.addEventListener('click',async()=>{
    if(busy||btn.disabled)return;
    const row=(result.rows||[])[Number(btn.dataset.row)]||{};
    if(btn.dataset.resultAction==='wanted_clear')return openChaseEndReason(result,action,row);
    busy=true;btn.disabled=true;
    const r=await post('resultAction',{action:btn.dataset.resultAction,payload:row});
    busy=false;
    if(!r?.ok){btn.disabled=false;return showToast(r?.message||'처리하지 못했습니다.',true);}
    if(r.kind && r.kind!=='success'){renderResult(action,r);return;}
    showToast(r.message||'처리했습니다.');
    const fresh=await post('runAction',{id:action.id,payload:{}});
    if(fresh?.ok)renderResult(action,fresh);else closeModal();
  }));
}
function renderResult(action,result){
  document.getElementById('modalEyebrow').textContent='COOKIE MDT · RESULT'; document.getElementById('modalTitle').textContent=result.title||action.label;
  if(result.kind==='profile')modalBody.innerHTML=renderProfile(result);
  else if(result.kind==='calculator')modalBody.innerHTML=renderCalculator(result);
  else if(result.kind==='summary')modalBody.innerHTML=renderSummary(result);
  else if(result.kind==='table')modalBody.innerHTML=renderTable(result);
  else modalBody.innerHTML=`<div class="success-result"><span>✓</span><h4>${safe(result.title||'처리 완료')}</h4><p>${safe(result.message||'업무 처리가 완료되었습니다.')}</p></div>`;
  modalFoot.innerHTML=`<button class="primary-btn" id="resultClose" type="button">닫기</button>`; document.getElementById('resultClose').onclick=closeModal; modal.classList.remove('hidden'); wireRowActions(result,action); if(result.kind==='calculator')wireCalculator(result); if(result.message)showToast(result.message,false);
}
async function runSelected(){
  const a=selectedAction;if(!canRun(a))return;
  if(a.mode==='form')return openForm(a);
  if(busy)return;busy=true;executeBtn.disabled=true;const r=await post('runAction',{id:a.id,payload:{}});busy=false;executeBtn.disabled=false;if(!r?.ok)return showToast(r?.message||'조회하지 못했습니다.',true);renderResult(a,r);
}
executeBtn.addEventListener('click',runSelected);
document.getElementById('closeBtn').addEventListener('click',()=>post('close'));
document.getElementById('refreshBtn').addEventListener('click',()=>post('refresh'));
document.getElementById('modalClose').addEventListener('click',closeModal);
modal.addEventListener('mousedown',e=>{if(e.target===modal)closeModal();});
document.addEventListener('keydown',e=>{if(e.key==='Escape'){e.preventDefault();if(!modal.classList.contains('hidden'))closeModal();else post('close');}else if(e.key==='F5'){e.preventDefault();post('close');}});
function focusActionById(id){
  for(const cat of categories){
    const a=(cat.actions||[]).find(x=>x.id===id);
    if(a){activeCategory=cat.id;selectCategory(cat.id);setDetail(a);if(canRun(a))setTimeout(()=>runSelected(),20);return true;}
  }
  return false;
}
window.addEventListener('message',e=>{const d=e.data||{};if(d.action==='open'){categories=Array.isArray(d.categories)?d.categories:[];setProfile(d.profile||{});root.classList.remove('hidden');activeCategory=categories[0]?.id||'';selectedAction=null;selectCategory(activeCategory);}if(d.action==='focusAction')focusActionById(String(d.id||''));if(d.action==='close'){closeModal();root.classList.add('hidden');}if(d.action==='profile')setProfile(d.profile||{});});
