let ST=null;const $=id=>document.getElementById(id);let OFFER_IV=null;
function stopOfferTimer(){if(OFFER_IV){clearInterval(OFFER_IV);OFFER_IV=null}}
function hideOffer(){stopOfferTimer();$('offer').classList.add('hidden')}
function startOfferTimer(ttl){
  stopOfferTimer();
  const total=Math.max(1,Number(ttl)||45);
  const started=Date.now();
  const bar=$('offer').querySelector('.dl-bar i');
  const timer=$('offerTimer');
  function tick(){
    const elapsed=(Date.now()-started)/1000;
    const left=Math.max(0,total-elapsed);
    if(timer)timer.textContent='남은 시간 '+Math.ceil(left)+'초';
    if(bar)bar.style.width=Math.max(0,(left/total)*100)+'%';
    if(left<=0){stopOfferTimer();hideOffer()}
  }
  tick();
  OFFER_IV=setInterval(tick,100);
}
function post(n,d){fetch('https://cookie_delivery/'+n,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(d||{})}).catch(()=>{})}function esc(s){return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}function comma(n){return Number(n||0).toLocaleString()}function say(t){$('dlgSub').textContent=t||''}
function profile(){if(!ST){$('profile').innerHTML='<p class="tx-pf-h">배달 기사</p><p class="tx-pf-muted">불러오는 중</p>';return}if(!ST.hired){$('profile').innerHTML='<p class="tx-pf-h">배달 기사</p><p class="tx-pf-name">'+esc(ST.nick||'-')+(ST.gobun?' <i>('+esc(ST.gobun)+')</i>':'')+'</p><p class="tx-pf-muted">아직 배달 업무에 소속되지 않았다</p>';return}const s=ST.skill||{},cur=(s.exp||0)-(s.levelExp||0),span=s.nextExp?(s.nextExp-(s.levelExp||0)):0,pct=span>0?Math.min(100,Math.round(cur/span*100)):100;let bonus=Math.max(0,Math.round(((ST.payMult||1)-1)*100));$('profile').innerHTML='<p class="tx-pf-h">배달 기사</p><p class="tx-pf-name">'+esc(ST.nick||'-')+(ST.gobun?' <i>('+esc(ST.gobun)+')</i>':'')+'</p><div class="tx-pf-lv"><span class="tx-pf-duty '+(ST.onDuty?'on':'')+'">'+(ST.onDuty?'근무중':'퇴근')+'</span></div><div class="tx-pf-rows"><div><span>배달 보너스</span><b>+'+bonus+'%</b></div><div><span>완료 배달</span><b>'+comma(s.total_job)+'건</b></div><div><span>누적 수익</span><b>'+comma(s.total_pay)+'원</b></div><div><span>진행 중인 콜</span><b>'+(ST.active?'있음':ST.pending?'대기':'없음')+'</b></div></div>'}
function acts(){let a=[];if(!ST||!ST.hired){a=[['hire','배달기사로 일하고 싶습니다'],['close','나가기']]}else{a=[['duty',ST.onDuty?'퇴근하겠습니다':'출근하겠습니다'],['quit','그만두겠습니다'],['close','나가기']]}$('acts').innerHTML=a.map(x=>'<button class="tx-act'+(x[0]==='quit'?' danger':'')+'" data-k="'+x[0]+'">'+x[1]+'</button>').join('')}
$('acts').onclick=e=>{let b=e.target.closest('[data-k]');if(!b)return;let k=b.dataset.k;if(k==='close')post('close');if(k==='hire')post('hire');if(k==='quit')post('quit');if(k==='duty')post('duty',{on:!(ST&&ST.onDuty)})};$('accept').onclick=()=>post('accept');
addEventListener('message',e=>{let d=e.data||{};if(d.action==='open'){$('dlg').classList.remove('hidden');$('npcName').textContent=d.npc||'배달 관리인';say('왔는가. 오늘도 배달할 곳이 많을 걸세.')}if(d.action==='state'){ST=d.data||{};profile();acts();if(ST.onDuty&&!ST.active&&!ST.pending){$('deliveryStatus').classList.remove('hidden');$('dlTitle').textContent='배달 대기중';$('dlText').textContent='새로운 배달 콜을 기다리고 있습니다'}else $('deliveryStatus').classList.add('hidden')}if(d.action==='close')$('dlg').classList.add('hidden');if(d.action==='call'){let x=d.data;$('offerRoute').textContent=(x.restaurant?.label||'식당')+' → '+(x.dropoff?.label||'배달지');$('offerInfo').textContent=Number(x.distanceKm||0).toFixed(1)+' km · 예상 '+comma(x.estimated)+'원';$('offer').classList.remove('hidden');$('deliveryStatus').classList.add('hidden');startOfferTimer(x.ttl||45)}if(d.action==='accepted'){hideOffer();$('deliveryStatus').classList.remove('hidden');$('dlTitle').textContent='음식 픽업';$('dlText').textContent='지도에 표시된 식당으로 이동하세요'}if(d.action==='picked'){$('deliveryStatus').classList.remove('hidden');$('dlTitle').textContent='배달 진행중';$('dlText').textContent='지도에 표시된 고객 위치로 이동하세요'}if(d.action==='completed'){$('deliveryStatus').classList.remove('hidden');$('dlTitle').textContent='배달 완료';$('dlText').textContent=comma(d.data?.reward)+'원이 지급되었습니다';setTimeout(()=>$('deliveryStatus').classList.add('hidden'),3000)}if(d.action==='clearCall'){hideOffer();$('deliveryStatus').classList.remove('hidden');$('dlTitle').textContent='배달 대기중';$('dlText').textContent='다음 배달 콜을 기다리고 있습니다';return}if(d.action==='callExpired'){hideOffer();$('deliveryStatus').classList.remove('hidden');$('dlTitle').textContent='콜 시간 초과';$('dlText').textContent='요청이 취소되었습니다. 다음 콜을 기다립니다'}if(d.action==='clearAll'){hideOffer();$('deliveryStatus').classList.add('hidden')}});document.addEventListener('keydown',e=>{
 if(e.key==='Escape'&&!$('dlg').classList.contains('hidden'))post('close')
});