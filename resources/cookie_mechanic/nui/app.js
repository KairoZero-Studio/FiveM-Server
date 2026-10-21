const $=id=>document.getElementById(id);let ST=null,IV=null;
const comma=n=>Number(n||0).toLocaleString();
function post(n,d){return fetch('https://cookie_mechanic/'+n,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(d||{})}).catch(()=>{})}
function profile(){const s=(ST&&ST.skill)||{},lv=Number(ST&&ST.level)||1,b=Math.max(0,Math.round(((Number(ST&&ST.payMult)||1)-1)*100));$('profile').innerHTML='<div class="pfTop"><b class="pfJob">정비공</b><span class="duty '+(ST&&ST.onDuty?'on':'')+'">'+(ST&&ST.onDuty?'근무중':'퇴근')+'</span></div><div class="rows"><div><span>정비 보너스</span><b>+'+b+'%</b></div><div><span>완료 정비</span><b>'+comma(s.total_job)+'건</b></div><div><span>누적 수익</span><b>'+comma(s.total_pay)+'원</b></div></div>'}
function acts(){let a=!ST||!ST.hired?[['hire','정비공으로 일하고 싶습니다'],['close','나가기']]:[['duty',ST.onDuty?'퇴근하겠습니다':'출근하겠습니다'],['quit','그만두겠습니다'],['close','나가기']];$('acts').innerHTML=a.map(x=>'<button class="act '+(x[0]==='quit'?'danger':'')+'" data-k="'+x[0]+'">'+x[1]+'</button>').join('')}
$('acts').onclick=e=>{let b=e.target.closest('[data-k]');if(!b)return;let k=b.dataset.k;if(k==='close')post('close');if(k==='hire')post('hire');if(k==='quit')post('quit');if(k==='duty')post('duty',{on:!(ST&&ST.onDuty)})};
function stop(){if(IV){clearInterval(IV);IV=null}}function hide(){stop();$('offer').classList.add('hidden')}
function timer(ttl){stop();let total=Number(ttl)||45,t0=Date.now();let tick=()=>{let l=Math.max(0,total-(Date.now()-t0)/1000);$('offerTimer').textContent='남은 시간 '+Math.ceil(l)+'초';$('offerBar').style.width=(l/total*100)+'%';if(l<=0)hide()};tick();IV=setInterval(tick,100)}
function showOffer(title,car,pay,secs,ttl,type){$('offerTitle').textContent=title;$('offerCar').textContent=car;$('offerPay').textContent=pay;$('offerSecs').textContent=secs;$('offerType').textContent=type;$('offer').classList.remove('hidden');timer(ttl)}
addEventListener('message',e=>{let d=e.data||{};
 if(d.action==='open'){$('dlg').classList.remove('hidden');$('npcName').textContent=(d.npc&&d.npc!=='정비소 반장')?d.npc:'강민철';$('speech').textContent='차에 문제라도 생겼나? 일할 생각이면 제대로 고쳐 보자고.'}
 if(d.action==='close')$('dlg').classList.add('hidden');
 if(d.action==='state'){ST=d.data||{};profile();acts()}
 if(d.action==='offer'){let x=d.data||{};showOffer(x.label||'현장 정비', 'NPC 차량 · '+(x.vehicleModel||'-'),comma(x.reward)+'원',comma(x.repairSeconds)+'초',x.ttl,'NPC 현장정비')}
 if(d.action==='playerOffer'){let x=d.data||{};showOffer('시민 긴급 정비 요청','실제 플레이어 차량','수락 후 요금 계산','현장 정비',x.ttl,'PLAYER 정비')}
 if(d.action==='offerExpired'||d.action==='offerClosed'||d.action==='playerOfferClose')hide();
 if(d.action==='task'){hide();$('status').classList.remove('hidden');$('statusTitle').textContent='NPC 현장 출동';$('statusText').textContent='고장 차량과 고객 NPC 위치로 이동하세요'}
 if(d.action==='playerTask'){hide();$('status').classList.remove('hidden');$('statusTitle').textContent='시민 정비 출동';$('statusText').textContent='실제 플레이어 차량으로 이동하세요 · 예상요금 '+comma(d.data&&d.data.price)+'원'}
 if(d.action==='completed'){hide();$('receiptPay').textContent=comma(d.data&&d.data.reward)+'원';$('receipt').classList.remove('hidden');setTimeout(()=>$('receipt').classList.add('hidden'),4500)}
 if(d.action==='clearAll'){hide();$('status').classList.add('hidden')}
});
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!$('dlg').classList.contains('hidden'))post('close')});
