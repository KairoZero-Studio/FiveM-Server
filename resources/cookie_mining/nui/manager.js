const app=document.getElementById('app'),content=document.getElementById('content'),title=document.getElementById('title');let data=null,tab='buy';const post=(n,b={})=>fetch(`https://${GetParentResourceName()}/${n}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(b)}).catch(()=>{});const money=v=>Number(v||0).toLocaleString('ko-KR');const itemImg=item=>`https://cfx-nui-ox_inventory/web/images/${encodeURIComponent(item||'')}.png`;function render(){if(!data)return;document.querySelectorAll('nav button').forEach(b=>b.classList.toggle('active',b.dataset.tab===tab));if(tab==='buy'){const rows=(data.shop||[]).filter(x=>x.enabled).map(s=>`<div class="card buy-card"><img class="item-img" src="${itemImg(s.item)}" onerror="this.style.visibility='hidden'"><div class="item-info"><h3>${s.label}</h3><p>${s.item||''}<br>채굴시간 배율 x${Number(s.durationMultiplier||1).toFixed(2)}</p><div class="toolbar" style="margin:15px 0 0"><b class="price">${money(s.price)}원 · ${s.qty||1}개</b><button class="btn" data-buy="${s.kind}">구매</button></div></div></div>`).join('');content.innerHTML=`<div class="toolbar"><h2>곡괭이 구매</h2><span>장비 단계가 높을수록 채굴 시간이 짧아집니다.</span></div><div class="grid">${rows||'<div class="empty">판매 중인 곡괭이가 없습니다.</div>'}</div>`;content.querySelectorAll('[data-buy]').forEach(b=>b.onclick=()=>post('managerBuy',{npcId:data.npcId,kind:b.dataset.buy}));return}if(tab==='sell'){const rows=(data.minerals||[]).map(m=>`<div class="row"><div class="grow"><b>${m.label} <span class="badge">순도 ${m.purity||0}%</span></b><small>${m.count||1}개 · 개당 ${money(m.priceEach)}원</small></div><div class="price">${money(m.value)}원</div><button class="btn dark" data-sell="${m.key}" data-slot="${m.slot}">판매</button></div>`).join('');content.innerHTML=`<div class="summary"><div class="stat"><span>보유 광물</span><b>${data.totalCount||0}개</b></div><div class="stat"><span>예상 총 매입가</span><b>${money(data.totalValue)}원</b></div><div class="stat"><span>순도</span><b>개별 반영</b></div></div><div class="toolbar"><h2>광물 판매</h2><button class="btn" id="sellAll">전부 판매</button></div>${rows||'<div class="empty">매입 가능한 광물이 없습니다.</div>'}`;document.getElementById('sellAll').onclick=()=>post('managerSellAll',{npcId:data.npcId});content.querySelectorAll('[data-sell]').forEach(b=>b.onclick=()=>post('managerSellOne',{npcId:data.npcId,key:b.dataset.sell,slot:Number(b.dataset.slot)}));return}const r=data.records||{},rows=(r.rows||[]).map(x=>`<div class="row"><div class="grow"><b>${x.discovered?x.label:'미발견'} <span class="badge">${x.rarityLabel||''}</span></b><small>${x.discovered?`채굴 ${x.count||0}회 · 최고 순도 ${x.bestPurity||0}%`:'아직 채굴 기록이 없습니다.'}</small></div></div>`).join('');const lb=(r.leaderboard||[]).map(x=>`<div class="row"><div style="width:42px;font-weight:900">#${x.rank}</div><div class="grow"><b>${x.nickname||('고번 '+(x.gobun||'-'))} <span class="badge">${x.rarityLabel||''}</span></b><small>고번 ${x.gobun||'-'} · ${x.mineralLabel||x.mineral||'-'}</small></div><div class="price">순도 ${x.purity||0}%</div></div>`).join('');content.innerHTML=`<div class="summary"><div class="stat"><span>발견 광물</span><b>${r.discovered||0} / ${r.total||0}</b></div><div class="stat"><span>누적 채굴</span><b>${r.totalMined||0}회</b></div><div class="stat"><span>기록 기준</span><b>순도 → 광물 등급</b></div></div><div class="toolbar"><h2>서버 최고 순도 TOP 10</h2><span>순도가 같으면 더 높은 등급 광물이 우선입니다.</span></div>${lb||'<div class="empty">아직 서버 광물 기록이 없습니다.</div>'}<div class="toolbar" style="margin-top:24px"><h2>나의 광질 기록</h2></div>${rows}`}
window.addEventListener('message',e=>{
  if(e.data?.action==='openManager'){
    data=e.data.data||{};
    title.textContent=data.label||'광물 관리인';
    app.classList.remove('hidden');
    if(data.loading){
      content.innerHTML='<div class="empty">광물 관리인 정보를 불러오는 중...</div>';
    }else{
      render();
    }
  }
  if(e.data?.action==='managerError'){
    app.classList.remove('hidden');
    content.innerHTML='<div class="empty">'+String(e.data.message||'광물 관리인 정보를 불러오지 못했습니다.')+'</div>';
  }
});document.querySelectorAll('nav button').forEach(b=>b.onclick=()=>{tab=b.dataset.tab;render()});document.getElementById('close').onclick=()=>{app.classList.add('hidden');post('managerClose')};document.addEventListener('keydown',e=>{if(e.key==='Escape'){app.classList.add('hidden');post('managerClose')}});
const minePrompt=document.getElementById('minePrompt');window.addEventListener('message',e=>{const d=e.data||{};if(d.action==='minePrompt'){if(!minePrompt)return;if(d.show){minePrompt.textContent=d.text||'[E] 광질';minePrompt.style.left=((Number(d.x)||.5)*100)+'%';minePrompt.style.top=((Number(d.y)||.5)*100)+'%';minePrompt.classList.remove('hidden')}else{minePrompt.classList.add('hidden')}}});

// V13.8 - mining circle timing minigame (NUI-authoritative visual sync)
const miningSkill=document.getElementById('miningSkill');
const miningSkillCard=miningSkill?.querySelector('.mining-skill-card');
const miningSkillTitle=document.getElementById('miningSkillTitle');
const miningSkillTarget=document.getElementById('miningSkillTarget');
const miningSkillMover=document.getElementById('miningSkillMover');
const miningSkillState=document.getElementById('miningSkillState');
let miningSkillRadius=86;
let miningSkillRun=null;

function miningPoint(el,angle){
  if(!el)return;
  const r=angle*Math.PI/180;
  const x=Math.sin(r)*miningSkillRadius;
  const y=-Math.cos(r)*miningSkillRadius;
  el.style.transform=`translate(calc(-50% + ${x}px),calc(-50% + ${y}px))`;
}

function miningAngleDiff(a,b){
  let d=Math.abs((((a-b)%360)+360)%360);
  if(d>180)d=360-d;
  return d;
}

function stopMiningSkillAnim(){
  if(miningSkillRun?.raf){
    cancelAnimationFrame(miningSkillRun.raf);
  }
  if(miningSkillRun){
    miningSkillRun.raf=0;
  }
}

function miningSkillCurrentAngle(){
  if(!miningSkillRun)return 0;
  const elapsed=Math.max(0,performance.now()-miningSkillRun.startedAt);
  return ((elapsed%miningSkillRun.period)/miningSkillRun.period)*360;
}

function startMiningSkillAnim(){
  stopMiningSkillAnim();

  const tick=()=>{
    if(!miningSkillRun)return;
    const angle=miningSkillCurrentAngle();
    miningSkillRun.angle=angle;
    miningPoint(miningSkillMover,angle);
    miningSkillRun.raf=requestAnimationFrame(tick);
  };

  miningSkillRun.raf=requestAnimationFrame(tick);
}

window.addEventListener('message',e=>{
  const d=e.data||{};

  if(d.action==='miningSkillOpen'){
    if(!miningSkill)return;

    stopMiningSkillAnim();

    miningSkillRun={
      roundId:String(d.roundId||''),
      target:Number(d.target)||0,
      tolerance:Math.max(24,Math.min(48,Number(d.tolerance)||36)),
      period:Math.max(850,Number(d.period)||1250),
      startedAt:performance.now(),
      angle:0,
      raf:0,
    };

    miningSkill.classList.remove('hidden');
    miningSkillCard?.classList.remove('success','fail');

    if(miningSkillTitle)miningSkillTitle.textContent=d.label||'광질 타이밍';
    if(miningSkillState)miningSkillState.textContent='흰 원을 초록 원 안에 맞추세요';

    miningPoint(miningSkillTarget,miningSkillRun.target);
    miningPoint(miningSkillMover,0);

    const tol=miningSkillRun.tolerance;
    if(miningSkillTarget){
      const size=42+(tol-24)*1.05;
      miningSkillTarget.style.width=size+'px';
      miningSkillTarget.style.height=size+'px';
    }

    startMiningSkillAnim();
    return;
  }

  if(d.action==='miningSkillJudge'){
    if(!miningSkillRun)return;

    const roundId=String(d.roundId||'');
    if(roundId!==miningSkillRun.roundId)return;

    // 실제 브라우저에서 그리고 있는 현재 위치를 바로 계산해서 판정.
    // 저FPS/NUI 지연 보정을 위해 8도 grace를 추가한다.
    const angle=miningSkillCurrentAngle();
    const success=miningAngleDiff(angle,miningSkillRun.target)<=miningSkillRun.tolerance+8;

    miningSkillRun.angle=angle;
    miningPoint(miningSkillMover,angle);
    stopMiningSkillAnim();

    miningSkillCard?.classList.remove('success','fail');
    miningSkillCard?.classList.add(success?'success':'fail');
    if(miningSkillState)miningSkillState.textContent=success?'성공!':'실패!';

    post('miningSkillJudged',{
      roundId:miningSkillRun.roundId,
      success,
      angle,
      target:miningSkillRun.target,
    });
    return;
  }

  if(d.action==='miningSkillResult'){
    if(!miningSkill)return;
    stopMiningSkillAnim();
    miningSkillCard?.classList.remove('success','fail');
    miningSkillCard?.classList.add(d.success?'success':'fail');
    if(miningSkillState){
      miningSkillState.textContent=d.success?'성공!':(d.timeout?'시간 초과!':'실패!');
    }
    return;
  }

  if(d.action==='miningSkillClose'){
    if(!miningSkill)return;
    stopMiningSkillAnim();
    miningSkillRun=null;
    miningSkill.classList.add('hidden');
    miningSkillCard?.classList.remove('success','fail');
  }
});

// COOKIE MINING RHYTHM NUI SYNC V13.8
