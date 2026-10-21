const app=document.getElementById('app');
let current=null,drawing=false,drawingCount=0;
const post=(name,data={})=>fetch(`https://${GetParentResourceName()}/${name}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)}).catch(()=>{});
const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));

function render(d){
  current=d||{};
  document.getElementById('title').textContent=current.title||'COOKIE 월간 쿠지';
  document.getElementById('season').textContent=(current.seasonMonth||'-')+' 시즌';
  document.getElementById('tickets').textContent=Number(current.tickets||0)+'장';
  document.getElementById('remaining').textContent=`${Number(current.remaining||0)} / ${Number(current.total||0)}`;

  const grid=document.getElementById('prizeGrid');grid.innerHTML='';
  (current.prizes||[]).forEach(p=>{
    const x=document.createElement('div');x.className='prize '+(Number(p.remaining)<=0?'soldout':'');
    x.innerHTML=`<span class="grade">${esc(p.grade)}</span><span class="stock">${Number(p.remaining)} / ${Number(p.stock)}</span><h3>${esc(p.label)}</h3><div class="meta">${esc(p.rewardType)} · ${Number(p.amount||1)}개</div>${p.image?`<img src="${esc(p.image)}" onerror="this.style.display='none'">`:''}`;
    grid.appendChild(x);
  });
  if(!(current.prizes||[]).length)grid.innerHTML='<div class="empty">등록된 경품이 없습니다.</div>';

  const hist=document.getElementById('history');hist.innerHTML='';
  (current.history||[]).forEach(h=>{const x=document.createElement('div');x.className='hist';x.innerHTML=`<b>${esc(h.label)}</b><span>${esc(h.grade)}상</span><small>${esc(String(h.created_at||''))}</small>`;hist.appendChild(x)});
  if(!(current.history||[]).length)hist.innerHTML='<div class="empty">아직 뽑은 기록이 없습니다.</div>';

  document.querySelectorAll('.drawBtn').forEach(btn=>{
    const n=Number(btn.dataset.count)||1;
    const disabled=drawing||!current.enabled||Number(current.tickets||0)<n||Number(current.remaining||0)<n;
    btn.disabled=disabled;
    btn.textContent=drawing&&drawingCount===n?`${n}회 뽑는 중...`:`${n}장 사용`;
  });
}

function showResult(d){
  const box=document.getElementById('result');box.classList.remove('hidden');
  const results=Array.isArray(d.results)?d.results:(d.prize?[d.prize]:[]);
  if(d.ok&&results.length){
    document.getElementById('resultGrade').textContent=results.length===1?String(results[0].grade||'?'):`×${results.length}`;
    document.getElementById('resultName').textContent=results.length===1?String(results[0].label||'당첨!'):`${results.length}회 뽑기 결과`;
    const lines=results.map((p,i)=>`${i+1}. [${p.grade}상] ${p.label}${p.permanent?'  📦':''}`);
    if(d.refunded)lines.push(`\n※ 실패분 티켓 ${Number(d.refunded)}장 환불`);
    document.getElementById('resultText').textContent=lines.join('\n');
  }else{
    document.getElementById('resultGrade').textContent='!';
    document.getElementById('resultName').textContent='뽑기 실패';
    document.getElementById('resultText').textContent=d.message||'오류가 발생했습니다.';
  }
}

window.addEventListener('message',e=>{
  const m=e.data||{};
  if(m.action==='open'){app.classList.remove('hidden');render(m.data)}
  if(m.action==='close')app.classList.add('hidden');
  if(m.action==='drawResult'){
    drawing=false;drawingCount=0;
    const d=m.data||{};
    if(d.state)render(d.state);else render(current||{});
    showResult(d);
  }
});

document.getElementById('close').onclick=()=>post('close');
document.querySelectorAll('.drawBtn').forEach(btn=>btn.addEventListener('click',()=>{
  if(drawing)return;
  const count=Number(btn.dataset.count)||1;
  drawing=true;drawingCount=count;render(current||{});
  post('draw',{count});
}));
document.getElementById('resultOk').onclick=()=>document.getElementById('result').classList.add('hidden');
document.addEventListener('keydown',e=>{if(e.key==='Escape')post('close')});
