const app=document.getElementById('app');
let state=null;
let original=null;
let tuning=null;
let busy=false;
let repairRequired=false;

const $=id=>document.getElementById(id);
const post=(name,body={})=>fetch(`https://${GetParentResourceName()}/${name}`,{
  method:'POST',
  headers:{'Content-Type':'application/json'},
  body:JSON.stringify(body)
}).then(r=>r.json()).catch(()=>({ok:false,message:'NUI 통신 오류'}));

const money=n=>Number(n||0).toLocaleString('ko-KR')+'원';
const clone=v=>JSON.parse(JSON.stringify(v));

function hexToRgb(hex){
  hex=String(hex||'#ffffff').replace('#','');
  return [parseInt(hex.slice(0,2),16)||0,parseInt(hex.slice(2,4),16)||0,parseInt(hex.slice(4,6),16)||0];
}
function rgbToHex(rgb){
  const f=n=>Math.max(0,Math.min(255,Number(n)||0)).toString(16).padStart(2,'0');
  return '#'+f(rgb?.[0])+f(rgb?.[1])+f(rgb?.[2]);
}
function sameRgb(a,b){
  return Number(a?.[0])===Number(b?.[0])&&Number(a?.[1])===Number(b?.[1])&&Number(a?.[2])===Number(b?.[2]);
}
function sameSides(a,b){
  return !!a?.left===!!b?.left&&!!a?.right===!!b?.right&&!!a?.front===!!b?.front&&!!a?.back===!!b?.back;
}
function extrasChanged(a={},b={}){
  const keys=new Set([...Object.keys(a),...Object.keys(b)]);
  let n=0;
  keys.forEach(k=>{if(!!a[k]!==!!b[k])n++});
  return n;
}
function levelPrice(a,b,unit){return Math.abs(Number(a||0)-Number(b||0))*Number(unit||0)}
function levelText(v){return Number(v||0)<=0?'순정':`${Number(v)}단계`}

function calcPrice(){
  if(!state||!original||!tuning)return 0;
  const p=state.prices||{};
  let total=0;

  if(!sameRgb(original.primary,tuning.primary)||!!original.primaryCustom!==!!tuning.primaryCustom||Number(original.primaryIndex)!==Number(tuning.primaryIndex)) total+=Number(p.primaryColor||0);
  if(!sameRgb(original.secondary,tuning.secondary)||!!original.secondaryCustom!==!!tuning.secondaryCustom||Number(original.secondaryIndex)!==Number(tuning.secondaryIndex)) total+=Number(p.secondaryColor||0);
  if(String(original.specialKey)!==String(tuning.specialKey)) total+=Number(p.specialPaint||0);

  if(Number(original.wheelColor)!==Number(tuning.wheelColor))total+=Number(p.wheelColor||0);
  if(Number(original.windowTint)!==Number(tuning.windowTint))total+=Number(p.windowTint||0);
  if(Number(original.interiorColor)!==Number(tuning.interiorColor))total+=Number(p.interiorColor||0);

  total+=levelPrice(original.engineLevel,tuning.engineLevel,p.enginePerLevel);
  total+=levelPrice(original.speedLevel,tuning.speedLevel,p.speedPerLevel);
  total+=levelPrice(original.durabilityLevel,tuning.durabilityLevel,p.durabilityPerLevel);
  total+=levelPrice(original.brakeLevel,tuning.brakeLevel,p.brakePerLevel);
  total+=levelPrice(original.suspensionLevel,tuning.suspensionLevel,p.suspensionPerLevel);
  total+=levelPrice(original.transmissionLevel,tuning.transmissionLevel,p.transmissionPerLevel);

  if(!!original.turbo!==!!tuning.turbo)total+=Number(p.turbo||0);
  if(!!original.bulletproofTyres!==!!tuning.bulletproofTyres)total+=Number(p.bulletproofTyres||0);
  if(Number(original.hornIndex)!==Number(tuning.hornIndex))total+=Number(p.horn||0);

  if(!!original.xenonEnabled!==!!tuning.xenonEnabled||Number(original.xenonColor)!==Number(tuning.xenonColor))total+=Number(p.xenon||0);
  if(String(original.engineAudio)!==String(tuning.engineAudio))total+=Number(p.engineAudio||0);

  total+=extrasChanged(original.extras,tuning.extras)*Number(p.extrasEach||0);

  if(Number(original.plateStyle)!==Number(tuning.plateStyle))total+=Number(p.plateStyle||0);

  if(!!original.neonEnabled!==!!tuning.neonEnabled||!sameRgb(original.neonColor,tuning.neonColor)||!sameSides(original.neonSides,tuning.neonSides))total+=Number(p.neon||0);

  if(Number(original.wheelType)!==Number(tuning.wheelType)||Number(original.wheelIndex)!==Number(tuning.wheelIndex))total+=Number(p.wheelModel||0);

  if(!sameRgb(original.tyreSmoke,tuning.tyreSmoke)||!!original.tyreSmokeEnabled!==!!tuning.tyreSmokeEnabled)total+=Number(p.tyreSmokeColor||0);

  if(Number(original.frontBumper)!==Number(tuning.frontBumper))total+=Number(p.frontBumper||0);
  if(Number(original.rearBumper)!==Number(tuning.rearBumper))total+=Number(p.rearBumper||0);
  if(Number(original.roofIndex)!==Number(tuning.roofIndex))total+=Number(p.roof||0);
  if(Number(original.exhaustIndex)!==Number(tuning.exhaustIndex))total+=Number(p.exhaust||0);

  return total;
}

