const phone = document.getElementById('phone');
const homeView = document.getElementById('homeView');
const phoneView = document.getElementById('phoneView');
const callView = document.getElementById('callView');
const ringtone = document.getElementById('ringtone');
const ringback = document.getElementById('ringback');

let dial = '';
let myNumber = '';
let historyRows = [];
let contactsRows = [];
let messageConversations = [];
let messageUnread = 0;
let activeConversation = null;
let messagePhotoSelectedId = 0;
let taxiPreview = null;
let taxiState = {state:'idle',pricing:null};
let mechanicVehicle = null;
let mechanicState = {state:'idle',pricing:null};
let dispatchOverview = {targets:[],ownCalls:[],assignedCalls:[]};
let dispatchSelectedTarget = null;
let dispatchCloseCallId = 0;
let dispatchIncomingRows = {};
let dispatchNoticeTimer = null;
let bankState = {balance:0,phone:'',history:[]};
let bankNearbyRows = [];
let bankNearbyTarget = null;
let bankPendingTransfer = null;
let phoneSettings = {accent:'#F0C85B',accent2:'#C69A2B',wallpaper:'cookie-bakery',customWallpaper:'',blur:0,dim:18,glass:46};
const LOCAL_WALLPAPER_KEY='cookie_phone_wallpaper_local_v1';

let settingsDraft = {...phoneSettings};
let profile = {name:'',avatar:''};
let activeContactId = 0;
let profileDraftAvatar = '';
let profileDraftPhotoId = 0;
let galleryRows = [];
let activeGalleryId = 0;
let activeMessagePhotoId = 0;
let contactOffer = null;
let call = null;
let callTimerInterval = null;
let toastTimer = null;

const post = (endpoint, data={}) =>
  fetch(`https://${GetParentResourceName()}/${endpoint}`, {
    method:'POST',
    headers:{'Content-Type':'application/json; charset=UTF-8'},
    body:JSON.stringify(data)
  }).then(r=>r.json()).catch(()=>({ok:false}));

function pad(v){ return String(v).padStart(2,'0'); }

function updateClock(){
  const d=new Date();
  const hh=pad(d.getHours()), mm=pad(d.getMinutes());
  document.getElementById('statusClock').textContent=`${hh}:${mm}`;
  document.getElementById('homeClock').textContent=`${hh}:${mm}`;
  const days=['일요일','월요일','화요일','수요일','목요일','금요일','토요일'];
  document.getElementById('homeDate').textContent=`${d.getMonth()+1}월 ${d.getDate()}일 ${days[d.getDay()]}`;
}
updateClock();
setInterval(updateClock,10000);

function escapeHtml(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));}

function digits(value){ return String(value||'').replace(/\D/g,'').slice(0,16); }

function formatPhone(value){
  const n=digits(value);
  if(!n) return '';
  if(n.length===10) return `${n.slice(0,3)} ${n.slice(3,6)} ${n.slice(6)}`;
  if(n.length===11) return `${n.slice(0,3)} ${n.slice(3,7)} ${n.slice(7)}`;
  return n.replace(/(.{3})/g,'$1 ').trim();
}

function initials(name, fallback='?'){
  const text=String(name||'').trim();
  if(!text)return fallback;
  const parts=text.split(/\s+/).filter(Boolean);
  if(parts.length>=2)return (parts[0][0]+parts[parts.length-1][0]).toUpperCase();
  return text.slice(0,2).toUpperCase();
}

function setAvatar(el, avatar, name, fallback='?'){
  if(!el)return;
  const url=String(avatar||'');
  if(url.startsWith('data:image/')){
    el.style.backgroundImage=`url("${url}")`;
    el.classList.add('has-photo');
    el.textContent='';
  }else{
    el.style.backgroundImage='';
    el.classList.remove('has-photo');
    el.textContent=initials(name,fallback);
  }
}

function contactByNumber(number){
  const n=digits(number);
  return contactsRows.find(c=>digits(c.phone)===n)||null;
}

function displayNameForNumber(number){
  const c=contactByNumber(number);
  return c&&c.name?c.name:formatPhone(number);
}


function resetHomeLauncherIfNeeded(name){
  if(name==='home'){
    const grid=document.getElementById('homeAppGrid');
    if(grid && grid.scrollTop < 4) grid.scrollTop=0;
  }
}

function setView(name){
  homeView.classList.toggle('active',name==='home');
  phoneView.classList.toggle('active',name==='phone');
  const cv=document.getElementById('contactsView');
  if(cv)cv.classList.toggle('active',name==='contacts');
  const mv=document.getElementById('messagesView');
  if(mv)mv.classList.toggle('active',name==='messages');
  const convo=document.getElementById('conversationView');
  if(convo)convo.classList.toggle('active',name==='conversation');
  const tv=document.getElementById('taxiView');
  if(tv)tv.classList.toggle('active',name==='taxi');
  const rv=document.getElementById('mechanicView');
  if(rv)rv.classList.toggle('active',name==='mechanic');
  const sv=document.getElementById('settingsView');
  if(sv)sv.classList.toggle('active',name==='settings');
  const bv=document.getElementById('bankView');
  if(bv)bv.classList.toggle('active',name==='bank');
  const gv=document.getElementById('galleryView');
  if(gv)gv.classList.toggle('active',name==='gallery');
  const dv=document.getElementById('dispatchView');
  if(dv)dv.classList.toggle('active',name==='dispatch');
  const mapv=document.getElementById('mapView');
  if(mapv)mapv.classList.toggle('active',name==='map');
  resetHomeLauncherIfNeeded(name);
}

function showToast(message,error=false){
  const el=document.getElementById('toast');
  el.textContent=message||'';
  el.classList.toggle('error',!!error);
  el.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer=setTimeout(()=>el.classList.remove('show'),2400);
}

function safePlay(audio){
  try{
    audio.currentTime=0;
    audio.volume=.34;
    const p=audio.play();
    if(p&&p.catch)p.catch(()=>{});
  }catch(e){}
}
function stopAudio(audio){
  try{audio.pause();audio.currentTime=0;}catch(e){}
}
function stopCallAudio(){ stopAudio(ringtone); stopAudio(ringback); }

function updateDial(){
  document.getElementById('dialNumber').textContent=formatPhone(dial);
  document.getElementById('dialHint').textContent=dial?'입력한 번호':'전화번호 입력';
}

function durationText(sec){
  sec=Math.max(0,Number(sec)||0);
  return `${pad(Math.floor(sec/60))}:${pad(sec%60)}`;
}

function historyStatus(row){
  const s=row.status;
  if(s==='answered') return row.direction==='outgoing'?'발신 통화':'수신 통화';
  if(s==='missed') return row.direction==='outgoing'?'응답 없음':'부재중 전화';
  if(s==='rejected') return row.direction==='outgoing'?'수신 거절':'거절한 전화';
  if(s==='cancelled') return '취소한 전화';
  if(s==='offline') return '상대방 오프라인';
  if(s==='invalid') return '없는 번호';
  if(s==='disconnected') return '연결 종료';
  if(s==='voice_error') return '음성 연결 실패';
  return '통화 기록';
}

function relativeTime(ts){
  const now=Math.floor(Date.now()/1000);
  const diff=Math.max(0,now-(Number(ts)||now));
  if(diff<60)return '방금';
  if(diff<3600)return `${Math.floor(diff/60)}분 전`;
  if(diff<86400)return `${Math.floor(diff/3600)}시간 전`;
  if(diff<604800)return `${Math.floor(diff/86400)}일 전`;
  const d=new Date((Number(ts)||0)*1000);
  return `${d.getMonth()+1}/${d.getDate()}`;
}

