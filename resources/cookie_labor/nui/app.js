
const dialog=document.getElementById('dialog'),stats=document.getElementById('stats'),actions=document.getElementById('actions'),guide=document.getElementById('guide'),toast=document.getElementById('toast');
function post(n,d){return fetch('https://cookie_labor/'+n,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(d||{})}).catch(()=>{});}
function money(v){return Number(v||0).toLocaleString()+'원';}
function state(d){
  d=d||{};
  stats.innerHTML='<div class="stat"><span>근무 상태</span><b>'+(d.onDuty?'출근':'퇴근')+'</b></div><div class="stat"><span>보수 보너스</span><b>+'+Math.max(0,Math.round(((d.payMult||1)-1)*100))+'%</b></div>';
  let h='';
  if(!d.hired){
    h='<button class="act" data-a="hire">건설 인부로 취업하기</button>';
  }else{
    h+='<button class="act" data-a="duty" data-on="'+(!d.onDuty)+'">'+(d.onDuty?'퇴근하기':'출근하기')+'</button>';
    if(d.onDuty)h+='<button class="act sub" data-a="task">현재 작업 확인</button>';
    h+='<button class="act danger" data-a="quit">직업 그만두기</button>';
  }
  actions.innerHTML=h;
  actions.querySelectorAll('button').forEach(b=>b.onclick=()=>{
    const a=b.dataset.a;
    if(a==='hire')post('hire');
    else if(a==='quit')post('quit');
    else if(a==='duty')post('duty',{on:b.dataset.on==='true'});
    else if(a==='task')post('task');
  });
}
function showToast(t){
  toast.textContent=t||'';toast.classList.remove('hidden');
  clearTimeout(window.__lt);window.__lt=setTimeout(()=>toast.classList.add('hidden'),3000);
}
window.addEventListener('message',e=>{
  const d=e.data||{};
  if(d.action==='openLoading'){document.getElementById('npcName').textContent=(d.npc&&d.npc!=='현장 반장'&&d.npc!=='건설 반장')?d.npc:'건설 반장 권설현';dialog.classList.remove('hidden');stats.innerHTML='<div class="stat"><span>상태</span><b>불러오는 중...</b></div>';actions.innerHTML='';}
  else if(d.action==='state')state(d.data);
  else if(d.action==='close')dialog.classList.add('hidden');
  else if(d.action==='toastLine')showToast(d.text);
  else if(d.action==='guide'){
    const total=Number(d.total||0),done=Number(d.delivered||0);
    document.getElementById('gLabel').textContent=d.label||'건설 작업';
    document.getElementById('gCount').textContent=done+'/'+total;
    document.getElementById('gBar').style.width=(total?Math.min(100,(done/total)*100):0)+'%';
    document.getElementById('gLine').textContent=d.line||'';
    document.getElementById('gReward').textContent=money(d.reward);
    guide.classList.remove('hidden');
  }else if(d.action==='guideHide')guide.classList.add('hidden');
  else if(d.action==='complete')showToast('작업 완료 · '+money(d.pay)+' 지급');
});
document.getElementById('close').onclick=()=>{dialog.classList.add('hidden');post('close');};
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!dialog.classList.contains('hidden')){dialog.classList.add('hidden');post('close');}});
