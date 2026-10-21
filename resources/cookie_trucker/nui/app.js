
const $ = (id) => document.getElementById(id);
const root = $('root');
const greetView = $('greetView');
const workView = $('workView');
const cineWrap = $('cineWrap');
const cineNpc = $('cineNpc');
const cineText = $('cineText');
const guideCard = $('guideCard');

let cineTimers = [], cineQueue = [], cineBusy = false;
function clearCine(){ cineTimers.forEach(clearTimeout); cineTimers = []; cineQueue = []; cineBusy = false; cineWrap.classList.remove('show'); }
function playNextCine(){
  if(cineBusy) return;
  const it = cineQueue.shift();
  if(!it){ return; }
  cineBusy = true;
  if(it.npc){ cineNpc.textContent = it.npc; cineNpc.style.display = ''; }
  else { cineNpc.style.display = 'none'; }
  cineText.textContent = it.text || '';
  cineText.classList.toggle('gold', !!it.gold);
  cineWrap.classList.remove('show'); void cineWrap.offsetWidth; cineWrap.classList.add('show');
  const hold = it.hold || 2600;
  cineTimers.push(setTimeout(()=>{
    cineWrap.classList.remove('show');
    cineTimers.push(setTimeout(()=>{ cineBusy = false; playNextCine(); }, 1500));
  }, hold));
}
function showCineSeq(seq){ clearCine(); cineQueue = (seq || []).slice(); playNextCine(); }
function showGuide(d){
  const lv = Math.max(1, d.level||1), cap = d.cap||(lv*15), loaded = d.loaded||0;
  $('gLv').textContent = '적재 현황';
  $('gCapNum').textContent = loaded + ' / ' + cap;
  $('gCapBar').style.width = Math.max(0, Math.min(100, cap ? (loaded/cap*100) : 0)) + '%';
  $('gGo').textContent = d.line || '재고지로 이동하시오.';
  guideCard.classList.add('show');
}
function hideDrive(){ clearCine(); guideCard.classList.remove('show'); }

function showReceipt(d){
  document.getElementById('rcPay').textContent = won(d.pay);
  document.getElementById('rcDate').textContent = d.date || '-';
  document.getElementById('rcBody').textContent =
    (d.from || '출발지') + '에서 ' + (d.to || '배송지') + '까지 물건을 배송완료하여 위 금액을 지급함.';
  const r = document.getElementById('receipt');
  r.classList.remove('hidden'); void r.offsetWidth; r.classList.add('on');
}
function hideReceipt(){ const r = document.getElementById('receipt'); r.classList.remove('on'); r.classList.add('hidden'); }

let LINES = {};
let STATE = { hired:false, onDuty:false, level:1, exp:0, deliveries:0, payMult:1.0 };
let JOBS = [];
const THR = [0, 50, 100, 150, 200];
const MAP_SPOTS = [ {x:70,y:22},{x:34,y:16},{x:82,y:34},{x:88,y:66},{x:52,y:46},{x:44,y:70} ];
const ORIGIN = { x:16, y:80 };
const won = (n)=> '₩ ' + Number(n||0).toLocaleString();
const pic = (i)=> { const h=(i*57)%360; return `linear-gradient(135deg,hsl(${h} 42% 40%),hsl(${h+30} 38% 24%))`; };

function showGreet(){ greetView.classList.remove('hidden'); workView.classList.add('hidden'); }
function showWork(){ greetView.classList.add('hidden'); workView.classList.remove('hidden'); renderMe(); renderJobs(); if(STATE.hired && STATE.onDuty) post('requestJobs'); }

function renderMe(){
  const s = STATE;
  if(!s.hired){
    $('meBody').innerHTML =
      `<div class="lvcard">
         <div class="greet-mini">아직 트럭커가 아닙니다</div>
         <button class="btn-primary" id="hireBtn">트럭커로 취업하기</button>
       </div>`;
    $('hireBtn').onclick = ()=> post('hire');
    return;
  }
  const li = Math.max(1, Math.min(5, s.level));
  const lo = THR[li-1], hi = THR[li] || (lo+50);
  const pct = li>=5 ? 100 : Math.max(0, Math.min(100, Math.round((s.exp-lo)/(hi-lo)*100)));
  const toNext = li>=5 ? '최고 레벨' : ('다음 레벨까지 ' + Math.max(0, hi - s.exp));
  const bonus = '＋' + Math.round((s.payMult-1)*100) + '% 보수';
  $('meBody').innerHTML =
    `<div class="lvcard">
       <div class="job">트럭기사</div>
       <div class="expnum">완료 배송 ${s.deliveries}건</div>
     </div>
     <div class="lvcard stat">
       <div class="statrow"><span class="k">완료 배송</span><span class="v">${s.deliveries} 건</span></div>
       <div class="statrow"><span class="k">근무 상태</span><span class="v">${s.onDuty?'출근':'퇴근'}</span></div>
       <div class="statrow"><span class="k">숙련 보너스</span><span class="v pay">${bonus}</span></div>
     </div>
     <button class="btn-duty ${s.onDuty?'off':''}" id="dutyBtn">${s.onDuty?'퇴근하기':'출근하기'}</button>
     <button class="quit" id="quitBtn">트럭 일 그만두기</button>`;
  $('dutyBtn').onclick = ()=> post('duty', { on: !s.onDuty });
  $('quitBtn').onclick = ()=> post('quit');
}