function galleryById(id){ return galleryRows.find(row=>Number(row.id)===Number(id))||null; }
function galleryDate(ts){
  const d=new Date((Number(ts)||0)*1000);
  if(!Number(ts))return '촬영 시간 없음';
  return `${d.getFullYear()}.${pad(d.getMonth()+1)}.${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
function renderGallery(){
  const grid=document.getElementById('galleryGrid'), count=document.getElementById('galleryCount');
  if(count)count.textContent=`${galleryRows.length}장`;
  if(!grid)return;
  if(!galleryRows.length){grid.innerHTML='<div class="gallery-empty"><b>아직 사진이 없습니다.</b><small>카메라 앱을 열어 첫 사진을 찍어보세요.</small></div>';return;}
  grid.innerHTML=galleryRows.map(row=>`<button class="gallery-tile ${row.orientation==='portrait'?'portrait':''}" type="button" data-gallery-id="${Number(row.id)||0}"><img src="${row.image}" alt="촬영 사진"><span>${escapeHtml(galleryDate(row.createdAt))} · ${row.cameraMode==='front'?'전면':'후면'} ${Number(row.zoom||1).toFixed(1)}×</span></button>`).join('');
  grid.querySelectorAll('[data-gallery-id]').forEach(btn=>btn.addEventListener('click',()=>openGalleryPhoto(Number(btn.dataset.galleryId))));
}
function renderProfileGallery(){
  const grid=document.getElementById('profileGalleryGrid'); if(!grid)return;
  if(!galleryRows.length){grid.innerHTML='<div class="gallery-empty"><b>선택할 사진이 없습니다.</b><small>카메라 앱에서 사진을 먼저 촬영하세요.</small></div>';return;}
  grid.innerHTML=galleryRows.map(row=>`<button class="gallery-tile ${row.orientation==='portrait'?'portrait':''} ${Number(row.id)===Number(profileDraftPhotoId)?'selected':''}" type="button" data-profile-photo="${Number(row.id)||0}"><img src="${row.image}" alt="프로필 후보"><span>${escapeHtml(galleryDate(row.createdAt))}</span></button>`).join('');
  grid.querySelectorAll('[data-profile-photo]').forEach(btn=>btn.addEventListener('click',()=>{
    const row=galleryById(Number(btn.dataset.profilePhoto)); if(!row)return;
    profileDraftPhotoId=Number(row.id)||0; profileDraftAvatar=row.image||'';
    setAvatar(document.getElementById('profilePhotoPreview'),profileDraftAvatar,document.getElementById('profileNameInput').value,'ME');
    closeModal('profileGalleryModal'); showToast('프로필 사진을 선택했습니다. 저장을 눌러 적용하세요.');
  }));
}
function openGalleryPhoto(id){
  const row=galleryById(id); if(!row)return; activeGalleryId=Number(row.id)||0; activeMessagePhotoId=0;
  const del=document.getElementById('galleryPhotoDelete'); if(del)del.classList.remove('hidden');
  const save=document.getElementById('galleryPhotoSave'); if(save)save.classList.add('hidden');
  const img=document.getElementById('galleryPhotoImage'); if(img)img.src=row.image||'';
  const frame=document.querySelector('#galleryPhotoModal .gallery-photo-frame'); if(frame){frame.classList.toggle('portrait',row.orientation==='portrait');frame.classList.toggle('landscape',row.orientation!=='portrait');}
  const date=document.getElementById('galleryPhotoDate'); if(date)date.textContent=galleryDate(row.createdAt);
  const lens=document.getElementById('galleryPhotoLens'); if(lens)lens.textContent=`${row.cameraMode==='front'?'전면':'후면'} · ${row.orientation==='portrait'?'세로':'가로'} · ${Number(row.zoom||1).toFixed(1)}×`;
  openModal('galleryPhotoModal');
}
function requestGallery(){ return post('phoneGalleryRefresh'); }

function renderHistory(){
  const list=document.getElementById('recentList');
  if(!historyRows.length){
    list.innerHTML='<div class="recent-empty">아직 통화 기록이 없습니다.<br>키패드 또는 연락처에서 첫 통화를 시작하세요.</div>';
    return;
  }

  list.innerHTML=historyRows.map(row=>{
    const missed=['missed','offline','invalid','rejected','unavailable'].includes(row.status);
    const arrow=row.direction==='outgoing'
      ? '<path d="M7 17L17 7m-7 0h7v7"/>'
      : '<path d="M17 7L7 17m7 0H7v-7"/>';
    const dur=row.duration>0?durationText(row.duration):'';
    const contact=contactByNumber(row.number);
    const mainName=contact&&contact.name?contact.name:formatPhone(row.number)||'알 수 없는 번호';
    const sub=contact?`${historyStatus(row)} · ${formatPhone(row.number)}`:historyStatus(row);
    return `<button class="recent-row" type="button" data-number="${digits(row.number)}">
      <span class="recent-symbol ${missed?'missed':''}">
        <svg viewBox="0 0 24 24">${arrow}</svg>
      </span>
      <span class="recent-info">
        <b>${escapeHtml(mainName)}</b>
        <small>${escapeHtml(sub)}</small>
      </span>
      <span class="recent-meta">
        <b>${relativeTime(row.startedAt)}</b>
        <small>${dur}</small>
      </span>
    </button>`;
  }).join('');

  list.querySelectorAll('.recent-row').forEach(btn=>{
    btn.addEventListener('click',()=>{
      dial=digits(btn.dataset.number);
      updateDial();
      switchTab('keypad');
    });
  });
}
function switchTab(name){
  document.querySelectorAll('.tab').forEach(b=>b.classList.toggle('active',b.dataset.tab===name));
  document.getElementById('keypadPane').classList.toggle('active',name==='keypad');
  document.getElementById('recentPane').classList.toggle('active',name==='recent');
}

function callReasonText(reason){
  return ({
    missed:'응답이 없습니다.',
    rejected:'상대방이 전화를 거절했습니다.',
    cancelled:'전화가 취소되었습니다.',
    answered:'통화가 종료되었습니다.',
    disconnected:'상대방과 연결이 끊겼습니다.',
    offline:'상대방이 현재 오프라인입니다.',
    invalid:'존재하지 않는 전화번호입니다.',
    busy:'상대방이 통화 중입니다.',
    voice_error:'음성 연결에 실패했습니다.',
    unavailable:'상대방에게 연결할 수 없습니다.'
  })[reason]||'통화가 종료되었습니다.';
}

function stopCallTimer(){
  clearInterval(callTimerInterval);
  callTimerInterval=null;
}

function startCallTimer(answeredAt){
  stopCallTimer();
  const render=()=>{
    const now=Math.floor(Date.now()/1000);
    document.getElementById('callTimer').textContent=durationText(now-(Number(answeredAt)||now));
  };
  render();
  callTimerInterval=setInterval(render,1000);
}

function renderCall(){
  if(!call){
    callView.classList.remove('active');
    stopCallTimer();
    stopCallAudio();
    return;
  }

  callView.classList.add('active');
  const saved=contactByNumber(call.number);
  document.getElementById('callNumber').textContent=saved&&saved.name?saved.name:(formatPhone(call.number)||'알 수 없는 번호');
  document.getElementById('callStateText').dataset.number=formatPhone(call.number)||'';
  setAvatar(document.getElementById('callerAvatar'),saved&&saved.avatar,saved&&saved.name,digits(call.number).slice(-4)||'CALL');
  const incoming=document.getElementById('incomingActions');
  const single=document.getElementById('singleCallAction');

  incoming.classList.add('hidden');
  single.classList.add('hidden');
  stopCallTimer();
  stopCallAudio();

  if(call.state==='incoming'){
    document.getElementById('callKicker').textContent='수신 전화';
    document.getElementById('callStateText').textContent='전화가 걸려왔습니다';
    document.getElementById('callTimer').textContent='수신 중';
    incoming.classList.remove('hidden');
    safePlay(ringtone);
  }else if(call.state==='outgoing'){
    document.getElementById('callKicker').textContent='발신 전화';
    document.getElementById('callStateText').textContent='상대방을 연결하는 중';
    document.getElementById('callTimer').textContent='연결 중';
    single.classList.remove('hidden');
    safePlay(ringback);
  }else if(call.state==='active'){
    document.getElementById('callKicker').textContent='통화 중';
    document.getElementById('callStateText').textContent='음성 통화 연결됨';
    single.classList.remove('hidden');
    startCallTimer(call.answeredAt);
  }
}

document.querySelector('[data-app="phone"]').addEventListener('click',()=>setView('phone'));
document.querySelector('[data-app="contacts"]')?.addEventListener('click',()=>setView('contacts'));
document.querySelector('[data-app="messages"]')?.addEventListener('click',()=>{
  setView('messages');
  post('phoneMessagesRefresh');
});
document.querySelector('[data-app="dispatch"]')?.addEventListener('click',()=>{
  setView('dispatch');
  loadDispatchOverview();
});
document.querySelector('[data-app="bank"]')?.addEventListener('click',()=>{
  setView('bank');
  post('phoneBankInfo');
});
document.querySelector('[data-app="camera"]')?.addEventListener('click',async()=>{
  await post('phoneCameraOpen');
});
document.querySelector('[data-app="gallery"]')?.addEventListener('click',()=>{
  setView('gallery');
  const grid=document.getElementById('galleryGrid'); if(grid)grid.innerHTML='<div class="gallery-empty">사진을 불러오는 중...</div>';
  requestGallery();
});
document.querySelector('[data-app="settings"]')?.addEventListener('click',()=>{
  settingsDraft={...phoneSettings};
  syncSettingsControls();
  applyTheme(settingsDraft,true);
  setView('settings');
  post('phoneSettingsRefresh');
});

let phoneMapRows=[];
function renderPhoneMap(){
  const list=document.getElementById('mapList'); if(!list)return;
  const q=(document.getElementById('mapSearch')?.value||'').trim().toLowerCase();
  const rows=phoneMapRows.filter(r=>!q||`${r.label} ${r.category}`.toLowerCase().includes(q));
  list.innerHTML=rows.length?rows.map(r=>`<button class="map-place" type="button" data-map-id="${escapeHtml(r.id)}"><span><b>${escapeHtml(r.label)}</b><small>${escapeHtml(r.category||'주요 장소')}</small></span><em>GPS</em></button>`).join(''):'<div class="gallery-empty"><b>검색 결과가 없습니다.</b></div>';
  list.querySelectorAll('[data-map-id]').forEach(btn=>btn.addEventListener('click',async()=>{
    const r=await post('phoneMapWaypoint',{id:btn.dataset.mapId});
    if(r?.ok)showToast(`${r.label||'장소'} GPS를 설정했습니다.`);
    else showToast('GPS 설정에 실패했습니다.',true);
  }));
}
async function openPhoneMap(){
  const r=await post('phoneOpenGtaMap',{});
  if(r?.ok===false) showToast('지도를 열 수 없습니다.',true);
}
document.querySelector('[data-app="map"]')?.addEventListener('click',openPhoneMap);
document.getElementById('mapBack')?.addEventListener('click',()=>setView('home'));
document.getElementById('mapSearch')?.addEventListener('input',renderPhoneMap);

document.getElementById('phoneBack').addEventListener('click',()=>setView('home'));
document.getElementById('dispatchBack')?.addEventListener('click',()=>setView('home'));
document.getElementById('messagesBack')?.addEventListener('click',()=>setView('home'));
document.getElementById('taxiBack')?.addEventListener('click',()=>setView('home'));
document.getElementById('mechanicBack')?.addEventListener('click',()=>setView('home'));
document.getElementById('bankBack')?.addEventListener('click',()=>setView('home'));
document.getElementById('galleryBack')?.addEventListener('click',()=>setView('home'));
document.getElementById('galleryRefresh')?.addEventListener('click',requestGallery);
document.getElementById('galleryPhotoDelete')?.addEventListener('click',()=>{
  if(!activeGalleryId)return; post('phoneGalleryDelete',{id:activeGalleryId}); closeModal('galleryPhotoModal'); activeGalleryId=0;
});
document.getElementById('galleryPhotoSave')?.addEventListener('click',()=>{
  if(!activeMessagePhotoId)return;
  post('phoneSaveMessagePhoto',{messageId:activeMessagePhotoId});
  closeModal('galleryPhotoModal');
  activeMessagePhotoId=0;
});
document.getElementById('settingsBack')?.addEventListener('click',()=>{
  settingsDraft={...phoneSettings};
  applyTheme(phoneSettings,false);
  setView('home');
});
document.getElementById('contactsBack')?.addEventListener('click',()=>setView('home'));
document.getElementById('refreshHistory').addEventListener('click',()=>post('phoneRefresh'));

document.querySelectorAll('.tab').forEach(btn=>btn.addEventListener('click',()=>switchTab(btn.dataset.tab)));

document.querySelectorAll('#keypad button').forEach(btn=>{
  btn.addEventListener('click',()=>{
    const k=btn.dataset.key;
    if(!k)return;
    if(dial.length>=16)return;
    dial+=k.replace(/\D/g,'');
    updateDial();
  });
});

document.getElementById('dialDelete').addEventListener('click',()=>{
  dial=dial.slice(0,-1);
  updateDial();
});

document.getElementById('dialCall').addEventListener('click',()=>{
  const number=digits(dial);
  if(number.length<4){showToast('전화번호를 입력하세요.',true);return;}
  post('phoneDial',{number});
});

document.getElementById('acceptCall').addEventListener('click',()=>{
  if(call)post('phoneAccept',{callId:call.id});
});
document.getElementById('declineCall').addEventListener('click',()=>{
  if(call)post('phoneDecline',{callId:call.id});
});
document.getElementById('endCall').addEventListener('click',()=>{
  if(!call)return;
  if(call.state==='outgoing')post('phoneCancel',{callId:call.id});
  else post('phoneHangup',{callId:call.id});
});

function isTextEditingTarget(target){
  if(!target) return false;
  const tag=String(target.tagName||'').toLowerCase();
  return tag==='input'||tag==='textarea'||tag==='select'||target.isContentEditable===true;
}

function getOpenPhoneModal(){
  return [...document.querySelectorAll('.phone-modal')].find(m=>!m.classList.contains('hidden'))||null;
}

window.addEventListener('keydown',e=>{
  const editing=isTextEditingTarget(e.target);
  const modal=getOpenPhoneModal();

  // 연락처/프로필 이름을 입력할 때 P 키는 한글 입력에도 사용됩니다.
  // 입력칸에서는 절대로 휴대전화를 닫지 않고 정상 문자 입력으로 넘깁니다.
  if(e.code==='KeyP'){
    if(editing||modal) return;
    e.preventDefault();
    post('phoneClose');
    return;
  }

  // ESC는 편집창이 떠 있으면 휴대전화 전체가 아니라 편집창만 닫습니다.
  if(e.key==='Escape'){
    e.preventDefault();

    if(modal){
      modal.classList.add('hidden');
      return;
    }

    if(editing){
      e.target.blur();
      return;
    }

    post('phoneClose');
  }
});





function validHex(v,fallback){
  const s=String(v||'').toUpperCase();
  return /^#[0-9A-F]{6}$/.test(s)?s:fallback;
}
function hexRgb(hex){
  const h=validHex(hex,'#F0C85B').slice(1);
  return `${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)}`;
}
const wallpaperLibrary={
  'solid-black':{key:'solid-black',light:false},
  'solid-white':{key:'solid-white',light:true},
  'starry-night':{key:'starry-night',light:false},
  'caramel-gloss':{key:'caramel-gloss',light:true},
  'pink-flower':{key:'pink-flower',light:true},
  'cookie-bakery':{key:'cookie-bakery',light:true},
  'mint-glass':{key:'mint-glass',light:true},
  'lavender-aurora':{key:'lavender-aurora',light:false}
};
function wallpaperImage(id){
  const item=wallpaperLibrary[id]||wallpaperLibrary['cookie-bakery'];
  return String((window.COOKIE_WALLPAPERS||{})[item.key]||'');
}
function paintWallpaperCards(){
  document.querySelectorAll('#wallpaperGrid [data-wallpaper]').forEach(btn=>{
    const image=wallpaperImage(btn.dataset.wallpaper);
    const thumb=btn.querySelector('.wallpaper-card-image');
    if(thumb&&image){
      thumb.style.backgroundImage=`url("${image}")`;
      thumb.style.backgroundSize='cover';
      thumb.style.backgroundPosition='center';
      thumb.style.backgroundRepeat='no-repeat';
    }
  });
}
function clampTheme(v,min,max,fallback){const n=Number(v);return Number.isFinite(n)?Math.max(min,Math.min(max,Math.round(n))):fallback;}
function normalizeSettings(raw={}){
  const wallpaper=String(raw.wallpaper||'cookie-bakery');
  return {
    accent:validHex(raw.accent,'#F0C85B'),
    accent2:validHex(raw.accent2,'#C69A2B'),
    wallpaper:Object.prototype.hasOwnProperty.call(wallpaperLibrary,wallpaper)?wallpaper:'cookie-bakery',
    customWallpaper:'',
    blur:clampTheme(raw.blur,0,24,0),
    dim:clampTheme(raw.dim,0,55,18),
    glass:clampTheme(raw.glass,20,85,46)
  };
}
function activeWallpaperCss(settings){
  const image=wallpaperImage(settings.wallpaper);
  return image?`url("${image}")`:'linear-gradient(#111,#111)';
}
function updateHomeContrast(settings){
  const screen=document.querySelector('.screen');
  if(!screen)return;
  const item=wallpaperLibrary[settings.wallpaper]||wallpaperLibrary['cookie-bakery'];
  screen.classList.toggle('home-light-wallpaper',!!item.light);
}
function applyTheme(raw,previewOnly=false){
  const s=normalizeSettings(raw);
  const root=document.documentElement;
  root.style.setProperty('--phone-accent',s.accent);
  root.style.setProperty('--phone-accent2',s.accent2);
  root.style.setProperty('--phone-accent-rgb',hexRgb(s.accent));
  root.style.setProperty('--phone-accent2-rgb',hexRgb(s.accent2));
  root.style.setProperty('--phone-dim',String(s.dim/100));
  root.style.setProperty('--phone-blur',`${s.blur}px`);
  root.style.setProperty('--phone-glass',String(s.glass/100));
  root.style.setProperty('--phone-wallpaper',activeWallpaperCss(s));
  updateHomeContrast(s);
  updateThemePreview(s);
}
function updateThemePreview(s){
  const preview=document.getElementById('themePreview');
  if(!preview)return;
  const image=wallpaperImage(s.wallpaper);
  preview.className='theme-preview';
  preview.style.backgroundImage=image?`url("${image}")`:'linear-gradient(#111,#111)';
  preview.style.backgroundSize='cover';
  preview.style.backgroundPosition='center';
  preview.style.backgroundRepeat='no-repeat';
}
function syncSettingsControls(){
  const s=normalizeSettings(settingsDraft);
  document.getElementById('accentPicker').value=s.accent;
  document.getElementById('accent2Picker').value=s.accent2;
  document.getElementById('accentHex').textContent=s.accent;
  document.getElementById('accent2Hex').textContent=s.accent2;
  document.getElementById('dimRange').value=s.dim;
  document.getElementById('blurRange').value=s.blur;
  document.getElementById('glassRange').value=s.glass;
  document.getElementById('dimValue').textContent=`${s.dim}%`;
  document.getElementById('blurValue').textContent=`${s.blur}px`;
  document.getElementById('glassValue').textContent=`${s.glass}%`;
  document.querySelectorAll('#wallpaperGrid [data-wallpaper]').forEach(b=>b.classList.toggle('selected',b.dataset.wallpaper===s.wallpaper));
  document.querySelectorAll('#accentPresets [data-accent]').forEach(b=>b.classList.toggle('selected',b.dataset.accent.toUpperCase()===s.accent&&b.dataset.accent2.toUpperCase()===s.accent2));
}
function previewSettingsChange(){
  settingsDraft=normalizeSettings(settingsDraft);
  syncSettingsControls();
  applyTheme(settingsDraft,true);
}

document.querySelectorAll('#accentPresets [data-accent]').forEach(btn=>btn.addEventListener('click',()=>{
  settingsDraft.accent=btn.dataset.accent;
  settingsDraft.accent2=btn.dataset.accent2;
  previewSettingsChange();
}));
document.getElementById('accentPicker')?.addEventListener('input',e=>{settingsDraft.accent=e.target.value;previewSettingsChange();});
document.getElementById('accent2Picker')?.addEventListener('input',e=>{settingsDraft.accent2=e.target.value;previewSettingsChange();});

document.querySelectorAll('#wallpaperGrid [data-wallpaper]').forEach(btn=>btn.addEventListener('click',()=>{
  settingsDraft.wallpaper=btn.dataset.wallpaper;
  previewSettingsChange();
  showToast(`${btn.querySelector('.wallpaper-card-name')?.textContent||'배경화면'} 미리보기`,false);
}));

paintWallpaperCards();

[['dimRange','dim'],['blurRange','blur'],['glassRange','glass']].forEach(([id,key])=>document.getElementById(id)?.addEventListener('input',e=>{settingsDraft[key]=Number(e.target.value);previewSettingsChange();}));
document.getElementById('settingsSave')?.addEventListener('click',()=>{
  settingsDraft=normalizeSettings(settingsDraft);
  phoneSettings={...settingsDraft};
  applyTheme(phoneSettings,false);

  // custom local wallpaper is already saved in NUI localStorage.
  // Never send base64 through a normal FiveM NUI/net event.
  post('phoneSettingsSave',{...phoneSettings,customWallpaper:''});
});
document.getElementById('settingsReset')?.addEventListener('click',()=>post('phoneSettingsReset'));


function bankMoney(v){
  const n=Math.max(0,Math.floor(Number(v)||0));
  return `${n.toLocaleString('ko-KR')}원`;
}
function bankInputNumber(value){
  return Math.max(0,Math.floor(Number(String(value||'').replace(/\D/g,''))||0));
}
function bankSetAmountInput(id,value){
  const el=document.getElementById(id);
  if(el)el.value=bankInputNumber(value).toLocaleString('ko-KR');
}
function bankTime(ts){
  const d=new Date((Number(ts)||0)*1000);
  const now=new Date();
  if(!ts)return '';
  if(d.toDateString()===now.toDateString())return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  return `${d.getMonth()+1}/${d.getDate()}`;
}
function bankTargetName(phone){
  const c=contactByNumber(phone);
  return c?.name||formatPhone(phone)||'알 수 없는 번호';
}
function renderBank(){
  document.getElementById('bankBalance').textContent=bankMoney(bankState.balance);
  document.getElementById('bankMyPhone').textContent=formatPhone(bankState.phone||myNumber)||'-';

  const list=document.getElementById('bankHistory');
  const rows=Array.isArray(bankState.history)?bankState.history:[];
  if(!rows.length){
    list.innerHTML='<div class="bank-history-empty">아직 휴대전화 송금 내역이 없습니다.<br>전화번호 또는 근처 송금으로 첫 거래를 시작하세요.</div>';
    return;
  }

  list.innerHTML=rows.map(row=>{
    const incoming=row.direction==='incoming';
    const name=bankTargetName(row.phone);
    const memo=row.memo?` · ${row.memo}`:'';
    const mode=row.mode==='nearby'?'근처 송금':'전화번호 송금';
    return `<div class="bank-history-row ${incoming?'incoming':'outgoing'}">
      <span class="bank-history-icon">
        <svg viewBox="0 0 24 24"><path d="${incoming?'M7 7l10 10m-7 0h7v-7':'M17 17L7 7m7 0H7v7'}"/></svg>
      </span>
      <span class="bank-history-info">
        <b>${escapeHtml(name)}</b>
        <small>${escapeHtml(mode+memo)}</small>
      </span>
      <span class="bank-history-money">
        <b>${incoming?'+':'-'}${bankMoney(row.amount)}</b>
        <small>${bankTime(row.createdAt)}</small>
      </span>
    </div>`;
  }).join('');
}

function renderBankContactHints(){
  const box=document.getElementById('bankContactHints');
  const q=String(document.getElementById('bankPhoneInput')?.value||'').trim().toLowerCase();
  const rows=contactsRows.filter(c=>{
    if(!q)return c.favorite;
    return String(c.name||'').toLowerCase().includes(q)||digits(c.phone).includes(digits(q));
  }).slice(0,6);

  if(!rows.length){box.innerHTML='';return;}
  box.innerHTML=rows.map(c=>`<button class="bank-contact-hint" type="button" data-bank-contact="${digits(c.phone)}">
    <b>${escapeHtml(c.name||formatPhone(c.phone))}</b><small>${escapeHtml(formatPhone(c.phone))}</small>
  </button>`).join('');

  box.querySelectorAll('[data-bank-contact]').forEach(btn=>btn.addEventListener('click',()=>{
    document.getElementById('bankPhoneInput').value=formatPhone(btn.dataset.bankContact);
    renderBankContactHints();
  }));
}

function openBankConfirm(payload){
  bankPendingTransfer=payload;
  const phone=payload.phone||payload.targetPhone||'';
  const name=payload.name||bankTargetName(phone);
  document.getElementById('bankConfirmName').textContent=name||'수신자';
  document.getElementById('bankConfirmPhone').textContent=formatPhone(phone)||'근처 사용자';
  document.getElementById('bankConfirmAmount').textContent=bankMoney(payload.amount);
  document.getElementById('bankConfirmMemo').textContent=payload.memo?`메모 · ${payload.memo}`:'';
  openModal('bankConfirmModal');
}

function renderBankNearby(rows){
  bankNearbyRows=Array.isArray(rows)?rows:[];
  const list=document.getElementById('bankNearbyList');
  if(!bankNearbyRows.length){
    list.innerHTML='<div class="sheet-loading">4m 안에 휴대전화를 켠 사용자가 없습니다.</div>';
    return;
  }

  list.innerHTML=bankNearbyRows.map(r=>`
    <div class="bank-nearby-row">
      <span class="contact-avatar bank-near-avatar" data-sid="${r.serverId}">${escapeHtml(initials(r.name,'?'))}</span>
      <span class="bank-nearby-info"><b>${escapeHtml(r.name||('사용자 #'+r.serverId))}</b><small>${escapeHtml(formatPhone(r.phone))} · ${Number(r.distance||0).toFixed(1)}m</small></span>
      <button class="bank-nearby-send" type="button" data-bank-near="${r.serverId}">송금</button>
    </div>`).join('');

  bankNearbyRows.forEach(r=>{
    setAvatar(list.querySelector(`.bank-near-avatar[data-sid="${r.serverId}"]`),r.avatar,r.name,'?');
  });

  list.querySelectorAll('[data-bank-near]').forEach(btn=>btn.addEventListener('click',()=>{
    const target=bankNearbyRows.find(r=>Number(r.serverId)===Number(btn.dataset.bankNear));
    if(!target)return;
    bankNearbyTarget=target;
    document.getElementById('bankNearbyName').textContent=target.name||('사용자 #'+target.serverId);
    document.getElementById('bankNearbyPhone').textContent=formatPhone(target.phone)||'-';
    setAvatar(document.getElementById('bankNearbyAvatar'),target.avatar,target.name,'?');
    bankSetAmountInput('bankNearbyAmount',0);
    document.getElementById('bankNearbyMemo').value='';
    closeModal('bankNearbyModal');
    openModal('bankNearbyAmountModal');
  }));
}

document.getElementById('bankRefresh')?.addEventListener('click',()=>post('phoneBankInfo'));

document.getElementById('bankPhoneTransfer')?.addEventListener('click',()=>{
  document.getElementById('bankPhoneInput').value='';
  bankSetAmountInput('bankPhoneAmount',0);
  document.getElementById('bankPhoneMemo').value='';
  renderBankContactHints();
  openModal('bankPhoneModal');
});
document.getElementById('bankPhoneInput')?.addEventListener('input',e=>{
  e.target.value=formatPhone(e.target.value);
  renderBankContactHints();
});
document.getElementById('bankPhoneAmount')?.addEventListener('input',e=>bankSetAmountInput('bankPhoneAmount',e.target.value));
document.querySelectorAll('[data-bank-add]').forEach(btn=>btn.addEventListener('click',()=>{
  const current=bankInputNumber(document.getElementById('bankPhoneAmount').value);
  bankSetAmountInput('bankPhoneAmount',current+Number(btn.dataset.bankAdd||0));
}));
document.getElementById('bankPhoneReview')?.addEventListener('click',()=>{
  const phone=digits(document.getElementById('bankPhoneInput').value);
  const amount=bankInputNumber(document.getElementById('bankPhoneAmount').value);
  const memo=document.getElementById('bankPhoneMemo').value.trim();
  if(phone.length<4){showToast('받는 사람 전화번호를 입력하세요.',true);return;}
  if(amount<1){showToast('송금 금액을 입력하세요.',true);return;}
  if(amount>Number(bankState.balance||0)){showToast('은행 잔액이 부족합니다.',true);return;}
  closeModal('bankPhoneModal');
  openBankConfirm({mode:'phone',phone,amount,memo,name:bankTargetName(phone)});
});

document.getElementById('bankNearbyTransfer')?.addEventListener('click',()=>{
  document.getElementById('bankNearbyList').innerHTML='<div class="sheet-loading">근처 휴대전화를 찾는 중...</div>';
  openModal('bankNearbyModal');
  post('phoneBankNearby');
});
document.getElementById('bankNearbyAmount')?.addEventListener('input',e=>bankSetAmountInput('bankNearbyAmount',e.target.value));
document.querySelectorAll('[data-bank-near-add]').forEach(btn=>btn.addEventListener('click',()=>{
  const current=bankInputNumber(document.getElementById('bankNearbyAmount').value);
  bankSetAmountInput('bankNearbyAmount',current+Number(btn.dataset.bankNearAdd||0));
}));
document.getElementById('bankNearbyReview')?.addEventListener('click',()=>{
  if(!bankNearbyTarget){showToast('근처 송금 대상을 다시 선택하세요.',true);return;}
  const amount=bankInputNumber(document.getElementById('bankNearbyAmount').value);
  const memo=document.getElementById('bankNearbyMemo').value.trim();
  if(amount<1){showToast('송금 금액을 입력하세요.',true);return;}
  if(amount>Number(bankState.balance||0)){showToast('은행 잔액이 부족합니다.',true);return;}
  closeModal('bankNearbyAmountModal');
  openBankConfirm({
    mode:'nearby',
    targetSource:Number(bankNearbyTarget.serverId),
    targetPhone:bankNearbyTarget.phone,
    name:bankNearbyTarget.name,
    amount,
    memo
  });
});

document.getElementById('bankConfirmCancel')?.addEventListener('click',()=>{
  closeModal('bankConfirmModal');
  bankPendingTransfer=null;
});
document.getElementById('bankConfirmSend')?.addEventListener('click',()=>{
  if(!bankPendingTransfer)return;
  const payload={...bankPendingTransfer};
  bankPendingTransfer=null;
  closeModal('bankConfirmModal');
  post('phoneBankTransfer',payload);
});

function money(v){
  const n=Math.max(0,Math.floor(Number(v)||0));
  return `${n.toLocaleString('ko-KR')}원`;
}
function km(v){
  const m=Number(v)||0;
  return m>=1000?`${(m/1000).toFixed(m>=10000?1:2)}km`:`${Math.round(m)}m`;
}
function taxiEstimateFromPreview(){
  if(!taxiPreview?.dest||!taxiState?.pricing)return null;
  const p=taxiState.pricing;
  const meters=Number(taxiPreview.distance)||0;
  let fare=Number(p.base_fare)||5500;
  const free=Number(p.free_dist)||1000;
  const step=Number(p.step_dist)||500;
  if(meters>free&&step>0)fare+=Math.floor((meters-free)/step)*(Number(p.step_fare)||200);
  const max=Number(p.max_fare)||200000;
  return Math.min(fare,max);
}
function renderTaxi(){
  document.getElementById('taxiPickup').textContent=taxiPreview?.pickupLabel||'현재 위치 불러오는 중';
  document.getElementById('taxiDestination').textContent=taxiPreview?.destLabel||'지도에 웨이포인트를 찍어주세요';
  document.getElementById('taxiDistance').textContent=taxiPreview?.distance!=null?km(taxiPreview.distance):'-';
  const est=taxiState?.estimate||taxiEstimateFromPreview();
  document.getElementById('taxiEstimate').textContent=est?money(est):'-';
  document.getElementById('taxiDrivers').textContent=taxiState?.drivers!=null?`${taxiState.drivers}명`:'확인 중';

  const state=taxiState?.state||'idle';
  const title=document.getElementById('taxiStatusTitle');
  const label=document.getElementById('taxiStatusLabel');
  const req=document.getElementById('taxiRequest');
  const cancel=document.getElementById('taxiCancel');

  const active=['searching','assigned','driver_arrived','riding'].includes(state);
  req.classList.toggle('hidden',active);
  cancel.classList.toggle('hidden',!['searching','assigned','driver_arrived'].includes(state));

  if(state==='searching'){
    label.textContent='배차 요청 중';
    title.textContent='가까운 택시기사를 찾고 있습니다';
    title.classList.add('service-status-pulse');
  }else if(state==='assigned'){
    label.textContent='기사 배정 완료';
    title.textContent=taxiState.driverDistance?`기사가 약 ${km(taxiState.driverDistance)} 거리에 있습니다`:'택시기사가 승객 위치로 이동 중입니다';
    title.classList.remove('service-status-pulse');
  }else if(state==='driver_arrived'){
    label.textContent='택시 도착';
    title.textContent='택시가 근처에 도착했습니다';
    title.classList.remove('service-status-pulse');
  }else if(state==='riding'){
    label.textContent='운행 중';
    title.textContent='목적지로 이동 중입니다';
    title.classList.remove('service-status-pulse');
  }else if(state==='completed'){
    label.textContent='운행 완료';
    title.textContent=`결제 완료 · ${money(taxiState.fare)}`;
    title.classList.remove('service-status-pulse');
  }else if(state==='unavailable'){
    label.textContent='배차 불가';
    title.textContent=taxiState.message||'현재 배차 가능한 택시기사가 없습니다';
    title.classList.remove('service-status-pulse');
  }else if(state==='expired'){
    label.textContent='배차 실패';
    title.textContent='응답 가능한 기사를 찾지 못했습니다';
    title.classList.remove('service-status-pulse');
  }else if(state==='payment_failed'){
    label.textContent='결제 필요';
    title.textContent=`은행 잔액을 확인해주세요 · ${money(taxiState.fare)}`;
    title.classList.remove('service-status-pulse');
  }else{
    label.textContent='택시가 필요하신가요?';
    title.textContent='현재 위치에서 바로 호출';
    title.classList.remove('service-status-pulse');
  }

  req.disabled=!taxiPreview?.dest||state==='unavailable';
}
async function refreshTaxiPreview(){
  const r=await post('phoneTaxiPreview');
  if(r?.ok)taxiPreview=r.data||null;
  renderTaxi();
}
document.getElementById('taxiRefresh')?.addEventListener('click',()=>{refreshTaxiPreview();post('phoneTaxiInfo');});
document.getElementById('taxiWaypointRefresh')?.addEventListener('click',refreshTaxiPreview);
document.getElementById('taxiRequest')?.addEventListener('click',async()=>{
  const r=await post('phoneTaxiRequest');
  if(!r?.ok){
    if(r?.error==='waypoint')showToast('먼저 GTA 지도에서 목적지 웨이포인트를 설정하세요.',true);
    return;
  }
  taxiPreview=r.data||taxiPreview;
  taxiState={...taxiState,state:'searching'};
  renderTaxi();
});
document.getElementById('taxiCancel')?.addEventListener('click',()=>post('phoneTaxiCancel'));

function setHealth(prefix,value){
  const n=Math.max(0,Math.min(100,Number(value)||0));
  document.getElementById(`${prefix}`)?.replaceChildren(document.createTextNode(`${Math.round(n)}%`));
  const bar=document.getElementById(`${prefix}Bar`);
  if(bar)bar.style.width=`${n}%`;
}
function renderMechanicVehicle(){
  const card=document.getElementById('vehicleScanCard');
  card.classList.toggle('empty',!mechanicVehicle);
  document.getElementById('mechanicVehicleName').textContent=mechanicVehicle?.label||'7m 안의 차량을 찾습니다';
  document.getElementById('mechanicPlate').textContent=mechanicVehicle?`번호판 ${mechanicVehicle.plate||'-'}`:'차량 안 또는 차량 근처에서 이용하세요.';
  setHealth('mechanicEngine',mechanicVehicle?.engine||0);
  setHealth('mechanicBody',mechanicVehicle?.body||0);
}
function renderMechanic(){
  renderMechanicVehicle();
  const p=mechanicState?.pricing||{};
  document.getElementById('mechanicBaseFare').textContent=p.base_fare!=null?money(p.base_fare):'-';
  document.getElementById('mechanicRepairFee').textContent=p.repair_fee!=null?money(p.repair_fee):'-';
  document.getElementById('mechanicMaxFare').textContent=p.max_fare!=null?money(p.max_fare):'-';

  const state=mechanicState?.state||'idle';
  const label=document.getElementById('mechanicStatusLabel');
  const title=document.getElementById('mechanicStatusTitle');
  const req=document.getElementById('mechanicRequest');
  const cancel=document.getElementById('mechanicCancel');

  const active=['searching','assigned'].includes(state);
  req.classList.toggle('hidden',active);
  cancel.classList.toggle('hidden',state!=='searching');

  if(state==='searching'){
    label.textContent='정비공 호출 중';
    title.textContent='출근 중인 정비공에게 요청을 전송했습니다';
    title.classList.add('service-status-pulse');
  }else if(state==='assigned'){
    label.textContent='정비공 배정 완료';
    title.textContent=mechanicState.price?`예상 요금 ${money(mechanicState.price)}`:'정비공이 현장으로 출동 중입니다';
    title.classList.remove('service-status-pulse');
  }else if(state==='completed'){
    label.textContent='정비 완료';
    title.textContent=`결제 완료 · ${money(mechanicState.price)}`;
    title.classList.remove('service-status-pulse');
  }else if(state==='unavailable'){
    label.textContent='출동 불가';
    title.textContent='현재 출근 중인 정비공이 없습니다';
    title.classList.remove('service-status-pulse');
  }else if(state==='expired'){
    label.textContent='요청 만료';
    title.textContent='정비공이 요청을 접수하지 못했습니다';
    title.classList.remove('service-status-pulse');
  }else if(state==='error'){
    label.textContent='요청 확인';
    title.textContent=mechanicState.message||'요청 상태를 확인해주세요';
    title.classList.remove('service-status-pulse');
  }else{
    label.textContent='차량에 문제가 생겼나요?';
    title.textContent='근처 차량을 찾아 정비공 호출';
    title.classList.remove('service-status-pulse');
  }
  req.disabled=!mechanicVehicle;
}
async function scanMechanicVehicle(){
  const r=await post('phoneMechanicScan');
  mechanicVehicle=r?.vehicle||null;
  renderMechanic();
}
document.getElementById('mechanicRefresh')?.addEventListener('click',()=>{scanMechanicVehicle();post('phoneMechanicInfo');});
document.getElementById('mechanicScan')?.addEventListener('click',scanMechanicVehicle);
document.getElementById('mechanicRequest')?.addEventListener('click',async()=>{
  const r=await post('phoneMechanicRequest');
  if(!r?.ok){
    if(r?.error==='vehicle')showToast('정비할 차량 안이나 7m 이내에서 요청하세요.',true);
    return;
  }
  mechanicVehicle=r.vehicle||mechanicVehicle;
  mechanicState={...mechanicState,state:'searching'};
  renderMechanic();
});
document.getElementById('mechanicCancel')?.addEventListener('click',()=>post('phoneMechanicCancel'));

function messageTime(ts){
  const d=new Date((Number(ts)||0)*1000);
  const now=new Date();
  if(!ts)return '';
  if(d.toDateString()===now.toDateString())return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  return `${d.getMonth()+1}/${d.getDate()}`;
}

function messageName(conv){
  if(conv.name)return conv.name;
  const c=contactByNumber(conv.phone);
  return c&&c.name?c.name:formatPhone(conv.phone);
}

function messageAvatar(conv){
  const c=contactByNumber(conv.phone);
  return conv.avatar||(c&&c.avatar)||'';
}

function renderMessageBadge(){
  const badge=document.getElementById('messageBadge');
  if(!badge)return;
  badge.textContent=messageUnread>99?'99+':String(messageUnread);
  badge.classList.toggle('hidden',messageUnread<=0);
}

function renderConversations(){
  const q=String(document.getElementById('messageSearch')?.value||'').trim().toLowerCase();
  const rows=messageConversations.filter(c=>{
    if(!q)return true;
    return messageName(c).toLowerCase().includes(q)||digits(c.phone).includes(digits(q));
  });

  document.getElementById('conversationCount').textContent=String(rows.length);
  document.getElementById('messageUnreadSummary').textContent=messageUnread>0?`읽지 않은 메시지 ${messageUnread}개`:'읽지 않은 메시지 없음';

  const list=document.getElementById('conversationList');
  if(!rows.length){
    list.innerHTML='<div class="message-empty"><b>대화가 없습니다</b>오른쪽 위 + 버튼으로 번호 또는 연락처를 선택해<br>첫 메시지를 보내보세요.</div>';
    return;
  }

  list.innerHTML=rows.map(c=>{
    const name=messageName(c)||formatPhone(c.phone);
    const preview=(c.outgoing?'나: ':'')+(c.lastBody|| (c.lastHasPhoto?'📷 사진':''));
    return `<button class="conversation-row" type="button" data-phone="${digits(c.phone)}">
      <span class="contact-avatar conversation-avatar" data-phone="${digits(c.phone)}">${escapeHtml(initials(name,'?'))}</span>
      <span class="conversation-main">
        <span class="conversation-topline"><b>${escapeHtml(name)}</b>${c.favorite?'<span class="fav-star">★</span>':''}</span>
        <span class="conversation-preview ${Number(c.unread)>0?'unread':''}">${escapeHtml(preview)}</span>
      </span>
      <span class="conversation-meta">
        <time>${messageTime(c.lastAt)}</time>
        ${Number(c.unread)>0?`<i class="conversation-unread">${Number(c.unread)>99?'99+':Number(c.unread)}</i>`:''}
      </span>
    </button>`;
  }).join('');

  rows.forEach(c=>{
    setAvatar(list.querySelector(`.conversation-avatar[data-phone="${digits(c.phone)}"]`),messageAvatar(c),messageName(c),'?');
  });

  list.querySelectorAll('[data-phone]').forEach(btn=>btn.addEventListener('click',()=>openConversation(btn.dataset.phone)));
}

function scrollThreadBottom(){
  const el=document.getElementById('messageThread');
  if(el)setTimeout(()=>{el.scrollTop=el.scrollHeight;},20);
}

function renderConversation(){
  if(!activeConversation)return;
  const name=activeConversation.name||contactByNumber(activeConversation.phone)?.name||formatPhone(activeConversation.phone);
  const avatar=activeConversation.avatar||contactByNumber(activeConversation.phone)?.avatar||'';

  document.getElementById('conversationName').textContent=name||formatPhone(activeConversation.phone);
  document.getElementById('conversationPhone').textContent=formatPhone(activeConversation.phone);
  setAvatar(document.getElementById('conversationAvatar'),avatar,name,'?');

  const thread=document.getElementById('messageThread');
  const rows=Array.isArray(activeConversation.messages)?activeConversation.messages:[];
  if(!rows.length){
    thread.innerHTML='<div class="message-empty"><b>새로운 대화</b>아직 주고받은 메시지가 없습니다.</div>';
  }else{
    thread.innerHTML=rows.map(m=>{
      const hasPhoto=String(m.photo||'').startsWith('data:image/');
      const photo=hasPhoto?`<button class="message-photo-wrap ${m.photoOrientation==='portrait'?'portrait':''}" type="button" data-message-photo="${Number(m.id)||0}"><img src="${m.photo}" alt="전송 사진"></button>`:'';
      const body=String(m.body||'').trim()?`<div class="message-text">${escapeHtml(m.body)}</div>`:'';
      return `<div class="message-line ${m.outgoing?'out':'in'}">
        <div class="message-bubble ${hasPhoto?'has-photo':''}">${photo}${body}</div>
        <div class="message-time ${m.outgoing&&Number(m.readAt)>0?'read':''}">${messageTime(m.sentAt)}${m.outgoing&&Number(m.readAt)>0?' · 읽음':''}</div>
      </div>`;
    }).join('');
    thread.querySelectorAll('[data-message-photo]').forEach(btn=>btn.addEventListener('click',()=>{
      const id=Number(btn.dataset.messagePhoto)||0;
      const row=rows.find(m=>Number(m.id)===id);
      if(!row?.photo)return;
      const img=document.getElementById('galleryPhotoImage'); if(img)img.src=row.photo;
      const frame=document.querySelector('#galleryPhotoModal .gallery-photo-frame'); if(frame){frame.classList.toggle('portrait',row.photoOrientation==='portrait');frame.classList.toggle('landscape',row.photoOrientation!=='portrait');}
      const date=document.getElementById('galleryPhotoDate'); if(date)date.textContent=messageTime(row.sentAt);
      const lens=document.getElementById('galleryPhotoLens'); if(lens)lens.textContent='메시지 사진';
      const del=document.getElementById('galleryPhotoDelete'); if(del)del.classList.add('hidden');
      const save=document.getElementById('galleryPhotoSave'); if(save)save.classList.toggle('hidden',row.outgoing===true);
      activeGalleryId=0;
      activeMessagePhotoId=row.outgoing?0:(Number(row.id)||0);
      openModal('galleryPhotoModal');
    }));
  }
  scrollThreadBottom();
}

function openConversation(phone){
  const number=digits(phone);
  if(!number)return;
  setView('conversation');
  activeConversation={phone:number,messages:[]};
  renderConversation();
  post('phoneOpenConversation',{phone:number});
}

function sendCurrentMessage(){
  if(!activeConversation)return;
  const input=document.getElementById('messageInput');
  const body=input.value.trim();
  if(!body)return;
  post('phoneSendMessage',{phone:activeConversation.phone,body});
  input.value='';
  input.style.height='';
}

function renderRecipientSuggestions(){
  const box=document.getElementById('messageRecipientSuggestions');
  const raw=String(document.getElementById('newMessageRecipient')?.value||'').trim();
  const q=raw.toLowerCase();
  const contactMatches=contactsRows.filter(c=>{
    if(!q)return true;
    return String(c.name||'').toLowerCase().includes(q)||digits(c.phone).includes(digits(q));
  }).slice(0,12);

  let html=contactMatches.map(c=>`
    <button class="recipient-row" type="button" data-recipient="${digits(c.phone)}">
      <span class="contact-avatar recipient-avatar" data-id="${c.id}">${escapeHtml(initials(c.name,'?'))}</span>
      <span class="recipient-row-info"><b>${escapeHtml(c.name||formatPhone(c.phone))}</b><small>${escapeHtml(formatPhone(c.phone))}</small></span>
    </button>`).join('');

  const rawNumber=digits(raw);
  if(rawNumber.length>=4&&!contactMatches.some(c=>digits(c.phone)===rawNumber)){
    html+=`<button class="recipient-row" type="button" data-recipient="${rawNumber}">
      <span class="contact-avatar">#</span>
      <span class="recipient-row-info"><b>${escapeHtml(formatPhone(rawNumber))}</b><small>전화번호로 대화 시작</small></span>
    </button>`;
  }

  box.innerHTML=html||'<div class="sheet-loading">연락처 이름이나 전화번호를 입력하세요.</div>';
  contactMatches.forEach(c=>setAvatar(box.querySelector(`.recipient-avatar[data-id="${c.id}"]`),c.avatar,c.name,'?'));
  box.querySelectorAll('[data-recipient]').forEach(btn=>btn.addEventListener('click',()=>{
    document.getElementById('newMessageRecipient').value=formatPhone(btn.dataset.recipient);
    box.dataset.selected=digits(btn.dataset.recipient);
    renderRecipientSuggestions();
  }));
}

function renderMessagePhotoPicker(){
  const grid=document.getElementById('messagePhotoGrid');
  const send=document.getElementById('messagePhotoSend');
  const selected=document.getElementById('messagePhotoSelected');
  if(!grid)return;
  if(!galleryRows.length){
    grid.innerHTML='<div class="gallery-empty"><b>보낼 사진이 없습니다.</b><small>카메라 앱에서 사진을 먼저 촬영하세요.</small></div>';
    if(send)send.disabled=true;
    if(selected)selected.classList.add('hidden');
    return;
  }
  grid.innerHTML=galleryRows.map(row=>`<button class="gallery-tile ${row.orientation==='portrait'?'portrait':''} ${Number(row.id)===Number(messagePhotoSelectedId)?'selected':''}" type="button" data-message-photo-pick="${Number(row.id)||0}"><img src="${row.image}" alt="보낼 사진"><span>${escapeHtml(galleryDate(row.createdAt))}</span></button>`).join('');
  grid.querySelectorAll('[data-message-photo-pick]').forEach(btn=>btn.addEventListener('click',()=>{
    messagePhotoSelectedId=Number(btn.dataset.messagePhotoPick)||0;
    renderMessagePhotoPicker();
  }));
  const picked=galleryById(messagePhotoSelectedId);
  if(send)send.disabled=!picked;
  if(selected){selected.textContent=picked?'선택 완료 · 사진 1장':'사진을 선택하세요.';selected.classList.toggle('hidden',!picked);}
}

function openMessagePhotoPicker(){
  if(!activeConversation?.phone)return;
  messagePhotoSelectedId=0;
  const grid=document.getElementById('messagePhotoGrid'); if(grid)grid.innerHTML='<div class="gallery-empty">사진을 불러오는 중...</div>';
  openModal('messagePhotoModal');
  requestGallery();
  setTimeout(renderMessagePhotoPicker,120);
}

document.getElementById('messagePhotoAttach')?.addEventListener('click',openMessagePhotoPicker);
document.getElementById('messagePhotoSend')?.addEventListener('click',()=>{
  if(!activeConversation?.phone||!messagePhotoSelectedId)return;
  const input=document.getElementById('messageInput');
  const body=String(input?.value||'').trim();
  post('phoneSendMessage',{phone:activeConversation.phone,body,photoId:messagePhotoSelectedId});
  if(input){input.value='';input.style.height='';}
  closeModal('messagePhotoModal');
  messagePhotoSelectedId=0;
});

document.getElementById('messageNew')?.addEventListener('click',()=>{
  document.getElementById('newMessageRecipient').value='';
  document.getElementById('messageRecipientSuggestions').dataset.selected='';
  renderRecipientSuggestions();
  openModal('newMessageModal');
});
document.getElementById('newMessageRecipient')?.addEventListener('input',e=>{
  document.getElementById('messageRecipientSuggestions').dataset.selected='';
  renderRecipientSuggestions();
});
document.getElementById('newMessageContinue')?.addEventListener('click',()=>{
  const box=document.getElementById('messageRecipientSuggestions');
  const number=digits(box.dataset.selected||document.getElementById('newMessageRecipient').value);
  if(number.length<4){showToast('받는 사람의 전화번호를 입력하세요.',true);return;}
  closeModal('newMessageModal');
  openConversation(number);
});
document.getElementById('messageSearch')?.addEventListener('input',renderConversations);
document.getElementById('conversationBack')?.addEventListener('click',()=>{
  setView('messages');
  activeConversation=null;
  post('phoneMessagesRefresh');
});
document.getElementById('conversationCall')?.addEventListener('click',()=>{
  if(activeConversation)post('phoneDial',{number:activeConversation.phone});
});
document.getElementById('messageSend')?.addEventListener('click',sendCurrentMessage);
document.getElementById('messageInput')?.addEventListener('keydown',e=>{
  if(e.key==='Enter'&&!e.shiftKey){
    e.preventDefault();
    sendCurrentMessage();
  }
});
document.getElementById('messageInput')?.addEventListener('input',e=>{
  e.target.style.height='auto';
  e.target.style.height=Math.min(86,e.target.scrollHeight)+'px';
});

function openModal(id){
  document.getElementById(id)?.classList.remove('hidden');
}
function closeModal(id){
  document.getElementById(id)?.classList.add('hidden');
}
document.querySelectorAll('.modal-close').forEach(btn=>btn.addEventListener('click',()=>closeModal(btn.dataset.close)));

function renderProfileCard(){
  const name=profile.name||'내 연락처';
  document.getElementById('myProfileName').textContent=name;
  document.getElementById('myProfilePhone').textContent=formatPhone(myNumber)||'번호 없음';
  document.getElementById('profilePhoneLocked').textContent=formatPhone(myNumber)||'-';
  setAvatar(document.getElementById('myAvatar'),profile.avatar,name,'ME');
}

function renderContacts(){
  const q=String(document.getElementById('contactSearch')?.value||'').trim().toLowerCase();
  const filtered=contactsRows.filter(c=>{
    if(!q)return true;
    return String(c.name||'').toLowerCase().includes(q)||digits(c.phone).includes(digits(q));
  });
  const favs=filtered.filter(c=>c.favorite);
  document.getElementById('favoriteCount').textContent=String(favs.length);
  document.getElementById('contactCount').textContent=String(filtered.length);

  const favList=document.getElementById('favoriteList');
  favList.innerHTML=favs.length?favs.map(c=>`
    <button class="favorite-card" type="button" data-contact="${c.id}">
      <span class="contact-avatar fav-avatar" data-id="${c.id}">${escapeHtml(initials(c.name,'?'))}</span>
      <b>${escapeHtml(c.name||formatPhone(c.phone))}</b>
      <small>${escapeHtml(formatPhone(c.phone))}</small>
    </button>`).join(''):'<div class="favorite-empty">★ 표시한 중요 연락처가 여기에 고정됩니다.</div>';

  favs.forEach(c=>{
    const el=favList.querySelector(`.fav-avatar[data-id="${c.id}"]`);
    setAvatar(el,c.avatar,c.name,'?');
  });

  const list=document.getElementById('contactList');
  list.innerHTML=filtered.length?filtered.map(c=>`
    <button class="contact-row" type="button" data-contact="${c.id}">
      <span class="contact-avatar row-avatar" data-id="${c.id}">${escapeHtml(initials(c.name,'?'))}</span>
      <span class="contact-row-info">
        <b>${c.favorite?'<span class="fav-star">★</span>':''}${escapeHtml(c.name||formatPhone(c.phone))}${c.blocked?'<span class="blocked-mark">차단</span>':''}</b>
        <small>${escapeHtml(formatPhone(c.phone))}${c.note?' · '+escapeHtml(c.note):''}</small>
      </span>
      <span class="contact-chevron">›</span>
    </button>`).join(''):'<div class="contact-empty">저장된 연락처가 없습니다.<br>직접 추가하거나 근처에서 연락처 카드를 받아보세요.</div>';

  filtered.forEach(c=>{
    setAvatar(list.querySelector(`.row-avatar[data-id="${c.id}"]`),c.avatar,c.name,'?');
  });

  document.querySelectorAll('[data-contact]').forEach(btn=>btn.addEventListener('click',()=>openContactEditor(Number(btn.dataset.contact))));
}

function updateContactEditorPreview(){
  const name=document.getElementById('contactNameInput').value.trim()||'새 연락처';
  const number=digits(document.getElementById('contactPhoneInput').value);
  document.getElementById('contactEditPreviewName').textContent=name;
  document.getElementById('contactEditPreviewPhone').textContent=number?formatPhone(number):'전화번호를 입력하세요';
}

function setToggle(id,on){
  const el=document.getElementById(id);
  if(el)el.dataset.on=on?'true':'false';
}
function getToggle(id){return document.getElementById(id)?.dataset.on==='true';}

function openContactEditor(id=0){
  activeContactId=Number(id)||0;
  const c=contactsRows.find(x=>Number(x.id)===activeContactId)||null;
  document.getElementById('contactModalTitle').textContent=c?'연락처 편집':'연락처 추가';
  document.getElementById('contactIdInput').value=c?c.id:0;
  document.getElementById('contactNameInput').value=c?.name||'';
  document.getElementById('contactPhoneInput').value=c?formatPhone(c.phone):'';
  document.getElementById('contactPhoneInput').disabled=!!c;
  document.getElementById('contactNoteInput').value=c?.note||'';
  setToggle('contactFavoriteToggle',!!c?.favorite);
  setToggle('contactBlockToggle',!!c?.blocked);
  document.getElementById('contactDelete').classList.toggle('hidden',!c);
  document.getElementById('contactCallNow').classList.toggle('hidden',!c);
  setAvatar(document.getElementById('contactEditAvatar'),c?.avatar,c?.name,'?');
  updateContactEditorPreview();
  openModal('contactModal');
}

document.getElementById('contactAdd')?.addEventListener('click',()=>openContactEditor(0));
document.getElementById('contactSearch')?.addEventListener('input',renderContacts);
document.getElementById('contactNameInput')?.addEventListener('input',updateContactEditorPreview);
document.getElementById('contactPhoneInput')?.addEventListener('input',e=>{
  e.target.value=formatPhone(e.target.value);
  updateContactEditorPreview();
});
document.getElementById('contactFavoriteToggle')?.addEventListener('click',()=>{
  setToggle('contactFavoriteToggle',!getToggle('contactFavoriteToggle'));
});
document.getElementById('contactBlockToggle')?.addEventListener('click',()=>{
  setToggle('contactBlockToggle',!getToggle('contactBlockToggle'));
});

document.getElementById('contactSave')?.addEventListener('click',()=>{
  const existing=contactsRows.find(x=>Number(x.id)===activeContactId)||{};
  const payload={
    phone:digits(document.getElementById('contactPhoneInput').value),
    name:document.getElementById('contactNameInput').value,
    note:document.getElementById('contactNoteInput').value,
    avatar:existing.avatar||'',
    favorite:getToggle('contactFavoriteToggle'),
    blocked:getToggle('contactBlockToggle'),
    sourceLicense:existing.sourceLicense||''
  };
  if(payload.phone.length<4){showToast('전화번호를 정확히 입력하세요.',true);return;}
  post('phoneSaveContact',payload);
  closeModal('contactModal');
});
document.getElementById('contactDelete')?.addEventListener('click',()=>{
  if(!activeContactId)return;
  post('phoneDeleteContact',{id:activeContactId});
  closeModal('contactModal');
});
document.getElementById('contactCallNow')?.addEventListener('click',()=>{
  const c=contactsRows.find(x=>Number(x.id)===activeContactId);
  if(!c)return;
  post('phoneDial',{number:c.phone});
  closeModal('contactModal');
});
document.getElementById('contactFavoriteToggle')?.addEventListener('dblclick',()=>{});
document.getElementById('contactBlockToggle')?.addEventListener('dblclick',()=>{});

document.getElementById('editProfile')?.addEventListener('click',()=>{
  profileDraftAvatar=profile.avatar||'';
  profileDraftPhotoId=Number(profile.photoId)||0;
  document.getElementById('profileNameInput').value=profile.name||'';
  setAvatar(document.getElementById('profilePhotoPreview'),profileDraftAvatar,profile.name,'ME');
  openModal('profileModal');
});
document.getElementById('profilePhotoPick')?.addEventListener('click',()=>{
  const grid=document.getElementById('profileGalleryGrid'); if(grid)grid.innerHTML='<div class="gallery-empty">사진을 불러오는 중...</div>';
  openModal('profileGalleryModal'); requestGallery();
});
document.getElementById('profilePhotoClear')?.addEventListener('click',()=>{
  profileDraftPhotoId=0; profileDraftAvatar=''; setAvatar(document.getElementById('profilePhotoPreview'),'','','ME');
  showToast('프로필 사진을 제거했습니다. 저장을 눌러 적용하세요.');
});
document.getElementById('profileSave')?.addEventListener('click',()=>{
  const name=document.getElementById('profileNameInput').value.trim(); if(!name){showToast('표시 이름을 입력하세요.',true);return;}
  post('phoneSaveProfile',{name,photoId:profileDraftPhotoId}); closeModal('profileModal');
});

document.getElementById('shareMyContact')?.addEventListener('click',()=>{
  document.getElementById('nearbyList').innerHTML='<div class="sheet-loading">근처 사용자를 찾는 중...</div>';
  openModal('nearbyModal');
  post('phoneNearby');
});

function renderNearby(rows){
  const list=document.getElementById('nearbyList');
  if(!Array.isArray(rows)||!rows.length){
    list.innerHTML='<div class="sheet-loading">4m 안에 휴대전화를 켠 사용자가 없습니다.</div>';
    return;
  }
  list.innerHTML=rows.map(r=>`
    <div class="nearby-row">
      <span class="contact-avatar nearby-avatar" data-sid="${r.serverId}">${escapeHtml(initials(r.name,'?'))}</span>
      <span class="nearby-row-info"><b>${escapeHtml(r.name||('사용자 #'+r.serverId))}</b><small>${Number(r.distance||0).toFixed(1)}m · 휴대전화 사용 중</small></span>
      <button class="nearby-send" type="button" data-share="${r.serverId}">보내기</button>
    </div>`).join('');
  rows.forEach(r=>setAvatar(list.querySelector(`.nearby-avatar[data-sid="${r.serverId}"]`),r.avatar,r.name,'?'));
  list.querySelectorAll('[data-share]').forEach(btn=>btn.addEventListener('click',()=>{
    post('phoneShareContact',{serverId:Number(btn.dataset.share)});
    closeModal('nearbyModal');
  }));
}

function showContactOffer(offer){
  contactOffer=offer||null;
  if(!contactOffer)return;
  document.getElementById('offerName').textContent=contactOffer.name||'알 수 없는 사용자';
  document.getElementById('offerPhone').textContent=formatPhone(contactOffer.phone)||'-';
  setAvatar(document.getElementById('offerAvatar'),contactOffer.avatar,contactOffer.name,'?');
  openModal('shareOfferModal');
}

document.getElementById('offerAccept')?.addEventListener('click',()=>{
  if(!contactOffer)return;
  post('phoneAcceptShare',{shareId:contactOffer.shareId});
  closeModal('shareOfferModal');
  contactOffer=null;
});
document.getElementById('offerDecline')?.addEventListener('click',()=>{
  if(!contactOffer)return;
  post('phoneDeclineShare',{shareId:contactOffer.shareId});
  closeModal('shareOfferModal');
  contactOffer=null;
});

const cameraHud=document.getElementById('cameraHud');
let cameraHudState={active:false,mode:'rear',orientation:'portrait',zoom:1,flash:'auto',timer:0,grid:true,busy:false,lastPhoto:''};

function cameraFlashText(mode){return mode==='on'?'ON ⚡':mode==='off'?'OFF ⚡':'AUTO ⚡';}
function renderCameraHudState(data={}){
  cameraHudState={...cameraHudState,...data};
  if(!cameraHud)return;
  cameraHud.classList.toggle('active',!!cameraHudState.active);
  cameraHud.classList.toggle('portrait',cameraHudState.orientation==='portrait');
  cameraHud.classList.toggle('landscape',cameraHudState.orientation!=='portrait');
  cameraHud.classList.toggle('front',cameraHudState.mode==='front');
  cameraHud.classList.toggle('busy',!!cameraHudState.busy);
  document.getElementById('cameraGrid')?.classList.toggle('hidden',!cameraHudState.grid);
  const flash=document.getElementById('camFlash'); if(flash)flash.textContent=cameraFlashText(cameraHudState.flash);
  const timer=document.getElementById('camTimer'); if(timer)timer.textContent=Number(cameraHudState.timer)>0?`${cameraHudState.timer}초 타이머`:'타이머 끔';
  const orientation=document.getElementById('camOrientation'); if(orientation)orientation.textContent=cameraHudState.orientation==='portrait'?'세로':'가로';
  const zoom=document.getElementById('camZoom'); if(zoom)zoom.textContent=`${Number(cameraHudState.zoom||1).toFixed(1)}×`;
  const mode=document.getElementById('camModeIcon'); if(mode){const s=mode.querySelector('small');if(s)s.textContent=cameraHudState.mode==='front'?'전면':'후면';}
  const last=document.getElementById('camLastPhoto');
  if(last&&cameraHudState.lastPhoto){last.style.backgroundImage=`url("${cameraHudState.lastPhoto}")`;last.classList.add('has-photo');last.innerHTML='';}
  if(data.flip){cameraHud.classList.remove('flipping');void cameraHud.offsetWidth;cameraHud.classList.add('flipping');setTimeout(()=>cameraHud?.classList.remove('flipping'),260);}
}
function cameraShutterEffect(useFlash){
  if(!cameraHud)return;
  cameraHud.classList.add('shutter');
  const flash=document.getElementById('cameraShutterFlash');
  if(flash){flash.classList.toggle('strong',!!useFlash);flash.classList.add('show');setTimeout(()=>flash.classList.remove('show'),130);}
  setTimeout(()=>cameraHud?.classList.remove('shutter'),180);
}

async function processCapturedPhoto(data){
  const token=String(data?.token||'');
  const src=String(data?.image||'');
  if(!token||!src)return;
  try{
    const image=new Image();
    await new Promise((resolve,reject)=>{image.onload=resolve;image.onerror=reject;image.src=src;});
    const sw=image.naturalWidth||image.width, sh=image.naturalHeight||image.height;
    if(!sw||!sh)throw new Error('invalid image');

    const portrait=data.orientation==='portrait';
    const targetRatio=portrait?(9/16):(16/9);
    let sx=0,sy=0,cw=sw,ch=sh;
    const sourceRatio=sw/sh;
    if(sourceRatio>targetRatio){cw=sh*targetRatio;sx=(sw-cw)/2;}
    else if(sourceRatio<targetRatio){ch=sw/targetRatio;sy=(sh-ch)/2;}

    const canvas=document.createElement('canvas');
    if(portrait){canvas.width=540;canvas.height=960;}
    else{canvas.width=1280;canvas.height=720;}
    const ctx=canvas.getContext('2d',{alpha:false});
    ctx.imageSmoothingEnabled=true;ctx.imageSmoothingQuality='high';

    // Front-camera selfies are stored mirrored, matching the live selfie preview.
    if(data.cameraMode==='front'){
      ctx.translate(canvas.width,0);ctx.scale(-1,1);
    }
    ctx.drawImage(image,sx,sy,cw,ch,0,0,canvas.width,canvas.height);
    const out=canvas.toDataURL('image/webp',.88);
    await post('phoneCameraProcessed',{token,image:out});
  }catch(e){
    await post('phoneCameraProcessed',{token,image:''});
  }
}

window.addEventListener('message',e=>{
  const d=e.data||{};

  if(d.action==='cameraHud') renderCameraHudState(d);
  if(d.action==='cameraCountdown'){
    const el=document.getElementById('cameraCountdown'); if(el){el.textContent=Number(d.value)>0?String(d.value):'';el.classList.toggle('show',Number(d.value)>0);}
  }
  if(d.action==='cameraCaptureClean') cameraHud?.classList.toggle('capture-clean',!!d.active);
  if(d.action==='cameraShutter') cameraShutterEffect(!!d.flash);
  if(d.action==='cameraProcessPhoto') processCapturedPhoto(d);

  if(d.action==='open'){
    phone.classList.add('open');
    updateClock();
  }
  if(d.action==='close'){
    phone.classList.remove('open');
    stopCallAudio();
  }
  if(d.action==='galleryData'){
    galleryRows=Array.isArray(d.rows)?d.rows:[]; renderGallery(); renderProfileGallery(); renderMessagePhotoPicker();
  }
  if(d.action==='galleryPhotoAdded'){
    const photo=d.photo||{};
    if(photo.id&&photo.image){galleryRows=[photo,...galleryRows.filter(r=>Number(r.id)!==Number(photo.id))].slice(0,36);cameraHudState.lastPhoto=photo.image;renderCameraHudState({lastPhoto:photo.image});renderGallery();renderProfileGallery();}
  }
  if(d.action==='phoneData'){
    myNumber=digits(d.phone);
    profile=d.profile||{name:'',avatar:''};
    if(d.settings){
      phoneSettings=normalizeSettings(d.settings);
      settingsDraft={...phoneSettings};applyTheme(phoneSettings,false);syncSettingsControls();
    }
    contactsRows=Array.isArray(d.contacts)?d.contacts:[];
    historyRows=Array.isArray(d.history)?d.history:[];
    document.getElementById('myNumber').textContent=myNumber?formatPhone(myNumber):'번호 없음';
    renderProfileCard();
    renderContacts();
    renderHistory();
    renderConversations();
    renderBank();
  }
  if(d.action==='callSync'){
    call=d.call||null;
    renderCall();
  }
  if(d.action==='callEnded'){
    call=null;
    renderCall();
    showToast(callReasonText(d.reason),d.reason!=='answered');
  }
  if(d.action==='callFailed'){
    showToast(callReasonText(d.reason),true);
  }
  if(d.action==='bankState'){
    bankState={...bankState,...(d.data||{})};
    renderBank();
  }
  if(d.action==='bankNearby'){
    renderBankNearby(d.rows||[]);
  }
  if(d.action==='bankNotice'){
    showToast(d.message||'',!!d.isError);
  }
  if(d.action==='bankIncoming'){
    const incoming=d.data||{};
    bankState.balance=Number(bankState.balance||0)+Number(incoming.amount||0);
    renderBank();
    showToast(`${bankTargetName(incoming.fromPhone)}에게서 ${bankMoney(incoming.amount)} 입금`,false);
    post('phoneBankInfo');
  }
  if(d.action==='phoneSettings'){
    phoneSettings=normalizeSettings(d.settings||{});
    settingsDraft={...phoneSettings};
    applyTheme(phoneSettings,false);
    syncSettingsControls();
  }
  if(d.action==='taxiStatus'){
    taxiState={...taxiState,...(d.data||{})};
    if(taxiState.state==='cancelled')setTimeout(()=>{taxiState={state:'idle',pricing:taxiState.pricing};renderTaxi();},1200);
    if(taxiState.state==='error'&&taxiState.message)showToast(taxiState.message,true);
    renderTaxi();
  }
  if(d.action==='mechanicStatus'){
    mechanicState={...mechanicState,...(d.data||{})};
    if(mechanicState.state==='cancelled')setTimeout(()=>{mechanicState={state:'idle',pricing:mechanicState.pricing};renderMechanic();},1200);
    if(mechanicState.state==='error'&&mechanicState.message)showToast(mechanicState.message,true);
    renderMechanic();
  }
  if(d.action==='messagesState'){
    messageConversations=Array.isArray(d.conversations)?d.conversations:[];
    messageUnread=Number(d.unread)||0;
    renderMessageBadge();
    renderConversations();
  }
  if(d.action==='conversation'){
    activeConversation=d.conversation||null;
    renderConversation();
    if(activeConversation?.phone)post('phoneMarkRead',{phone:activeConversation.phone});
  }
  if(d.action==='newMessage'){
    const m=d.message||{};
    if(activeConversation&&digits(activeConversation.phone)===digits(m.fromPhone)){
      activeConversation.messages=Array.isArray(activeConversation.messages)?activeConversation.messages:[];
      activeConversation.messages.push({id:m.id,outgoing:false,body:m.body,photo:m.photo||'',photoOrientation:m.photoOrientation||'landscape',sentAt:m.sentAt,readAt:0});
      renderConversation();
      post('phoneMarkRead',{phone:m.fromPhone});
    }else{
      showToast(`새 메시지 · ${displayNameForNumber(m.fromPhone)||formatPhone(m.fromPhone)}`,false);
    }
  }
  if(d.action==='messageSent'){
    const m=d.message||{};
    if(activeConversation&&digits(activeConversation.phone)===digits(m.phone)){
      activeConversation.messages=Array.isArray(activeConversation.messages)?activeConversation.messages:[];
      activeConversation.messages.push({id:m.id,outgoing:true,body:m.body,photo:m.photo||'',photoOrientation:m.photoOrientation||'landscape',sentAt:m.sentAt,readAt:0});
      renderConversation();
    }
  }
  if(d.action==='messagesRead'){
    if(activeConversation&&digits(activeConversation.phone)===digits(d.phone)){
      (activeConversation.messages||[]).forEach(m=>{if(m.outgoing&&!m.readAt)m.readAt=Math.floor(Date.now()/1000);});
      renderConversation();
    }
  }
  if(d.action==='nearbyContacts'){
    renderNearby(d.rows||[]);
  }
  if(d.action==='contactOffer'){
    showContactOffer(d.offer||{});
  }
  if(d.action==='dispatchOverview'){ renderDispatchOverview(d.data||{}); }
  if(d.action==='dispatchNotice'){ showDispatchNotice(d.data||{}); }
  if(d.action==='dispatchIncoming'){ dispatchIncomingRows[String(d.data?.id||'')]=d.data||{}; renderDispatchIncoming(); }
  if(d.action==='dispatchRemove'){ delete dispatchIncomingRows[String(d.id||'')]; renderDispatchIncoming(); }
  if(d.action==='dispatchClearIncoming'){ dispatchIncomingRows={}; renderDispatchIncoming(); }
  if(d.action==='toast'){
    showToast(d.message,!!d.isError);
  }
});


function dispatchCallLabel(row){
  return `CALL #${String(Number(row.id)||0).padStart(4,'0')}`;
}
function dispatchStatusText(s){
  return ({pending:'대기 중',accepted:'접수됨',cancelled:'취소됨',closed:'처리 완료'})[s]||s||'-';
}
function dispatchTargetIcon(t){
  if(t.icon)return escapeHtml(t.icon);
  return t.kind==='service'?(t.key==='taxi'?'🚕':'🔧'):(t.gov?'🏛️':'📡');
}
function renderDispatchTargets(){
  const box=document.getElementById('dispatchTargets');
  const count=document.getElementById('dispatchTargetCount');
  const rows=Array.isArray(dispatchOverview.targets)?dispatchOverview.targets:[];
  if(count)count.textContent=String(rows.length);
  if(!box)return;
  if(!rows.length){box.innerHTML='<div class="dispatch-empty">연락 가능한 대상이 없습니다.</div>';return;}
  box.innerHTML=rows.map(t=>{
    const available=Number(t.available)||0;
    return `<button class="dispatch-target ${available<=0?'offline':''}" type="button" data-dispatch-target="${escapeHtml(t.target)}">
      <span class="dispatch-target-icon">${dispatchTargetIcon(t)}</span>
      <span class="dispatch-target-copy"><b>${escapeHtml(t.label||'-')}</b><small>${escapeHtml(t.category||'팩션')}</small></span>
      <span class="dispatch-available"><b>${available}</b><small>응답 가능</small></span>
    </button>`;
  }).join('');
  box.querySelectorAll('[data-dispatch-target]').forEach(btn=>btn.addEventListener('click',()=>{
    const target=rows.find(x=>String(x.target)===String(btn.dataset.dispatchTarget));
    if(!target)return;
    dispatchSelectedTarget=target;
    document.getElementById('dispatchComposeTarget').textContent=target.label||'긴급연락';
    document.getElementById('dispatchReasonInput').value='';
    openModal('dispatchComposeModal');
  }));
}
function renderDispatchOwnCalls(){
  const box=document.getElementById('dispatchOwnCalls'); if(!box)return;
  const rows=Array.isArray(dispatchOverview.ownCalls)?dispatchOverview.ownCalls:[];
  if(!rows.length){box.innerHTML='<div class="dispatch-empty compact">활성 콜이 없습니다.</div>';return;}
  box.innerHTML=rows.map(r=>`<div class="dispatch-call-card">
    <div class="dispatch-call-top"><b>${dispatchCallLabel(r)}</b><span class="status ${r.status}">${dispatchStatusText(r.status)}</span></div>
    <strong>${escapeHtml(r.targetLabel||'-')}</strong><p>${escapeHtml(r.reason||'')}</p>
    <small>${r.acceptedByName?('담당자: '+escapeHtml(r.acceptedByName)):'아직 접수되지 않았습니다.'}</small>
    <button class="dispatch-cancel-btn" type="button" data-dispatch-cancel="${Number(r.id)||0}">콜 취소</button>
  </div>`).join('');
  box.querySelectorAll('[data-dispatch-cancel]').forEach(btn=>btn.addEventListener('click',async()=>{
    const r=await post('phoneDispatchCancel',{id:Number(btn.dataset.dispatchCancel)||0});
    if(r?.ok){showToast('콜을 취소했습니다.');loadDispatchOverview();}else showToast(r?.reason||'취소할 수 없습니다.',true);
  }));
}
function renderDispatchAssignedCalls(){
  const box=document.getElementById('dispatchAssignedCalls'); if(!box)return;
  const rows=Array.isArray(dispatchOverview.assignedCalls)?dispatchOverview.assignedCalls:[];
  if(!rows.length){box.innerHTML='<div class="dispatch-empty compact">접수한 콜이 없습니다.</div>';return;}
  box.innerHTML=rows.map(r=>`<div class="dispatch-call-card assigned">
    <div class="dispatch-call-top"><b>${dispatchCallLabel(r)}</b><span class="status accepted">접수됨</span></div>
    <strong>${escapeHtml(r.callerName||'-')} · ${escapeHtml(r.targetLabel||'-')}</strong><p>${escapeHtml(r.reason||'')}</p>
    <small>신고 위치: ${escapeHtml(r.locationLabel||'호출 위치')}</small>
    <div class="dispatch-call-actions"><button type="button" data-dispatch-gps="${Number(r.id)||0}">GPS 설정</button><button type="button" data-dispatch-gps-clear="1">GPS 해제</button><button class="finish" type="button" data-dispatch-close="${Number(r.id)||0}">콜 종료</button></div>
  </div>`).join('');
  box.querySelectorAll('[data-dispatch-gps]').forEach(btn=>btn.addEventListener('click',async()=>{
    const r=await post('phoneDispatchGps',{id:Number(btn.dataset.dispatchGps)||0}); if(!r?.ok)showToast(r?.reason||'GPS를 설정할 수 없습니다.',true);
  }));
  box.querySelectorAll('[data-dispatch-gps-clear]').forEach(btn=>btn.addEventListener('click',()=>post('phoneDispatchGpsClear')));
  box.querySelectorAll('[data-dispatch-close]').forEach(btn=>btn.addEventListener('click',()=>{
    dispatchCloseCallId=Number(btn.dataset.dispatchClose)||0;
    document.getElementById('dispatchCloseTitle').textContent=dispatchCallLabel({id:dispatchCloseCallId})+' 종료';
    document.getElementById('dispatchCloseReason').value='';
    openModal('dispatchCloseModal');
  }));
}
function renderDispatchOverview(data){
  dispatchOverview=data||{targets:[],ownCalls:[],assignedCalls:[]};
  renderDispatchTargets();renderDispatchOwnCalls();renderDispatchAssignedCalls();
}
function loadDispatchOverview(){
  const box=document.getElementById('dispatchTargets'); if(box)box.innerHTML='<div class="dispatch-empty">대상을 불러오는 중...</div>';
  return post('phoneDispatchOverview').then(r=>{if(r?.ok)renderDispatchOverview(r);else if(box)box.innerHTML='<div class="dispatch-empty">불러오지 못했습니다.</div>';return r;});
}
function showDispatchNotice(data){
  const box=document.getElementById('dispatchAlerts'); if(!box)return;
  const item=document.createElement('div');item.className='dispatch-alert '+(data?.type||'info');
  item.innerHTML=`<b>${escapeHtml(data?.title||'긴급연락')}</b><span>${escapeHtml(data?.message||'')}</span>`;
  box.prepend(item);while(box.children.length>4)box.lastElementChild.remove();
  requestAnimationFrame(()=>item.classList.add('show'));
  setTimeout(()=>{item.classList.remove('show');setTimeout(()=>item.remove(),220);},5200);
}
function renderDispatchIncoming(){
  const box=document.getElementById('dispatchIncoming'); if(!box)return;
  const rows=Object.values(dispatchIncomingRows).sort((a,b)=>(Number(b.id)||0)-(Number(a.id)||0));
  const r=rows[0];
  if(!r){box.classList.add('hidden');return;}
  box.classList.remove('hidden');
  document.getElementById('dispatchIncomingId').textContent=dispatchCallLabel(r);
  document.getElementById('dispatchIncomingTarget').textContent=r.targetLabel||'-';
  document.getElementById('dispatchIncomingCaller').textContent=`신고자 ${r.callerName||'-'} [${r.callerGobun||'-'}]`;
  document.getElementById('dispatchIncomingReason').textContent=r.reason||'-';
  document.getElementById('dispatchIncomingDistance').textContent=r.distance?`${Number(r.distance).toFixed(1)}km · 호출 위치`:'호출 위치 전송됨';
}