function fillSelect(id,items,value){
  const el=$(id);
  el.innerHTML=(items||[]).map(v=>`<option value="${String(v.id??v.key)}">${String(v.label)}</option>`).join('');
  if(value!==undefined&&value!==null)el.value=String(value);
}
function fillModSelect(id,items,value){
  fillSelect(id,items,value);
}
function updateRepairUi(condition){
  const c=condition||{};
  $('engineHealth').textContent=`${Number(c.enginePct??100)}%`;
  $('bodyHealth').textContent=`${Number(c.bodyPct??100)}%`;
  $('tankHealth').textContent=`${Number(c.tankPct??100)}%`;

  const notes=[];
  if(c.tyreBurst)notes.push('파손된 타이어');
  if(c.brokenWindow)notes.push('파손된 유리');
  if(Number(c.enginePct??100)<100)notes.push('엔진 손상');
  if(Number(c.bodyPct??100)<100)notes.push('차체 손상');
  if(Number(c.tankPct??100)<100)notes.push('연료탱크 손상');

  $('damageDetail').textContent=repairRequired
    ? `손상 확인: ${notes.length?notes.join(' · '):'차량 내구도 감소'}`
    : '차량 상태 정상 · 바로 튜닝할 수 있습니다.';

  $('repairBtn').disabled=!repairRequired||busy;
  $('repairBtn').textContent=repairRequired?'전체 수리':'수리 완료';
  $('repairLock').classList.toggle('hidden',!repairRequired);

  document.querySelectorAll('.tab').forEach(btn=>{
    if(btn.dataset.tab!=='repair')btn.classList.toggle('locked',repairRequired);
  });

  $('buyBtn').disabled=repairRequired||busy;
}

function setupOptions(){
  fillSelect('specialPaint',state.specialPaints,tuning.specialKey);
  fillSelect('wheelColor',state.wheelColors,tuning.wheelColor);
  fillSelect('windowTint',state.windowTints,tuning.windowTint);
  fillSelect('interiorColor',state.interiorColors,tuning.interiorColor);

  fillSelect('xenonColor',state.xenonColors,tuning.xenonColor);
  fillSelect('plateStyle',state.plateStyles,tuning.plateStyle);
  fillSelect('wheelType',state.wheelTypes,tuning.wheelType);
  fillSelect('engineAudio',state.engineAudios,tuning.engineAudio);

  const d=state.dynamicOptions||{};
  fillModSelect('hornIndex',d.horn,tuning.hornIndex);
  fillModSelect('frontBumper',d.frontBumper,tuning.frontBumper);
  fillModSelect('rearBumper',d.rearBumper,tuning.rearBumper);
  fillModSelect('roofIndex',d.roof,tuning.roofIndex);
  fillModSelect('exhaustIndex',d.exhaust,tuning.exhaustIndex);
  fillModSelect('wheelIndex',d.wheel,tuning.wheelIndex);

  const extras=d.extras||[];
  $('extrasList').innerHTML=extras.length?extras.map(v=>{
    const key=String(v.id);
    const checked=tuning.extras?.[key]?'checked':'';
    return `<label class="extra-item"><span>${String(v.label)}</span><input type="checkbox" data-extra="${key}" ${checked}></label>`;
  }).join(''):'<div class="info-box">이 차량은 사용 가능한 EXTRA가 없습니다.</div>';

  document.querySelectorAll('[data-extra]').forEach(el=>el.addEventListener('change',()=>{
    tuning.extras=tuning.extras||{};
    tuning.extras[String(el.dataset.extra)]=el.checked;
    preview();
  }));
}