function renderJobs(){
  const canWork = STATE.hired && STATE.onDuty;
  $('jobGrid').classList.toggle('hidden', !canWork || JOBS.length===0);
  $('jobsEmpty').classList.toggle('hidden', canWork && JOBS.length>0);
  $('jobsEmpty').textContent = !STATE.hired ? '먼저 트럭커로 취업하세요'
    : (!STATE.onDuty ? '출근 후 배송 작업을 받을 수 있습니다' : '가능한 배송 작업이 없습니다');
  if(!canWork){ $('jobGrid').innerHTML=''; return; }

  $('jobGrid').innerHTML = JOBS.slice(0,12).map((j,i)=>`
    <div class="job" data-i="${i}">
      <div class="pic" style="background-image:${ j.img ? `url('${j.img}')` : pic(i) }"></div>
      <div class="bd">
        <div class="dest">${j.dest}</div>
        <div class="from">상차 · ${j.from}</div>
        <div class="meta">
          <div class="chip"><div class="k">거리</div><div class="v">${j.distKm} km</div></div>
          <div class="chip"><div class="k">보수</div><div class="v pay">${won(j.pay)}</div></div>
        </div>
        <button class="go">지도에서 보기</button>
      </div>
    </div>`).join('');
  $('jobGrid').querySelectorAll('.job').forEach(c=> c.onclick = ()=> openMap(+c.dataset.i));
}

const modal = $('mapModal'), markers = $('markers'), routeLine = $('routeLine');
let curIdx = -1;
function drawMap(i){
  markers.innerHTML='';
  const o=document.createElement('div'); o.className='mk origin';
  o.innerHTML='<div class="lbl">출발</div><div class="dp"></div>'; o.style.left=ORIGIN.x+'%'; o.style.top=ORIGIN.y+'%'; markers.appendChild(o);
  JOBS.forEach((j,k)=>{
    const sp=MAP_SPOTS[k%MAP_SPOTS.length];
    const m=document.createElement('div'); m.className='mk '+(k===i?'dest':''); m.style.opacity=(k===i?'1':'.4');
    m.innerHTML=(k===i?`<div class="lbl">${j.dest}</div>`:'')+'<div class="dp"></div>';
    m.style.left=sp.x+'%'; m.style.top=sp.y+'%'; markers.appendChild(m);
  });
  const sp=MAP_SPOTS[i%MAP_SPOTS.length];
  const mx=(ORIGIN.x+sp.x)/2, my=(ORIGIN.y+sp.y)/2-12;
  routeLine.setAttribute('d',`M${ORIGIN.x},${ORIGIN.y} Q${mx},${my} ${sp.x},${sp.y}`);
}
function openMap(i){
  curIdx=i; const j=JOBS[i];
  $('mDest').textContent=j.dest; $('mTo').textContent=j.dest;
  $('mDist').textContent=j.distKm+' km'; $('mPay').textContent=won(j.pay);

  $('destPic').style.backgroundImage = j.img ? `url('${j.img}')` : pic(i);
  const stage = document.querySelector('.mapStage');
  if(j.img){ stage.style.backgroundImage = `url('${j.img}')`; stage.classList.add('photo'); }
  else { stage.style.backgroundImage=''; stage.classList.remove('photo'); }
  drawMap(i); modal.classList.add('on');
}
$('backBtn').onclick = ()=> modal.classList.remove('on');
$('cancelBtn').onclick = ()=> modal.classList.remove('on');
$('acceptBtn').onclick = ()=>{ if(curIdx>=0 && JOBS[curIdx]) post('accept', { id: JOBS[curIdx].id }); };

$('goWorkBtn').onclick = ()=> showWork();
$('greetClose').onclick = ()=> post('close');
$('closeBtn').onclick = ()=> post('close');
$('rcOk').onclick = ()=>{ hideReceipt(); post('receiptClose'); };
document.addEventListener('keydown', (e)=>{
  if(e.key!=='Escape') return;
  if(modal.classList.contains('on')){ modal.classList.remove('on'); return; }
  if(!workView.classList.contains('hidden') && !greetView.classList.contains('hidden')){  }
  post('close');
});

function post(name, data){
  fetch(`https://cookie_trucker/${name}`, {
    method:'POST', headers:{'Content-Type':'application/json; charset=UTF-8'},
    body: JSON.stringify(data||{}),
  }).catch(()=>{});
}

window.addEventListener('message', (ev)=>{
  const d = ev.data||{};
  if(d.action==='open'){
    LINES = d.lines||{};
    $('greetNpc').textContent = d.npc || '트럭 배차관리인';
    $('greetText').textContent = LINES.greet || '어이, 배송 일 찾아왔나?';
    root.classList.remove('hidden'); modal.classList.remove('on');
    hideDrive();
    showGreet();
    return;
  }
  if(d.action==='cine'){ if(d.seq) showCineSeq(d.seq); else showCineSeq([{ text: d.text }]); return; }
  if(d.action==='guide'){ showGuide(d); return; }
  if(d.action==='guideHide'){ guideCard.classList.remove('show'); return; }
  if(d.action==='receipt'){ showReceipt(d); return; }
  if(d.action==='receiptClose'){ hideReceipt(); return; }
  if(d.action==='state'){
    STATE = Object.assign(STATE, d.state||{});
    if(!workView.classList.contains('hidden')){ renderMe(); renderJobs(); if(STATE.hired && STATE.onDuty) post('requestJobs'); }
    return;
  }
  if(d.action==='jobs'){ JOBS = d.jobs||[]; if(!workView.classList.contains('hidden')) renderJobs(); return; }
  if(d.action==='line'){ return; }
  if(d.action==='close'){ root.classList.add('hidden'); modal.classList.remove('on'); return; }
});
