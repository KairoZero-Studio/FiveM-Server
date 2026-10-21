const root = document.getElementById('root');
const guideView = document.getElementById('guideView');
const adminView = document.getElementById('adminView');
const tabs = document.getElementById('tabs');
const guideItems = document.getElementById('guideItems');
const adminList = document.getElementById('adminList');
const adminBtn = document.getElementById('adminBtn');
const title = document.getElementById('title');
const subtitle = document.getElementById('subtitle');
const toastEl = document.getElementById('toast');

let guideData = [];
let adminData = [];
let activeKey = null;
let editCategoryId = null;
let editItemId = null;

const res = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cookie_keybinds';
const post = (name, data={}) => fetch(`https://${res}/${name}`, {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)}).catch(()=>{});
const esc = v => String(v ?? '').replace(/[&<>"']/g,s=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[s]));

function openRoot(){ root.classList.remove('hidden'); }
function closeRoot(){ root.classList.add('hidden'); post('close'); }
function showGuide(){
  openRoot(); guideView.classList.remove('hidden'); adminView.classList.add('hidden');
  title.textContent='키 가이드'; subtitle.textContent='현재 역할에서 사용할 수 있는 단축키입니다.';
}
function showAdmin(){
  openRoot(); guideView.classList.add('hidden'); adminView.classList.remove('hidden');
  title.textContent='키 가이드 관리'; subtitle.textContent='버튼 종류, 공개 대상, 단축키를 직접 관리합니다.';
}
function toast(msg, error=false){
  toastEl.textContent=msg; toastEl.classList.toggle('error',!!error); toastEl.classList.remove('hidden');
  clearTimeout(toastEl._t); toastEl._t=setTimeout(()=>toastEl.classList.add('hidden'),2600);
}

function renderGuide(){
  tabs.innerHTML='';
  if(!guideData.length){ guideItems.innerHTML='<div class="empty">현재 볼 수 있는 단축키가 없습니다.</div>'; return; }
  if(!activeKey || !guideData.some(c=>c.key===activeKey)) activeKey=guideData[0].key;
  guideData.forEach(cat=>{
    const b=document.createElement('button'); b.className='tab'+(cat.key===activeKey?' active':'');
    b.innerHTML=`<span>${esc(cat.icon||'⌨')}</span><span>${esc(cat.label)}</span>`;
    b.onclick=()=>{activeKey=cat.key;renderGuide();}; tabs.appendChild(b);
  });
  const cat=guideData.find(c=>c.key===activeKey);
  guideItems.innerHTML=(cat?.items||[]).map(it=>`<div class="key-row"><div><span class="keycap">${esc(it.keyLabel)}</span></div><div class="key-name">${esc(it.label)}</div><div class="key-desc">${esc(it.description||'')}</div></div>`).join('') || '<div class="empty">등록된 단축키가 없습니다.</div>';
}

function visibilityText(cat){
  if(cat.visibility_mode==='all') return '전체 공개';
  if(cat.visibility_mode==='admin') return `관리자 LV${esc(cat.visibility_value||'4')}+`;
  let jobs=[]; try{jobs=JSON.parse(cat.visibility_value||'[]')}catch(e){} return `직업: ${esc(jobs.join(', ')||'-')}`;
}

function fillCategoryEditor(cat){
  editCategoryId=cat?.id||null;
  document.getElementById('catKey').value=cat?.category_key||'';
  document.getElementById('catLabel').value=cat?.label||'';
  document.getElementById('catIcon').value=cat?.icon||'';
  document.getElementById('catSort').value=cat?.sort_order??100;
  document.getElementById('catMode').value=cat?.visibility_mode||'all';
  let value=cat?.visibility_value||''; if(cat?.visibility_mode==='jobs'){try{value=JSON.parse(value).join(',')}catch(e){}}
  document.getElementById('catValue').value=value;
  document.getElementById('catEnabled').value=cat?.enabled===false?'0':'1';
  document.getElementById('categoryEditor').classList.remove('hidden');
}
function fillItemEditor(cat,it){
  editItemId=it?.id||null; refreshCategorySelect(cat?.id||it?.category_id);
  document.getElementById('itemKey').value=it?.item_key||'';
  document.getElementById('itemKeyLabel').value=it?.key_label||'';
  document.getElementById('itemLabel').value=it?.label||'';
  document.getElementById('itemDescription').value=it?.description||'';
  document.getElementById('itemSort').value=it?.sort_order??100;
  document.getElementById('itemEnabled').value=it?.enabled===false?'0':'1';
  document.getElementById('itemEditor').classList.remove('hidden');
}
function refreshCategorySelect(selected){
  const el=document.getElementById('itemCategory'); el.innerHTML=adminData.map(c=>`<option value="${c.id}">${esc(c.icon||'')} ${esc(c.label)}</option>`).join('');
  if(selected) el.value=String(selected);
}

function renderAdmin(){
  refreshCategorySelect();
  adminList.innerHTML=adminData.map(cat=>`<div class="cat-card">
    <div class="cat-head"><div><span class="cat-title">${esc(cat.icon||'⌨')} ${esc(cat.label)}</span><span class="meta">${esc(cat.category_key)} · ${visibilityText(cat)} · ${cat.enabled===false?'숨김':'표시'}</span></div><div class="actions"><button class="btn small" data-cat-edit="${cat.id}">수정</button><button class="btn small danger" data-cat-del="${cat.id}">삭제</button></div></div>
    ${(cat.items||[]).map(it=>`<div class="item-admin-row"><div><span class="keycap">${esc(it.key_label)}</span></div><div class="key-name">${esc(it.label)}</div><div class="key-desc">${esc(it.description||'')} ${it.enabled===false?' · 숨김':''}</div><div class="actions"><button class="btn small" data-item-edit="${it.id}" data-cat-id="${cat.id}">수정</button><button class="btn small danger" data-item-del="${it.id}">삭제</button></div></div>`).join('')}
  </div>`).join('') || '<div class="empty">카테고리가 없습니다.</div>';

  adminList.querySelectorAll('[data-cat-edit]').forEach(b=>b.onclick=()=>fillCategoryEditor(adminData.find(c=>Number(c.id)===Number(b.dataset.catEdit))));
  adminList.querySelectorAll('[data-cat-del]').forEach(b=>b.onclick=()=>{if(confirm('카테고리와 내부 단축키를 모두 삭제할까요?'))post('deleteCategory',{id:Number(b.dataset.catDel)});});
  adminList.querySelectorAll('[data-item-edit]').forEach(b=>b.onclick=()=>{const c=adminData.find(x=>Number(x.id)===Number(b.dataset.catId));const it=c?.items?.find(x=>Number(x.id)===Number(b.dataset.itemEdit));if(it)fillItemEditor(c,it);});
  adminList.querySelectorAll('[data-item-del]').forEach(b=>b.onclick=()=>{if(confirm('이 단축키를 삭제할까요?'))post('deleteItem',{id:Number(b.dataset.itemDel)});});
}

window.addEventListener('message',e=>{
  const d=e.data||{};
  if(d.action==='openGuide'){showGuide();post('refreshGuide');}
  else if(d.action==='openAdmin'){showAdmin();post('refreshAdmin');}
  else if(d.action==='guideData'){guideData=Array.isArray(d.categories)?d.categories:[];adminBtn.classList.toggle('hidden',d.canAdmin!==true);renderGuide();}
  else if(d.action==='adminData'){adminData=Array.isArray(d.categories)?d.categories:[];adminBtn.classList.remove('hidden');showAdmin();renderAdmin();}
  else if(d.action==='toast')toast(d.message||'',d.isError);
  else if(d.action==='close')root.classList.add('hidden');
});

document.getElementById('closeBtn').onclick=closeRoot;
document.getElementById('backBtn').onclick=()=>{showGuide();post('refreshGuide');};
adminBtn.onclick=()=>post('openAdmin');
document.getElementById('newCategoryBtn').onclick=()=>fillCategoryEditor(null);
document.getElementById('newItemBtn').onclick=()=>fillItemEditor(adminData[0],null);
document.getElementById('cancelCategoryBtn').onclick=()=>document.getElementById('categoryEditor').classList.add('hidden');
document.getElementById('cancelItemBtn').onclick=()=>document.getElementById('itemEditor').classList.add('hidden');

document.getElementById('saveCategoryBtn').onclick=()=>{
  post('saveCategory',{id:editCategoryId,categoryKey:document.getElementById('catKey').value.trim(),label:document.getElementById('catLabel').value.trim(),icon:document.getElementById('catIcon').value.trim(),sortOrder:Number(document.getElementById('catSort').value||100),visibilityMode:document.getElementById('catMode').value,visibilityValue:document.getElementById('catValue').value.trim(),enabled:document.getElementById('catEnabled').value==='1'});
  document.getElementById('categoryEditor').classList.add('hidden');
};
document.getElementById('saveItemBtn').onclick=()=>{
  post('saveItem',{id:editItemId,categoryId:Number(document.getElementById('itemCategory').value),itemKey:document.getElementById('itemKey').value.trim(),keyLabel:document.getElementById('itemKeyLabel').value.trim(),label:document.getElementById('itemLabel').value.trim(),description:document.getElementById('itemDescription').value.trim(),sortOrder:Number(document.getElementById('itemSort').value||100),enabled:document.getElementById('itemEnabled').value==='1'});
  document.getElementById('itemEditor').classList.add('hidden');
};

document.addEventListener('keyup',e=>{if(e.key==='Escape'&&!root.classList.contains('hidden'))closeRoot();});
