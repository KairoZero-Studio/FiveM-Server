let DATA = {}, TAB = 'general', LOCKED = false, SELLING = null;
const app = document.getElementById('app'), loading = document.getElementById('loading'), content = document.getElementById('content'), tabs = document.getElementById('tabs'), body = document.getElementById('body');
function post(n,d){return fetch('https://cookie_garage/'+n,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(d||{})}).catch(()=>{});}
function esc(v){return String(v==null?'':v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function money(v){return Number(v||0).toLocaleString()+'원';}
function pic(src){return src?'<img src="'+src+'" onerror="this.remove()">':'이미지 없음';}
function showLoading(t,x){app.classList.remove('hidden');content.classList.add('hidden');loading.classList.remove('hidden');document.getElementById('loadingTitle').textContent=t||'쿠키 차고';document.getElementById('loadingText').textContent=x||'불러오는 중입니다...';}
function close(){app.classList.add('hidden');loading.classList.add('hidden');content.classList.add('hidden');}
function defs(){if(DATA.mode==='faction')return [['faction',(DATA.faction&&DATA.faction.name?DATA.faction.name:'팩션')+' 차고']];return [['general','일반 차량'],['limited','한정 차량']];}
function renderTabs(){tabs.innerHTML='';defs().forEach(([k,l])=>{const b=document.createElement('button');b.className='tab'+(TAB===k?' active':'');b.textContent=l;b.onclick=()=>{TAB=k;render();};tabs.appendChild(b);});}
function section(title,sub,rows,kind,owned){
 const s=document.createElement('section');s.className='section';s.innerHTML='<div class="section-head"><div><div class="section-title">'+esc(title)+'</div><div class="section-sub">'+esc(sub||'')+'</div></div></div>';
 if(!rows||!rows.length){const e=document.createElement('div');e.className='empty';e.textContent=kind==='limited'?'보유 중인 한정 차량이 없습니다.':kind==='faction'?'현재 출고 가능한 팩션 차량이 없습니다.':'표시할 차량이 없습니다.';s.appendChild(e);return s;}
 const g=document.createElement('div');g.className='grid';
 rows.forEach(v=>{
  const c=document.createElement('article');c.className='card';
  const meta=owned?('번호판 '+esc(v.plate||'-')):esc(v.spec||'');
  const price=owned?'':('<div class="price">'+money(v.price)+'</div>');
  let actions='';
  if(owned&&kind==='general'){
   const canSell=!!v.canSell&&Number(v.sellPrice||0)>0;
   const saleInfo=canSell?'<div class="resale-info"><span>판매 시</span><b>'+money(v.sellPrice)+'</b><small>구매가의 40%</small></div>':'<div class="resale-info disabled"><span>판매</span><b>불가</b><small>가격 정보 없음</small></div>';
   actions=saleInfo+'<div class="owned-actions"><button class="action secondary spawn-btn">출고</button><button class="action danger sell-btn" '+(canSell?'':'disabled')+'>판매</button></div>';
  }else if(owned)actions='<button class="action secondary spawn-btn">출고</button>';
  else if(kind==='general')actions='<button class="action buy-btn">구매</button>';
  const badge=kind==='limited'?'<span class="badge">LIMITED</span>':kind==='faction'?'<span class="badge faction-badge">FACTION</span>':'';
  c.innerHTML='<div class="img">'+pic(v.image)+'</div><div class="card-info"><div class="name">'+esc(v.label||v.model)+'</div><div class="meta">'+meta+'</div><div class="row">'+price+badge+'</div>'+actions+'</div>';
  if(owned){
   const spawn=c.querySelector('.spawn-btn');if(spawn)spawn.onclick=()=>{if(LOCKED)return;LOCKED=true;post('spawnOwned',{id:v.id});};
   if(kind==='general'){const sell=c.querySelector('.sell-btn');if(sell&&!sell.disabled)sell.onclick=()=>{if(LOCKED)return;openSell(v);};}
  }else if(kind==='general'){const buy=c.querySelector('.buy-btn');if(buy)buy.onclick=()=>{if(LOCKED)return;LOCKED=true;buy.disabled=true;buy.textContent='구매 처리 중...';post('buyGeneral',{model:v.model});};}
  g.appendChild(c);
 });
 s.appendChild(g);return s;
}
function renderBody(){
 body.innerHTML='';
 if(DATA.mode==='faction'){body.appendChild(section((DATA.faction&&DATA.faction.name?DATA.faction.name:'팩션')+' 전용 차량','이 차고에는 해당 팩션의 공유 차량만 표시됩니다.',DATA.ownedFaction||[],'faction',true));return;}
 if(TAB==='general'){
  const owned=DATA.ownedGeneral||[];const ownedSet=new Set((DATA.ownedModels||owned.map(v=>v.model)).map(v=>String(v||'').trim().toLowerCase()).filter(Boolean));
  const purch=(DATA.general||[]).filter(v=>!ownedSet.has(String(v.model||'').trim().toLowerCase()));
  body.appendChild(section('내 일반 차량','보유 중인 일반 차량 · 출고하면 바로 운전석에 탑승합니다',owned,'general',true));
  body.appendChild(section('일반 차량 구매','F3 전시 관리 시민차량과 연동',purch,'general',false));
 }else if(TAB==='limited')body.appendChild(section('내 한정 차량','내가 실제로 소유한 한정 차량만 표시됩니다.',DATA.ownedLimited||[],'limited',true));
}
const sellModal=document.getElementById('sellModal'),sellAgree=document.getElementById('sellAgree'),sellConfirm=document.getElementById('sellConfirm');
function closeSell(){SELLING=null;sellAgree.checked=false;sellConfirm.disabled=true;sellModal.classList.add('hidden');}
function openSell(v){SELLING=v;document.getElementById('sellName').textContent=v.label||v.model||'-';document.getElementById('sellPlate').textContent=v.plate||'-';document.getElementById('sellBase').textContent=money(v.buyPrice||0);document.getElementById('sellRefund').textContent=money(v.sellPrice||0);sellAgree.checked=false;sellConfirm.disabled=true;sellModal.classList.remove('hidden');}
sellAgree.addEventListener('change',()=>{sellConfirm.disabled=!sellAgree.checked;});
document.getElementById('sellCancel').onclick=closeSell;
sellConfirm.onclick=()=>{if(!SELLING||!sellAgree.checked||LOCKED)return;LOCKED=true;sellConfirm.disabled=true;sellConfirm.textContent='판매 처리 중...';post('sellGeneral',{id:SELLING.id});};
function render(){if(DATA.mode==='faction')TAB='faction';else if(TAB==='faction')TAB='general';renderTabs();renderBody();}
function openData(d){DATA=d||{};LOCKED=false;if(DATA.mode==='faction')TAB='faction';else if(TAB!=='general'&&TAB!=='limited')TAB='general';const title=document.querySelector('.brand h1');if(title)title.textContent=DATA.title||'쿠키 차고';loading.classList.add('hidden');content.classList.remove('hidden');app.classList.remove('hidden');render();}
window.addEventListener('message',e=>{const d=e.data||{};if(d.action==='loading')showLoading(d.title,d.text);else if(d.action==='open'){closeSell();sellConfirm.textContent='40%에 차량 판매';openData(d.data);}else if(d.action==='close'){closeSell();close();}else if(d.action==='unlock'){LOCKED=false;sellConfirm.textContent='40%에 차량 판매';sellConfirm.disabled=!sellAgree.checked;}else if(d.action==='saleResult'){LOCKED=false;sellConfirm.textContent='40%에 차량 판매';if(d.ok)closeSell();else sellConfirm.disabled=!sellAgree.checked;}});
document.getElementById('close').onclick=()=>{closeSell();close();post('close');};
document.getElementById('refresh').onclick=()=>{showLoading('쿠키 차고','차량 목록을 새로고침하는 중입니다...');post('refresh');};
document.addEventListener('keydown',e=>{if(e.key==='Escape'){if(!sellModal.classList.contains('hidden')){closeSell();return;}if(!app.classList.contains('hidden')){close();post('close');}}});