document.getElementById('dispatchRefresh')?.addEventListener('click',loadDispatchOverview);
document.getElementById('dispatchComposeCancel')?.addEventListener('click',()=>closeModal('dispatchComposeModal'));
document.getElementById('dispatchSend')?.addEventListener('click',async()=>{
  if(!dispatchSelectedTarget)return;
  const reason=(document.getElementById('dispatchReasonInput').value||'').trim();
  if(reason.length<2){showToast('콜 사유를 입력하세요.',true);return;}
  const r=await post('phoneDispatchCreate',{target:dispatchSelectedTarget.target,reason});
  if(r?.ok){closeModal('dispatchComposeModal');showToast(`${r.callLabel||'CALL'} 전송 완료`);loadDispatchOverview();}
  else showToast(r?.reason||'콜 전송에 실패했습니다.',true);
});
document.getElementById('dispatchCloseCancel')?.addEventListener('click',()=>closeModal('dispatchCloseModal'));
document.querySelectorAll('#dispatchClosePresets button').forEach(btn=>btn.addEventListener('click',()=>{document.getElementById('dispatchCloseReason').value=btn.textContent.trim();}));
document.getElementById('dispatchCloseSubmit')?.addEventListener('click',async()=>{
  const reason=(document.getElementById('dispatchCloseReason').value||'').trim();
  if(!dispatchCloseCallId||reason.length<2){showToast('종료 사유를 입력하세요.',true);return;}
  const r=await post('phoneDispatchClose',{id:dispatchCloseCallId,reason});
  if(r?.ok){closeModal('dispatchCloseModal');showToast('콜 처리를 완료했습니다.');loadDispatchOverview();}
  else showToast(r?.reason||'콜 종료에 실패했습니다.',true);
});

updateDial();
renderHistory();


// HOME LAUNCHER: 앱이 많아져도 폰 전체가 내려가지 않고 이 영역만 스크롤.
const homeAppGrid = document.getElementById('homeAppGrid');
if(homeAppGrid){
  homeAppGrid.addEventListener('wheel', (e)=>{
    e.stopPropagation();
  }, {passive:true});
}

// COOKIE PHONE MESSAGE PHOTO SAVE V13.9.0
