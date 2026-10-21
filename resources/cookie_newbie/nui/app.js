const app=document.getElementById('app');
const stepsEl=document.getElementById('steps');
const titleEl=document.getElementById('title');
const whoEl=document.getElementById('who');
const progressBar=document.getElementById('progressBar');
const progressText=document.getElementById('progressText');
const completeBox=document.getElementById('completeBox');
const completeDesc=document.getElementById('completeDesc');
const claimRewardBtn=document.getElementById('claimRewardBtn');
const modal=document.getElementById('modal');
const modalTitle=document.getElementById('modalTitle');
const modalPages=document.getElementById('modalPages');
const modalDone=document.getElementById('modalDone');
const toast=document.getElementById('toast');

let state={};
let guidePages=[];
let educationPages=[];
let modalMode='';
let verifyTitle='디스코드 뉴비 인증';

const post=(name,data={})=>fetch(`https://${GetParentResourceName()}/${name}`,{
  method:'POST',
  headers:{'Content-Type':'application/json'},
  body:JSON.stringify(data)
}).then(r=>r.json()).catch(()=>({ok:false}));

const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
const done=v=>v===true;

function showToast(msg,bad=false){
  toast.textContent=msg;
  toast.className='toast'+(bad?' bad':'');
  toast.classList.remove('hidden');
  setTimeout(()=>toast.classList.add('hidden'),2800);
}

function stepCard(no,name,desc,isDone,unlocked,button,extra=''){
  return `<section class="step ${isDone?'done':''} ${!unlocked&&!isDone?'locked':''}">
    <div class="no">${isDone?'✓':no}</div>
    <div>
      <h3>${name}</h3>
      <p>${desc}</p>
      ${extra?`<p class="values">${extra}</p>`:''}
    </div>
    <button class="action ${isDone?'doneBtn':''}" data-step="${button}" ${isDone||!unlocked?'disabled':''}>
      ${isDone?'완료':button==='guide'?'가이드 보기':button==='identity'?'발급받기':button==='license'?'면허 발급':button==='education'?'교육 받기':'진행'}
    </button>
  </section>`;
}

function verifyCard(){
  const isDone=done(state.verifyDone);
  const unlocked=done(state.educationDone);
  const info=state.verifyInfo||{};
  const invite=info.invite||info.url||'';
  const channel=info.channel||'뉴비-인증';
  const length=Number(info.length||6);

  return `<section class="step verifyStep ${isDone?'done':''} ${!unlocked&&!isDone?'locked':''}">
    <div class="no">${isDone?'✓':'5'}</div>
    <div class="verifyContent">
      <h3>${esc(verifyTitle)}</h3>
      <p>디스코드에서 인증코드를 발급받은 뒤 아래에 입력하세요.</p>
      <div class="verifyGuide">
        <span><b>1</b> 쿠키서버 Discord 입장</span>
        <span><b>2</b> #${esc(channel.replace(/^#/,'') )} 에서 <strong>뉴비 인증</strong> 버튼 클릭</span>
        <span><b>3</b> 발급된 ${length}자리 코드를 입력</span>
      </div>
      ${invite?`<div class="discordLine">Discord · <span>${esc(invite)}</span></div>`:''}
      ${!isDone?`<div class="verifyInputRow">
        <input id="verifyCode" type="text" inputmode="numeric" autocomplete="off" maxlength="${length}" placeholder="${'0'.repeat(Math.min(length,6))}" ${!unlocked?'disabled':''}>
        <button id="verifySubmit" class="action" ${!unlocked?'disabled':''}>인증하기</button>
      </div>`:`<p class="verifiedText">디스코드 인증이 완료되었습니다.</p>`}
    </div>
  </section>`;
}