function refresh(){
  $('primaryColor').value=rgbToHex(tuning.primary);
  $('secondaryColor').value=rgbToHex(tuning.secondary);
  $('tyreSmokeColor').value=rgbToHex(tuning.tyreSmoke);
  $('neonColor').value=rgbToHex(tuning.neonColor);

  $('specialPaint').value=String(tuning.specialKey||'none');
  $('wheelColor').value=String(Number(tuning.wheelColor||0));
  $('windowTint').value=String(Number(tuning.windowTint??4));
  $('interiorColor').value=String(Number(tuning.interiorColor||0));

  $('turbo').checked=!!tuning.turbo;
  $('bulletproofTyres').checked=!!tuning.bulletproofTyres;
  $('xenonEnabled').checked=!!tuning.xenonEnabled;
  $('xenonColor').value=String(Number(tuning.xenonColor||0));

  $('neonEnabled').checked=!!tuning.neonEnabled;
  $('neonLeft').checked=!!tuning.neonSides?.left;
  $('neonRight').checked=!!tuning.neonSides?.right;
  $('neonFront').checked=!!tuning.neonSides?.front;
  $('neonBack').checked=!!tuning.neonSides?.back;

  $('plateStyle').value=String(Number(tuning.plateStyle||0));
  $('wheelType').value=String(Number(tuning.wheelType||0));
  $('wheelIndex').value=String(Number(tuning.wheelIndex??-1));
  $('hornIndex').value=String(Number(tuning.hornIndex??-1));
  $('engineAudio').value=String(tuning.engineAudio||'stock');
  $('frontBumper').value=String(Number(tuning.frontBumper??-1));
  $('rearBumper').value=String(Number(tuning.rearBumper??-1));
  $('roofIndex').value=String(Number(tuning.roofIndex??-1));
  $('exhaustIndex').value=String(Number(tuning.exhaustIndex??-1));

  $('engineLevelText').textContent=levelText(tuning.engineLevel);
  $('speedLevelText').textContent=levelText(tuning.speedLevel);
  $('durabilityLevelText').textContent=levelText(tuning.durabilityLevel);
  $('brakeLevelText').textContent=levelText(tuning.brakeLevel);
  $('suspensionLevelText').textContent=levelText(tuning.suspensionLevel);
  $('transmissionLevelText').textContent=levelText(tuning.transmissionLevel);

  $('priceText').textContent=money(calcPrice());
  $('balanceText').textContent=`계좌 ${money(state?.money?.bank)} · 현금 ${money(state?.money?.cash)}`;
}

let previewTimer=null;
function preview(){
  refresh();
  if(repairRequired)return;
  clearTimeout(previewTimer);
  previewTimer=setTimeout(()=>post('preview',{tuning}),55);
}

window.addEventListener('message',e=>{
  const d=e.data||{};
  if(d.action==='open'){
    state=d.data||{};
    original=clone(state.tuning||{});
    tuning=clone(state.tuning||{});
    repairRequired=!!state.repairRequired;

    $('vehicleMeta').textContent=`${state.model||'차량'} · ${state.plate||'-'}`;
    $('repairPriceText').textContent=`전체 수리비 ${money(state.repairPrice||0)}`;

    setupOptions();
    app.classList.remove('hidden');
    updateRepairUi(state.condition);
    refresh();

    if(repairRequired){
      document.querySelectorAll('.tab').forEach(x=>x.classList.toggle('active',x.dataset.tab==='repair'));
      document.querySelectorAll('.page').forEach(x=>x.classList.toggle('active',x.dataset.page==='repair'));
    }
  }else if(d.action==='close'){
    app.classList.add('hidden');
    busy=false;
  }
});

document.querySelectorAll('.tab').forEach(btn=>btn.addEventListener('click',()=>{
  if(repairRequired&&btn.dataset.tab!=='repair')return;
  document.querySelectorAll('.tab').forEach(x=>x.classList.toggle('active',x===btn));
  document.querySelectorAll('.page').forEach(x=>x.classList.toggle('active',x.dataset.page===btn.dataset.tab));
}));

$('primaryColor').addEventListener('input',()=>{
  tuning.primary=hexToRgb($('primaryColor').value);
  tuning.primaryCustom=true;
  tuning.specialKey='none';
  preview();
});
$('secondaryColor').addEventListener('input',()=>{
  tuning.secondary=hexToRgb($('secondaryColor').value);
  tuning.secondaryCustom=true;
  preview();
});
$('specialPaint').addEventListener('change',()=>{tuning.specialKey=$('specialPaint').value;preview()});
$('wheelColor').addEventListener('change',()=>{tuning.wheelColor=Number($('wheelColor').value)||0;preview()});
$('windowTint').addEventListener('change',()=>{tuning.windowTint=Number($('windowTint').value);preview()});
$('interiorColor').addEventListener('change',()=>{tuning.interiorColor=Number($('interiorColor').value)||0;preview()});

$('turbo').addEventListener('change',()=>{tuning.turbo=$('turbo').checked;preview()});
$('bulletproofTyres').addEventListener('change',()=>{tuning.bulletproofTyres=$('bulletproofTyres').checked;preview()});

