const app=document.getElementById('app'),content=document.getElementById('content'),title=document.getElementById('title');let data=null,tab='buy';const post=(n,b={})=>fetch(`https://${GetParentResourceName()}/${n}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(b)}).catch(()=>{});const money=v=>Number(v||0).toLocaleString('ko-KR');const itemImg=item=>`https://cfx-nui-ox_inventory/web/images/${encodeURIComponent(item||'')}.png`;function render(){if(!data)return;document.querySelectorAll('nav button').forEach(b=>b.classList.toggle('active',b.dataset.tab===tab));if(tab==='buy'){const rows=(data.shop||[]).filter(x=>x.enabled).map(s=>`<div class="card buy-card"><img class="item-img" src="${itemImg(s.item)}" onerror="this.style.visibility='hidden'"><div class="item-info"><h3>${s.label}</h3><p>${s.item||''}</p><div class="toolbar" style="margin:15px 0 0"><b class="price">${money(s.price)}원 · ${s.qty||1}개</b><button class="btn" data-buy="${s.kind}">구매</button></div></div></div>`).join('');content.innerHTML=`<div class="toolbar"><h2>낚시용품 구매</h2><span>낚싯대 3단계 · 미끼 3단계</span></div><div class="grid">${rows}</div>`;content.querySelectorAll('[data-buy]').forEach(b=>b.onclick=()=>post('managerBuy',{npcId:data.npcId,kind:b.dataset.buy}));return}if(tab==='sell'){const rows=(data.fish||[]).map(f=>`<div class="row"><div class="grow"><b>${f.label} <span class="badge">${f.gradeLabel||''}</span></b><small>${Number(f.kg||0).toFixed(2)}kg · ${f.count||1}마리 · kg당 ${money(f.ppk)}원</small></div><div class="price">${money(f.value)}원</div><button class="btn dark" data-sell="${f.key}" data-slot="${f.slot}">판매</button></div>`).join('');content.innerHTML=`<div class="summary"><div class="stat"><span>보유 물고기</span><b>${data.totalCount||0}마리</b></div><div class="stat"><span>예상 총 매입가</span><b>${money(data.totalValue)}원</b></div><div class="stat"><span>낚시왕</span><b>${data.hof?data.hof.nickname:'없음'}</b></div></div><div class="toolbar"><h2>물고기 판매</h2><button class="btn" id="sellAll">전부 판매</button></div>${rows||'<div class="empty">판매 가능한 물고기가 없습니다.</div>'}`;document.getElementById('sellAll').onclick=()=>post('managerSellAll',{npcId:data.npcId});content.querySelectorAll('[data-sell]').forEach(b=>b.onclick=()=>post('managerSellOne',{npcId:data.npcId,key:b.dataset.sell,slot:Number(b.dataset.slot)}));return}const c=data.collection||{},sm=c.summary||{},rows=(c.fish||[]).filter(x=>x.discovered).map(x=>`<div class="row"><div class="grow"><b>${x.label} <span class="badge">${x.gradeLabel||''}</span></b><small>누적 ${x.caughtCount||0}마리 · 개인 최고 ${Number(x.personalBest||0).toFixed(2)}kg</small></div>${x.serverRecord?`<div class="price">서버 ${Number(x.serverRecord.kg||0).toFixed(2)}kg</div>`:''}</div>`).join('');content.innerHTML=`<div class="summary"><div class="stat"><span>발견 어종</span><b>${sm.discovered||0} / ${sm.total||0}</b></div><div class="stat"><span>누적 낚시</span><b>${sm.totalCaught||0}마리</b></div><div class="stat"><span>낚시왕</span><b>${c.king?c.king.nickname:'없음'}</b></div></div><div class="toolbar"><h2>나의 낚시 기록</h2></div>${rows||'<div class="empty">아직 낚시 기록이 없습니다.</div>'}`}
const fishGame=document.getElementById('fishGame');
const fishPrompt=document.getElementById('fishPrompt');
const fishKeys=document.getElementById('fishKeys');
const fishGrade=document.getElementById('fishGrade');
const fishHint=document.getElementById('fishHint');
const fishProgressText=document.getElementById('fishProgressText');
const fishTimeBar=document.getElementById('fishTimeBar');
let fishSeq=[];
let fishCurrent=1;
let fishTimer=null;

function stopFishTimer(){if(fishTimer){clearTimeout(fishTimer);fishTimer=null}}
function paintFishKeys(){
  if(!fishKeys)return;
  fishKeys.querySelectorAll('.fish-key').forEach((el,i)=>{
    el.classList.toggle('current',i+1===fishCurrent);
  });
  if(fishProgressText) fishProgressText.textContent=Math.max(0,fishCurrent-1)+' / '+fishSeq.length;
}
function openFishGame(d){
  fishSeq=Array.isArray(d.sequence)?d.sequence:[];
  fishCurrent=1;
  fishKeys.innerHTML=fishSeq.map((k,i)=>'<div class="fish-key" data-index="'+(i+1)+'"><span>'+(k.label||String(k.key||'').toUpperCase())+'</span></div>').join('');
  fishGrade.textContent=d.gradeLabel||'낚시';
  fishGrade.style.borderColor=d.gradeColor||'#4dabf7';
  fishGrade.style.color=d.gradeColor||'#4dabf7';
  fishHint.textContent='표시된 키를 왼쪽부터 입력';
  fishGame.classList.remove('hidden');
  paintFishKeys();
  stopFishTimer();
  fishTimeBar.style.transition='none';
  fishTimeBar.style.width='100%';
  requestAnimationFrame(()=>requestAnimationFrame(()=>{
    fishTimeBar.style.transition='width '+Math.max(500,Number(d.duration||6000))+'ms linear';
    fishTimeBar.style.width='0%';
  }));
}
function hitFishKey(index){
  const el=fishKeys.querySelector('[data-index="'+index+'"]');
  if(el){el.classList.remove('current');el.classList.add('done')}
  fishCurrent=index+1;
  paintFishKeys();
}
function failFishGame(d){
  const el=fishKeys.querySelector('[data-index="'+(d.index||fishCurrent)+'"]');
  if(el){el.classList.remove('current');el.classList.add('fail')}
  fishHint.textContent=d.reason==='time'?'시간 초과! 물고기를 놓쳤습니다.':'잘못된 키! 물고기를 놓쳤습니다.';
  stopFishTimer();
  fishTimeBar.style.transition='none';
}
function successFishGame(){
  fishHint.textContent='성공! 물고기를 끌어올립니다.';
  fishKeys.querySelectorAll('.fish-key').forEach(el=>{el.classList.remove('current');el.classList.add('done')});
  if(fishProgressText) fishProgressText.textContent=fishSeq.length+' / '+fishSeq.length;
  stopFishTimer();
  fishTimeBar.style.width='100%';
}
function closeFishGame(){
  stopFishTimer();
  fishGame.classList.add('hidden');
  fishSeq=[];fishCurrent=1;
}

function setFishPrompt(d){
  if(!fishPrompt)return;
  if(d.show){fishPrompt.textContent=d.text||'[E] 낚시 시작';fishPrompt.classList.remove('hidden')}
  else fishPrompt.classList.add('hidden');
}

window.addEventListener('message',e=>{
  const d=e.data||{};
  if(d.action==='fishPrompt'){setFishPrompt(d);return;}
  if(d.action==='openManager'){
    data=d.data;title.textContent=data.label||'낚시 관리인';app.classList.remove('hidden');render();return;
  }
  if(d.action==='fishGameOpen'){openFishGame(d);return;}
  if(d.action==='fishGameHit'){hitFishKey(Number(d.index)||fishCurrent);return;}
  if(d.action==='fishGameCurrent'){fishCurrent=Number(d.index)||fishCurrent;paintFishKeys();return;}
  if(d.action==='fishGameFail'){failFishGame(d);return;}
  if(d.action==='fishGameSuccess'){successFishGame();return;}
  if(d.action==='fishGameClose'){closeFishGame();return;}
});document.querySelectorAll('nav button').forEach(b=>b.onclick=()=>{tab=b.dataset.tab;render()});document.getElementById('close').onclick=()=>{app.classList.add('hidden');post('managerClose')};document.addEventListener('keydown',e=>{if(e.key==='Escape'){app.classList.add('hidden');post('managerClose')}});