function render(){
  const n=[state.guideDone,state.identityDone,state.licenseDone,state.educationDone,state.verifyDone].filter(done).length;
  progressBar.style.width=`${n*20}%`;
  progressText.textContent=`${n} / 5 완료`;
  whoEl.textContent=`고번 ${state.gobun??'-'} · ${state.nickname??'-'}`;

  stepsEl.innerHTML=
    stepCard(1,'가이드 받기','쿠키서버 기본 생활 안내를 확인합니다.',done(state.guideDone),true,'guide')+
    stepCard(2,'주민번호 · 전화번호 발급','쿠키서버 전용 주민번호와 전화번호를 발급합니다.',done(state.identityDone),done(state.guideDone),'identity',state.identityDone?`${esc(state.jumin||'-')} · ${esc(state.phone||'-')}`:'')+
    stepCard(3,'운전면허 발급','신분 발급 완료 후 COOKIE 운전면허를 발급합니다.',done(state.licenseDone),done(state.identityDone),'license',state.licenseDone?`${esc(state.driverLicense||'-')} · ${esc(state.driverStatus||'정상')}`:'')+
    stepCard(4,'교육 받기','기본 도로·RP·문제 대응 교육을 확인합니다.',done(state.educationDone),done(state.licenseDone),'education')+
    verifyCard();

  completeBox.classList.toggle('hidden',!state.completed);
  if(state.completed){
    completeDesc.textContent=state.rewardClaimed
      ? `${state.rewardLabel||'뉴비 보상 키트'} 지급까지 완료되었습니다.`
      : `인증 완료! ${state.rewardLabel||'뉴비 보상 키트'}를 받아주세요.`;
    claimRewardBtn.classList.toggle('hidden',!!state.rewardClaimed);
  }

  document.querySelectorAll('[data-step]').forEach(b=>b.addEventListener('click',()=>run(b.dataset.step)));

  const verifySubmit=document.getElementById('verifySubmit');
  const verifyCode=document.getElementById('verifyCode');
  if(verifySubmit&&verifyCode){
    verifyCode.addEventListener('input',()=>{verifyCode.value=verifyCode.value.replace(/\D/g,'');});
    verifyCode.addEventListener('keydown',e=>{if(e.key==='Enter') submitVerify(verifyCode.value);});
    verifySubmit.addEventListener('click',()=>submitVerify(verifyCode.value));
  }
}

function openModal(mode,pages,title){
  modalMode=mode;
  modalTitle.textContent=title;
  modalPages.innerHTML=(pages||[]).map(p=>`<div class="page"><b>${esc(p.title)}</b><p>${esc(p.body)}</p></div>`).join('');
  modalDone.textContent=mode==='guide'?'가이드 확인 완료':'교육 확인 완료';
  modal.classList.remove('hidden');
}

async function submitVerify(code){
  const trimmed=String(code||'').replace(/\s/g,'');
  if(!trimmed){showToast('인증코드를 입력해주세요.',true);return;}
  const btn=document.getElementById('verifySubmit');
  if(btn) btn.disabled=true;
  const r=await post('submitVerifyCode',{code:trimmed});
  if(btn) btn.disabled=false;
  if(r&&r.ok!==false){
    state=r;
    render();
    showToast(r.message||'인증이 완료되었습니다.');
  }else{
    showToast((r&&r.reason)||'인증에 실패했습니다.',true);
    if(r&&r.state){state=r.state;render();}
  }
}

async function run(which){
  if(which==='guide'){openModal('guide',guidePages,'뉴비 가이드');return;}
  if(which==='education'){openModal('education',educationPages,'기본 교육');return;}
  const map={identity:'issueIdentity',license:'issueLicense'};
  const r=await post(map[which]);
  if(r&&r.ok!==false){state=r;render();showToast(r.message||'처리되었습니다.');}
  else{showToast((r&&r.reason)||'처리에 실패했습니다.',true);if(r&&r.state){state=r.state;render();}}
}

modalDone.addEventListener('click',async()=>{
  const cb=modalMode==='guide'?'guideDone':'educationDone';
  modalDone.disabled=true;
  const r=await post(cb);
  modalDone.disabled=false;
  if(r&&r.ok!==false){state=r;render();modal.classList.add('hidden');showToast(r.message||'완료했습니다.');}
  else{showToast((r&&r.reason)||'처리에 실패했습니다.',true);if(r&&r.state){state=r.state;render();}}
});

document.getElementById('modalClose').onclick=()=>modal.classList.add('hidden');
document.getElementById('close').onclick=()=>post('close');
claimRewardBtn.onclick=async()=>{
  claimRewardBtn.disabled=true;
  const r=await post('claimReward');
  claimRewardBtn.disabled=false;
  if(r&&r.ok!==false){state=r;render();showToast(r.message||'보상이 지급되었습니다.');}
  else{showToast((r&&r.reason)||'보상 지급에 실패했습니다.',true);if(r&&r.state){state=r.state;render();}}
};

document.addEventListener('keydown',e=>{
  if(e.key==='Escape'){
    if(!modal.classList.contains('hidden')) modal.classList.add('hidden');
    else post('close');
  }
});

window.addEventListener('message',e=>{
  const m=e.data||{};
  if(m.action==='open'){
    state=m.data||{};
    guidePages=m.guidePages||[];
    educationPages=m.educationPages||[];
    verifyTitle=m.verifyTitle||'디스코드 뉴비 인증';
    titleEl.textContent=m.title||'뉴비 시청';
    app.classList.remove('hidden');
    render();
  }
  if(m.action==='close') app.classList.add('hidden');
});