$('tyreSmokeColor').addEventListener('input',()=>{
  tuning.tyreSmoke=hexToRgb($('tyreSmokeColor').value);
  tuning.tyreSmokeEnabled=true;
  preview();
});

$('xenonEnabled').addEventListener('change',()=>{tuning.xenonEnabled=$('xenonEnabled').checked;preview()});
$('xenonColor').addEventListener('change',()=>{tuning.xenonColor=Number($('xenonColor').value)||0;tuning.xenonEnabled=true;preview()});

$('neonEnabled').addEventListener('change',()=>{tuning.neonEnabled=$('neonEnabled').checked;preview()});
$('neonColor').addEventListener('input',()=>{tuning.neonColor=hexToRgb($('neonColor').value);tuning.neonEnabled=true;preview()});

[['neonLeft','left'],['neonRight','right'],['neonFront','front'],['neonBack','back']].forEach(([id,key])=>{
  $(id).addEventListener('change',()=>{
    tuning.neonSides=tuning.neonSides||{};
    tuning.neonSides[key]=$(id).checked;
    tuning.neonEnabled=true;
    preview();
  });
});

$('hornIndex').addEventListener('change',()=>{tuning.hornIndex=Number($('hornIndex').value);preview()});
$('engineAudio').addEventListener('change',()=>{tuning.engineAudio=$('engineAudio').value;preview()});
$('plateStyle').addEventListener('change',()=>{tuning.plateStyle=Number($('plateStyle').value)||0;preview()});

$('frontBumper').addEventListener('change',()=>{tuning.frontBumper=Number($('frontBumper').value);preview()});
$('rearBumper').addEventListener('change',()=>{tuning.rearBumper=Number($('rearBumper').value);preview()});
$('roofIndex').addEventListener('change',()=>{tuning.roofIndex=Number($('roofIndex').value);preview()});
$('exhaustIndex').addEventListener('change',()=>{tuning.exhaustIndex=Number($('exhaustIndex').value);preview()});

$('wheelType').addEventListener('change',async()=>{
  tuning.wheelType=Number($('wheelType').value)||0;
  const res=await post('wheelOptions',{wheelType:tuning.wheelType});
  if(res?.ok){
    state.dynamicOptions=state.dynamicOptions||{};
    state.dynamicOptions.wheel=res.options||[];
    tuning.wheelIndex=-1;
    fillModSelect('wheelIndex',state.dynamicOptions.wheel,tuning.wheelIndex);
  }
  preview();
});
$('wheelIndex').addEventListener('change',()=>{tuning.wheelIndex=Number($('wheelIndex').value);preview()});

document.querySelectorAll('[data-minus]').forEach(btn=>btn.addEventListener('click',()=>{
  const key=btn.dataset.minus;
  tuning[key]=Math.max(0,Number(tuning[key]||0)-1);
  preview();
}));
document.querySelectorAll('[data-plus]').forEach(btn=>btn.addEventListener('click',()=>{
  const key=btn.dataset.plus;
  const map={
    engineLevel:'engine',
    speedLevel:'speed',
    durabilityLevel:'durability',
    brakeLevel:'brake',
    suspensionLevel:'suspension',
    transmissionLevel:'transmission'
  };
  const max=Number(state?.maxLevels?.[map[key]]||5);
  tuning[key]=Math.min(max,Number(tuning[key]||0)+1);
  preview();
}));

$('repairBtn').addEventListener('click',async()=>{
  if(busy||!repairRequired)return;
  busy=true;
  $('repairBtn').disabled=true;

  const res=await post('repair',{});

  busy=false;
  if(res?.ok){
    repairRequired=false;
    state.repairRequired=false;
    if(res.money)state.money=res.money;
    updateRepairUi(res.condition||{enginePct:100,bodyPct:100,tankPct:100});
    refresh();
  }else{
    $('repairBtn').disabled=false;
    alert(res?.message||'전체 수리에 실패했습니다.');
  }
});

$('resetBtn').addEventListener('click',async()=>{
  tuning=clone(original);
  await post('resetPreview',{});
  setupOptions();
  refresh();
});

$('buyBtn').addEventListener('click',async()=>{
  if(busy||repairRequired)return;

  busy=true;
  $('buyBtn').disabled=true;

  const res=await post('purchase',{tuning});

  busy=false;
  $('buyBtn').disabled=false;

  if(res?.ok){
    original=clone(res.tuning||tuning);
    tuning=clone(res.tuning||tuning);
    if(res.money)state.money=res.money;
    refresh();
  }else{
    alert(res?.message||'튜닝 적용에 실패했습니다.');
    tuning=clone(original);
    setupOptions();
    refresh();
  }
});

$('closeBtn').addEventListener('click',()=>post('close',{}));
document.addEventListener('keydown',e=>{if(e.key==='Escape')post('close',{})});
