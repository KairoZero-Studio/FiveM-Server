const COOKIE_ADMIN_BUILD_20260827_2124 = true;
console.log('[COOKIE ADMIN] build 20260827-2124 loaded');
const LEVEL_NAME = {
  1: '뉴비가이드', 2: '스태프', 3: 'ADMIN', 4: 'SENIORADMIN', 5: 'HEADADMIN'
};

const overlay = document.getElementById('overlay');

// Global NUI escape guard.
// F3 must ALWAYS be able to release the admin NUI, even if a sub-window state broke.
document.addEventListener('keydown', (e) => {
  if (e.key === 'F3') {
    e.preventDefault();
    e.stopImmediatePropagation();
    closePanel();
    return;
  }
  if (e.key !== 'Escape') return;

  // V14.2.7: 이벤트/출석/퀘스트 허브는 #overlay 바깥 body에 붙는다.
  // 따라서 일반 ESC 가드보다 먼저 닫아야 standalone 상태에서도
  // DOM 제거 + closeEventHub(NUI focus 해제)가 반드시 실행된다.
  const eventHub = document.getElementById('ckEventModal');
  if (eventHub) {
    e.preventDefault();
    e.stopImmediatePropagation();
    try { closeCookieEventHub(); } catch (_) { eventHub.remove(); }
    return;
  }

  // If the visual panel is already hidden but NUI still receives keys,
  // focus is stuck. Force the Lua close callback immediately.
  if (!overlay || overlay.classList.contains('hidden')) {
    e.preventDefault();
    e.stopImmediatePropagation();
    fetch('https://cookie_admin/close', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}'
    }).catch(() => {});
    return;
  }

  // Let visible sub-windows consume the first ESC normally.
  const subOpen = document.querySelector(
    '.ck-system-window-overlay:not(.hidden), #zonePreviewBar:not(.hidden), #boxEdit:not(.hidden), ' +
    '#zoneNewModal:not(.hidden), #zoneDelModal:not(.hidden), #pwModal:not(.hidden), ' +
    '#pwResetModal:not(.hidden), #grantModal:not(.hidden), #onboardingModal:not(.hidden), #weaponModal:not(.hidden)'
  );
  if (!subOpen) {
    e.preventDefault();
    e.stopImmediatePropagation();
    closePanel();
  }
}, true);

let currentFeatures = [];
let currentPlayers = [];
let currentState = 'rp';

let skinData = { rp: [], admin: [], private: [] };
let currentSkinTab = 'rp';
let personalStorageData = { vehicle: [], cosmetic: [], chair: [], skin: [], summary: {} };
let personalStorageTab = 'skin';
let myLevel = 0;
let myEffectiveLevel = 0;
let myHasPw = false;
let rebootRemain = -1;
let rebootExecuting = false;
let grantLevel = 1;
let grantTeam = null;
let adminTeamsData = [];

let weaponCatalog = [];
let wpActiveCat = null;
let wpSelected = null;

let grantItemCatalog = [];
let grantMailDraft = null;
let grantMailBusy = false;
let mailboxRows = [];

let vehicleCatalog = [];
let vehicleBrandOrder = [];
let vehicleMajorOrder = [];
let vehiclePerms = { spawn: false, exhibit: false };
let vehSpawnMode = 'preview';
let vehMajorFilter = '';
let vehBrandFilter = '전체';
let vehJobFilter = '전체';
let currentTestName = '';
let currentPreviewModel = '';
let previewUiOn = false;
let exhibitPick = null;
let exhibitCitizenRows = [];
let exhibitLimitedRows = [];
let exhibitFactions = [];
let exhibitAddTarget = 'citizen';
let exhibitListTab = 'citizen';
let exhibitPhotoMode = false;
let exhibitImageByModel = {};

const PREVIEW_COLORS = [
  ['오션레드', 122, 31, 43], ['블랙', 22, 24, 28], ['화이트', 235, 235, 238], ['실버', 174, 180, 187],
  ['블루', 36, 58, 94], ['그린', 47, 61, 42], ['오렌지', 214, 106, 0], ['옐로우', 240, 190, 20], ['퍼플', 74, 45, 110],
];

let shellTabs = [];
let activeRoot = 'user';
let isAdminUser = false;
const ROOT_PANE = { admin: 'paneAdmin', user: 'paneUser', job: 'paneJob' };

function fmtWon(n) {
  return '$' + Number(n || 0).toLocaleString();
}

function fmtNum(n) {
  return Number(n || 0).toLocaleString();
}

function setRootTab(key) {
  if (!shellTabs.some((t) => t.key === key)) return;
  activeRoot = key;
  document.querySelectorAll('#rootTabs .ck-root-tab').forEach((b) =>
    b.classList.toggle('active', b.dataset.root === key));
  Object.keys(ROOT_PANE).forEach((k) => {
    const el = document.getElementById(ROOT_PANE[k]);
    if (el) el.classList.toggle('hidden', k !== key);
  });
  const slider = document.querySelector('.ck-admin-hslider[data-for-tabs="rightTabs"]');
  if (slider && key !== 'admin') slider.classList.add('hidden');
  const rightTabs = document.getElementById('rightTabs');
  if (rightTabs && key === 'admin') rightTabs.dispatchEvent(new Event('scroll'));
}

const ROLE_DESC = {
  admin: '관리 도구, 좌표, 차량, 팩션, 로그',
  user: '내 정보와 소속, 플레이 시간',
  job: '직업, 근무, 무장',
};

function showRolePick() {
  const wrap = document.getElementById('rolePick');
  const panel = document.getElementById('panelWrap');
  if (wrap) wrap.classList.add('hidden');
  if (panel) panel.classList.remove('hidden');
}

(function wireRolePickClose() {
  const btn = document.getElementById('rolePickClose');
  if (btn) btn.addEventListener('click', () => closePanel());
})();

function renderRootTabs() {
  const bar = document.getElementById('rootTabs');
  if (!bar) return;
  bar.innerHTML = '';
  shellTabs.forEach((t) => {
    const b = document.createElement('button');
    b.className = 'ck-root-tab';
    b.dataset.root = t.key;
    b.textContent = t.label;
    b.addEventListener('click', () => setRootTab(t.key));
    bar.appendChild(b);
  });
  bar.classList.toggle('hidden', shellTabs.length < 2);
}

function uRow(k, v) {
  return '<div class="ck-info-row"><span>' + escapeHtml(k) + '</span><span>' + v + '</span></div>';
}

const ME_ICONS = {
  skin:    '<path d="M8 4h8l4 3-2.5 3L16 9v11H8V9l-1.5 1L4 7z"/>',
  vehicle: '<path d="M5 11l1.5-4h11L19 11"/><rect x="3" y="11" width="18" height="7" rx="2"/><circle cx="7" cy="18" r="1.5"/><circle cx="17" cy="18" r="1.5"/><path d="M6 14h.01M18 14h.01"/>',
  cosmetic:'<path d="M12 3l1.4 4.1L18 8.5l-3.5 2.5 1.3 4.2-3.8-2.4-3.8 2.4 1.3-4.2L6 8.5l4.6-1.4z"/><path d="M4 18h16M7 21h10"/>',
  chair:   '<path d="M7 4v9h10V4M6 13h12v4H6zM8 17v4M16 17v4"/>',

  org:     '<path d="M3 20h18M5 20V8l5-3 5 3v12M9 12h2m-2 4h2m4-4h1m-1 4h1"/>',
  title:   '<path d="M12 3l2.6 5.6 6.1.8-4.5 4.2 1.2 6-5.4-3-5.4 3 1.2-6L3.3 9.4l6.1-.8z"/>',
  fish:    '<path d="M4 12c3-5 8-6 13-3l4-3v12l-4-3c-5 3-10 2-13-3z"/><circle cx="14" cy="10" r="1"/><path d="M4 12l-2-3v6z"/>',
  navi:    '<circle cx="12" cy="12" r="9"/><path d="M15.5 8.5l-2 5.2-5.2 2 2-5.2z"/>',
  mail:    '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 7l9 6 9-6"/>',
  suggest: '<path d="M21 15a2 2 0 0 1-2 2H8l-5 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
  heart:   '<path d="M20.8 6.6a5 5 0 0 0-7.1 0L12 8.3l-1.7-1.7a5 5 0 0 0-7.1 7.1l8.8 8.8 8.8-8.8a5 5 0 0 0 0-7.1z"/>',
  shop:    '<path d="M3 6h18l-1.5 12.5a2 2 0 0 1-2 1.5H6.5a2 2 0 0 1-2-1.5z"/><path d="M8 6V4a4 4 0 0 1 8 0v2"/>',
  check:   '<rect x="3" y="4" width="18" height="17" rx="2"/><path d="M8 2v4M16 2v4M3 10h18M9 15l2 2 4-4"/>',
  event:   '<path d="M4 5h16v14H4z"/><path d="M8 3v4M16 3v4M4 9h16"/><path d="M8 13h3v3H8zM14 13h2"/>',
  map:     '<path d="M9 4L3 6v14l6-2 6 2 6-2V4l-6 2z"/><path d="M9 4v14M15 6v14"/>',
  key:     '<rect x="2" y="6" width="20" height="12" rx="2"/><path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M7 14h10"/>',
  gear:    '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1A1.7 1.7 0 0 0 9 19.4a1.7 1.7 0 0 0-1.9.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.9 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1A1.7 1.7 0 0 0 4.6 9a1.7 1.7 0 0 0-.3-1.9l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.9.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.9-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.9V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
};

function meIcon(name) {
  const body = ME_ICONS[name] || ME_ICONS.gear;
  return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" ' +
    'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + body + '</svg>';
}

function renderUserPane(u) {
  const el = document.getElementById('paneUser');
  if (!el) return;
  if (!u) { el.innerHTML = '<div class="ck-skin-empty">정보를 불러올 수 없습니다</div>'; return; }

  const hasSkins = skinData && ((skinData.rp || []).length > 0);
  const mug = myMugshotData ? '<img src="' + myMugshotData + '" alt="">' : '';

  let roleRows = '';
  if (factionData) {
    roleRows =
      '<div class="ck-info-row"><span>소속</span><span>' + escapeHtml(factionData.name) + '</span></div>' +
      '<div class="ck-info-row"><span>계급</span><span>' + escapeHtml(factionData.myRank || '-') + '</span></div>';
  } else {
    roleRows =
      '<div class="ck-info-row"><span>직업</span><span>' + escapeHtml(u.jobDisplay || '백수') + '</span></div>';
  }

  const groups = [
    {
      cap: '플레이', items: [
        { id: 'uSkinBtn', title: '한정 인벤토리', icon: 'skin' },
        { id: 'uJobLevelBtn', title: '직업 레벨', icon: 'title' },
        { id: 'uFishDexBtn', title: '도감', icon: 'fish' },
        { id: 'uFacBtn', title: '소속 대시보드', icon: 'org' },
        { id: 'uTitleBtn', title: '칭호', icon: 'title' },
      ]
    },
    {
      cap: '커뮤니티', items: [
        { id: 'uMailBtn', title: '우편함', icon: 'mail' },
        { id: 'uCoupleBtn', title: '커플 시스템', icon: 'heart' },
      ]
    },
    {
      cap: '상점 · 이벤트', items: [
        { id: 'uShopBtn', title: '쿠키 상점', icon: 'shop', soon: true },
        { id: 'uEventBtn', title: '이벤트', icon: 'event' },
        { id: 'uAttendanceBtn', title: '출석체크', icon: 'check' },
        { id: 'uQuestBtn', title: '퀘스트', icon: 'check' },
      ]
    },
    {
      cap: '시스템', items: [
        { id: 'uMapBtn', title: '지도', icon: 'map' },
        { id: 'uCrossBtn', title: '크로스헤어', icon: 'gear' },
        { id: 'uKeyBtn', title: '키 가이드', icon: 'key' },
        { id: 'uCfgBtn', title: '게임설정', icon: 'gear' },
      ]
    },
  ];

  const groupCols = groups.map((g) =>
    '<div class="ck-mg">' +
      '<p class="ck-mg-cap">' + escapeHtml(g.cap) + '</p>' +
      g.items.map((f) =>
        '<button class="ck-mg-btn" id="' + f.id + '"' + (f.soon ? ' data-soon="1"' : '') + '>' +
          '<span class="ck-mg-ico">' + meIcon(f.icon) + '</span>' +
          '<span class="ck-mg-title">' + escapeHtml(f.title) + '</span>' +
        '</button>'
      ).join('') +
    '</div>'
  ).join('');

  el.innerHTML =
    '<div class="ck-mepane">' +
      '<aside class="ck-me-side">' +
        '<p class="ck-label">나의 유저 정보</p>' +
        '<div class="ck-me-card">' +
          '<div class="ck-me-avatar">' + mug + '</div>' +
          '<p class="ck-me-nick">' + escapeHtml(u.nickname || '-') + '</p>' +
        '</div>' +
        '<div class="ck-info">' +
          '<div class="ck-info-row"><span>고정번호</span>' +
            '<span>' + (u.gobun != null ? (escapeHtml(String(u.gobun)) + '번') : '-') + '</span></div>' +
          roleRows +
          '<div class="ck-info-row"><span>RP 시간</span><span>' + formatTime(u.rpMinute || 0) + '</span></div>' +
          '<div class="ck-info-row"><span>근무 시간</span><span>' + formatTime(u.jobMinute || 0) + '</span></div>' +
          '<div class="ck-info-row"><span>현금</span><span>' + fmtWon(u.cash) + '</span></div>' +
          '<div class="ck-info-row"><span>계좌</span><span>' + fmtWon(u.bank) + '</span></div>' +
        '</div>' +
      '</aside>' +
      '<section class="ck-me-main">' +
        '<div class="ck-mg-grid">' + groupCols + '</div>' +
      '</section>' +
    '</div>';

  el.querySelectorAll('.ck-mg-btn[data-soon]').forEach((b) => {
    b.addEventListener('click', () => showToast('아직 제작중입니다', true));
  });

  const jobLvBtn = document.getElementById('uJobLevelBtn');
  if (jobLvBtn) jobLvBtn.addEventListener('click', () => {
    openJobLevelModal();
  });

  const fishDexBtn = document.getElementById('uFishDexBtn');
  if (fishDexBtn) fishDexBtn.addEventListener('click', () => {
    fishCollectionData = null;
    miningCollectionData = null;
    collectionDexTab = 'fish';
    openFishCollectionModal();
    fetch('https://cookie_admin/requestFishingCollection', {
      method: 'POST', headers: {'Content-Type':'application/json'}, body: '{}'
    }).catch(() => {});
    fetch('https://cookie_admin/requestMiningCollection', {
      method: 'POST', headers: {'Content-Type':'application/json'}, body: '{}'
    }).catch(() => {});
  });

  const eventBtn = document.getElementById('uEventBtn');
  if (eventBtn) eventBtn.addEventListener('click', () => {
    openCookieEventHub('event', false, false);
  });

  const attendanceBtn = document.getElementById('uAttendanceBtn');
  if (attendanceBtn) attendanceBtn.addEventListener('click', () => {
    openCookieEventHub('attendance_daily', false, false);
  });

  const questBtn = document.getElementById('uQuestBtn');
  if (questBtn) questBtn.addEventListener('click', () => {
    openCookieEventHub('quest_daily', false, false);
  });

  const mailBtn = document.getElementById('uMailBtn');
  if (mailBtn) mailBtn.addEventListener('click', () => {
    openMailboxModal();
  });

  const keyGuideBtn = document.getElementById('uKeyBtn');
  if (keyGuideBtn) keyGuideBtn.addEventListener('click', () => {
    openKeyGuideModal();
  });

  const coupleBtn = document.getElementById('uCoupleBtn');
  if (coupleBtn) coupleBtn.addEventListener('click', () => {
    openCoupleModal();
  });

  function openJobLevelModal() {
    const old=document.getElementById('ckJobLevelModal'); if(old) old.remove();
    const rows=(jobLevelsData||[]).map(j=>{
      const exp=Number(j.exp||0), need=Number(j.requiredExp||j.nextExp||0);
      const maxLv=Number(j.maxLevel||1), lv=Number(j.level||1);
      const atMax=lv>=maxLv;
      const auto=!!j.autoLevel;
      const levelStart=Number(j.levelExp||0);
      const pct=atMax?100:(auto
        ? (need>levelStart?Math.max(0,Math.min(100,Math.round((exp-levelStart)/(need-levelStart)*100))):0)
        : (need>0?Math.max(0,Math.min(100,Math.round(exp/need*100))):0));
      const item=(j.requiredItem||'').trim();
      const itemCount=Number(j.requiredItemCount||0);
      const needText=atMax?'최대 레벨':('다음 레벨까지 '+fmtNum(Math.max(0,need-exp))+' EXP 필요');
      const itemText=auto
        ? '활동 성공 시 숙련도 EXP가 자동으로 누적됩니다.'
        : (atMax?'':(item && itemCount>0 ? ('승급 아이템 '+escapeHtml(item)+' × '+fmtNum(itemCount)) : '승급 아이템 없음'));
      const can=!!j.canLevel && !atMax && !auto;
      const statLabel=escapeHtml(j.statLabel||'완료');
      return '<div class="ck-jlv-card">'+
        '<div class="ck-jlv-head"><span class="ck-jlv-name">'+escapeHtml((j.emoji||'💼')+' '+j.label)+'</span><b>LV '+lv+' / '+maxLv+'</b></div>'+
        '<div class="ck-jlv-bar"><i style="width:'+pct+'%"></i></div>'+
        '<div class="ck-jlv-meta"><span>'+ (atMax?'최고 레벨':(fmtNum(exp)+' / '+fmtNum(need)+' EXP')) +'</span><span>'+needText+'</span></div>'+
        (auto
          ? '<div class="ck-jlv-req"><span>'+itemText+'</span><span class="ck-jlv-auto">자동 레벨업</span></div>'
          : (!atMax?'<div class="ck-jlv-req"><span>'+itemText+'</span><button class="ck-jlv-up '+(can?'ready':'')+'" data-joblv="'+escapeHtml(j.key)+'" '+(can?'':'disabled')+'>LV '+(lv+1)+' 승급</button></div>':''))+
        '<div class="ck-jlv-meta"><span>'+statLabel+' '+fmtNum(j.totalJob||0)+'회</span><span>'+(!auto?'누적 '+fmtWon(j.totalPay||0):'활동 숙련도')+'</span></div>'+
      '</div>';
    }).join('');
    const m=document.createElement('div');
    m.id='ckJobLevelModal';m.className='ck-jlv-overlay';
    m.innerHTML='<div class="ck-jlv-modal"><div class="ck-jlv-title"><div><b>직업 레벨</b><span>모든 시민직과 낚시·광질 숙련도를 한 번에 확인할 수 있습니다.</span></div><button id="ckJobLvClose">×</button></div><div class="ck-jlv-list">'+(rows||'<div class="ck-skin-empty">직업 레벨 데이터를 불러오지 못했습니다. F3를 닫았다 다시 열어주세요.</div>')+'</div></div>';
    document.body.appendChild(m);
    document.getElementById('ckJobLvClose').onclick=()=>m.remove();
    m.onclick=e=>{if(e.target===m)m.remove()};
    m.querySelectorAll('[data-joblv]').forEach(b=>b.onclick=()=>{
      if(b.disabled)return;
      b.disabled=true;
      fetch('https://cookie_admin/jobLevelUp',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({jobKey:b.dataset.joblv})}).catch(()=>{b.disabled=false});
    });
  }

  const titleBtn = document.getElementById('uTitleBtn');
  if (titleBtn) titleBtn.addEventListener('click', () => openCookieTitleModal());

  const mapBtn = document.getElementById('uMapBtn');
  if (mapBtn) mapBtn.addEventListener('click', () => {
    // close와 openMap POST가 경쟁하지 않도록 client openMap 콜백이 닫기까지 담당한다.
    fcPost('openMap', {});
  });

  const cfgBtn = document.getElementById('uCfgBtn');
  if (cfgBtn) cfgBtn.addEventListener('click', () => {
    closePanel();
    fcPost('openEsc', {});
  });

  const crossBtn = document.getElementById('uCrossBtn');
  if (crossBtn) crossBtn.addEventListener('click', () => {
    closePanel();
    fcPost('openCrosshair', {});
  });

  const sb = document.getElementById('uSkinBtn');
  if (sb) sb.addEventListener('click', () => openPersonalStorageModal('skin'));

  const fb = document.getElementById('uFacBtn');
  if (fb) fb.addEventListener('click', () => {
    if (!factionData) { showToast('가입 된 소속이 없습니다', true); return; }
    openMyFaction();
  });
}


function openFishCollectionModal() {
  const old = document.getElementById('ckFishCollectionModal');
  if (old) old.remove();
  const m = document.createElement('div');
  m.id = 'ckFishCollectionModal';
  m.className = 'ck-fishdex-overlay';
  m.innerHTML = '<div class="ck-fishdex-modal">' +
    '<div class="ck-fishdex-head"><div><b>도감</b><span>수집한 물고기와 광물을 한곳에서 확인합니다.</span></div><button id="ckFishDexClose">×</button></div>' +
    '<div class="ck-fishdex-tabs"><button data-dex-tab="fish">물고기</button><button data-dex-tab="mineral">광물</button></div>' +
    '<div id="ckFishDexBody" class="ck-fishdex-body"><div class="ck-skin-empty">도감을 불러오는 중입니다...</div></div>' +
  '</div>';
  document.body.appendChild(m);
  document.getElementById('ckFishDexClose').onclick = () => m.remove();
  m.onclick = (e) => { if (e.target === m) m.remove(); };
  m.querySelectorAll('[data-dex-tab]').forEach((b) => {
    b.onclick = () => { collectionDexTab = b.dataset.dexTab || 'fish'; renderFishCollectionModal(); };
  });
  renderFishCollectionModal();
}

function fishDexNum(v, d=2) {
  const n = Number(v || 0);
  return n.toLocaleString('ko-KR', { minimumFractionDigits:d, maximumFractionDigits:d });
}

function renderFishCollectionModal() {
  const body = document.getElementById('ckFishDexBody');
  if (!body) return;
  const modal = document.getElementById('ckFishCollectionModal');
  if (modal) modal.querySelectorAll('[data-dex-tab]').forEach((b) => b.classList.toggle('active', b.dataset.dexTab === collectionDexTab));
  if (collectionDexTab === 'mineral') { renderMiningCollectionBody(body); return; }
  const d = fishCollectionData;
  if (!d || !Array.isArray(d.fish)) {
    body.innerHTML = '<div class="ck-skin-empty">도감을 불러오는 중입니다...</div>';
    return;
  }
  const s = d.summary || {};
  const king = d.king || null;
  const personal = s.personalBest || null;
  const top = '<div class="ck-fishdex-stats">' +
    '<div><span>도감</span><b>'+Number(s.discovered||0)+' / '+Number(s.total||d.fish.length)+'</b></div>'+
    '<div><span>총 포획</span><b>'+Number(s.totalCaught||0).toLocaleString('ko-KR')+'마리</b></div>'+
    '<div><span>내 최고기록</span><b>'+(personal ? escapeHtml(personal.label)+' '+fishDexNum(personal.kg)+'kg' : '-')+'</b></div>'+
    '<div class="king"><span>현재 낚시왕</span><b>'+(king ? escapeHtml(king.nickname||'무명')+' · '+Number(king.recordCount||0)+'종 기록' : '아직 없음')+'</b></div>'+
  '</div>';

  const grades = {};
  d.fish.forEach(f => { const k=f.grade||'etc'; if(!grades[k]) grades[k]={label:f.gradeLabel||k,color:f.gradeColor||'#9aa4b2',rows:[]}; grades[k].rows.push(f); });
  const order = Array.isArray(d.gradeOrder) ? d.gradeOrder : Object.keys(grades);
  const sections = order.filter(k=>grades[k]).map(k=>{
    const g=grades[k];
    const cards=g.rows.map(f=>{
      const seen=!!f.discovered;
      const regionText=(f.regions||[]).join(' · ') || '전 지역';
      if(!seen){
        return '<div class="ck-fishdex-card locked">'+
          '<div class="ck-fishdex-img"><span>?</span></div>'+
          '<div class="ck-fishdex-cardbody"><div class="ck-fishdex-name">미발견</div>'+
          '<div class="ck-fishdex-hint">서식지 힌트 · '+escapeHtml(regionText)+'</div>'+
          '<div class="ck-fishdex-range">무게 범위 '+fishDexNum(f.min)+' ~ '+fishDexNum(f.max)+'kg</div></div></div>';
      }
      const img=f.img ? '<img src="nui://ox_inventory/web/images/'+encodeURIComponent(f.img)+'" alt="">' : '<span>🐟</span>';
      const rec=f.serverRecord;
      return '<div class="ck-fishdex-card">'+
        '<div class="ck-fishdex-img">'+img+'</div>'+
        '<div class="ck-fishdex-cardbody">'+
          '<div class="ck-fishdex-name">'+escapeHtml(f.label)+'</div>'+
          '<div class="ck-fishdex-hint">'+escapeHtml(regionText)+'</div>'+
          '<div class="ck-fishdex-records">'+
            '<span>내 기록 <b>'+fishDexNum(f.personalBest)+'kg</b></span>'+
            '<span>포획 <b>'+Number(f.caughtCount||0).toLocaleString('ko-KR')+'회</b></span>'+
            '<span>서버 기록 <b>'+(rec ? fishDexNum(rec.kg)+'kg · '+escapeHtml(rec.nickname||'무명') : '-')+'</b></span>'+
          '</div>'+
        '</div></div>';
    }).join('');
    return '<section class="ck-fishdex-grade"><div class="ck-fishdex-gradehead"><i style="background:'+escapeHtml(g.color)+'"></i><b>'+escapeHtml(g.label)+'</b><span>'+g.rows.filter(x=>x.discovered).length+' / '+g.rows.length+'</span></div><div class="ck-fishdex-grid">'+cards+'</div></section>';
  }).join('');

  body.innerHTML = top + sections;
}


function renderMiningCollectionBody(body) {
  const d = miningCollectionData;
  if (!d || !Array.isArray(d.minerals)) {
    body.innerHTML = '<div class="ck-skin-empty">광물 도감을 불러오는 중입니다...</div>';
    return;
  }
  const s = d.summary || {};
  const personal = s.personalBest || null;
  const top = '<div class="ck-fishdex-stats ck-minedex-stats">' +
    '<div><span>광물 도감</span><b>'+Number(s.discovered||0)+' / '+Number(s.total||d.minerals.length)+'</b></div>'+
    '<div><span>총 채굴</span><b>'+Number(s.totalMined||0).toLocaleString('ko-KR')+'개</b></div>'+
    '<div><span>내 최고 순도</span><b>'+(personal ? escapeHtml(personal.label)+' '+Number(personal.purity||0)+'%' : '-')+'</b></div>'+
    '<div><span>최고 품질</span><b>'+(personal ? escapeHtml(personal.qualityLabel||'-') : '-')+'</b></div>'+
  '</div>';

  const groups = {};
  d.minerals.forEach(m => {
    const k=m.rarity||'etc';
    if(!groups[k]) groups[k]={label:m.rarityLabel||k,color:m.rarityColor||'#9aa4b2',rows:[]};
    groups[k].rows.push(m);
  });
  const order=Array.isArray(d.rarityOrder)?d.rarityOrder:Object.keys(groups);
  const sections=order.filter(k=>groups[k]).map(k=>{
    const g=groups[k];
    const cards=g.rows.map(m=>{
      if(!m.discovered){
        return '<div class="ck-fishdex-card locked ck-mineral-card">'+
          '<div class="ck-fishdex-img"><span>?</span></div>'+
          '<div class="ck-fishdex-cardbody"><div class="ck-fishdex-name">미발견</div>'+
          '<div class="ck-fishdex-hint">'+escapeHtml(m.rarityLabel||'-')+' 광물</div>'+
          '<div class="ck-fishdex-range">채굴하면 도감에 등록됩니다.</div></div></div>';
      }
      return '<div class="ck-fishdex-card ck-mineral-card">'+
        '<div class="ck-fishdex-img ck-mineral-gem"><span>◆</span></div>'+
        '<div class="ck-fishdex-cardbody">'+
          '<div class="ck-fishdex-name">'+escapeHtml(m.label)+'</div>'+
          '<div class="ck-fishdex-hint">'+escapeHtml(m.rarityLabel||'-')+' 광물</div>'+
          '<div class="ck-fishdex-records">'+
            '<span>최고 순도 <b>'+Number(m.bestPurity||0)+'%</b></span>'+
            '<span>최고 품질 <b>'+escapeHtml(m.bestQualityLabel||'-')+'</b></span>'+
            '<span>채굴 <b>'+Number(m.minedCount||0).toLocaleString('ko-KR')+'회</b></span>'+
          '</div></div></div>';
    }).join('');
    return '<section class="ck-fishdex-grade"><div class="ck-fishdex-gradehead"><i style="background:'+escapeHtml(g.color)+'"></i><b>'+escapeHtml(g.label)+'</b><span>'+g.rows.filter(x=>x.discovered).length+' / '+g.rows.length+'</span></div><div class="ck-fishdex-grid">'+cards+'</div></section>';
  }).join('');
  body.innerHTML=top+sections;
}

function renderAdminDash(d) {
  const el = document.getElementById('paneDash');
  if (!el) return;

  if (!d || !d.me) {
    el.innerHTML = '<div class="ck-skin-empty">관리자 정보를 불러올 수 없습니다</div>';
    return;
  }

  const me = d.me;
  const onDuty = me.state === 'duty';
  const players = (d.players && d.players.length) || 0;

  const totalMin = me.totalMinute || 0;
  const dutyMin = me.dutyMinute || 0;
  const rpMin = Math.max(0, totalMin - dutyMin);

  const stat = (label, value, sub) =>
    '<div class="ck-dash-stat">' +
      '<p class="ck-dash-k">' + escapeHtml(label) + '</p>' +
      '<p class="ck-dash-v">' + value + '</p>' +
      (sub ? '<p class="ck-dash-s">' + sub + '</p>' : '') +
    '</div>';

  el.innerHTML =
    '<div class="ck-dash-hero' + (onDuty ? ' on' : '') + '">' +
      '<p class="ck-dash-hello">' + escapeHtml(me.name || '관리자') + ' 님</p>' +
      '<p class="ck-dash-state">' +
        (onDuty ? '지금 관리 업무 중입니다' : '지금은 일반 플레이 중입니다') +
      '</p>' +
    '</div>' +
    '<div class="ck-dash-grid">' +
      stat('내 레벨', 'LV' + (me.level || 0), escapeHtml(LEVEL_NAME[me.level] || '-')) +
      stat('접속 중인 플레이어', players + '<small>명</small>') +
      stat('RP 시간', formatTime(rpMin), '총 ' + formatTime(totalMin)) +
      stat('관리 시간', formatTime(dutyMin)) +
    '</div>' +
    '<p class="ck-dash-cap">바로가기</p>' +
    '<div class="ck-dash-links" id="dashLinks"></div>';

  const links = document.getElementById('dashLinks');
  document.querySelectorAll('#rightTabs .ck-rtab').forEach((t) => {
    const key = t.dataset.pane;
    if (key === 'dash') return;
    if (t.classList.contains('hidden')) return;

    const b = document.createElement('button');
    b.className = 'ck-feat';
    b.innerHTML =
      '<span class="ck-feat-main">' +
        '<span class="ck-feat-title"></span>' +
      '</span><span class="ck-feat-arrow">›</span>';
    b.querySelector('.ck-feat-title').textContent = t.textContent;
    b.addEventListener('click', () => t.click());
    links.appendChild(b);
  });
}

function renderJobPane(j) {
  const el = document.getElementById('paneJob');
  if (!el) return;
  if (!j) { el.innerHTML = '<div class="ck-skin-empty">직업 정보가 없습니다</div>'; return; }

  const civil = !!j.isCivil;

  let rows =
    '<div class="ck-info-row"><span>직업</span><span>' + escapeHtml(j.name || '-') + '</span></div>';
  if (civil) {
    rows += '<div class="ck-info-row"><span>근무형태</span><span>' + escapeHtml(j.employ || '위촉직') + '</span></div>';
  } else {
    rows += '<div class="ck-info-row"><span>계급</span><span>' + escapeHtml(j.grade || '-') + '</span></div>';
  }
  rows += '<div class="ck-info-row"><span>근무</span><span>' + (j.onDuty ? '근무 중' : '비번') + '</span></div>';
  rows += '<div class="ck-info-row"><span>급여</span><span>' +
    (civil ? '프리랜서' : fmtWon(j.salary)) + '</span></div>';


  el.innerHTML =
    '<div class="ck-upane">' +
      '<div class="ck-ucard">' +
        '<p class="ck-label">직업</p>' + rows +
      '</div>' +
    '</div>';
}

const KO_DAYS = ['일', '월', '화', '수', '목', '금', '토'];

function fmtDate(v) {
  if (!v) return '-';
  let d;
  if (typeof v === 'number') d = new Date(v);
  else if (/^\d{10,}$/.test(String(v))) d = new Date(Number(v));
  else d = new Date(String(v).replace(' ', 'T'));
  if (isNaN(d.getTime())) return String(v);

  const y = d.getFullYear();
  const mo = String(d.getMonth() + 1).padStart(2, '0');
  const da = String(d.getDate()).padStart(2, '0');
  let h = d.getHours();
  const ap = h < 12 ? '오전' : '오후';
  h = h % 12; if (h === 0) h = 12;
  const mi = String(d.getMinutes()).padStart(2, '0');
  return y + '년' + mo + '월' + da + '일 (' + KO_DAYS[d.getDay()] + ') ' + ap + ' ' + h + ':' + mi;
}

let myMugshotData = null;
let jobLevelsData = [];
let fishCollectionData = null;
let miningCollectionData = null;
let collectionDexTab = 'fish';
let factionData = null;




let COOKIE_KEY_GUIDE = [];
let COOKIE_KEY_GUIDE_CATEGORIES = [];
let activeKeyGuideCategoryId = null;
let keyGuideAdminData = { categories: [], factions: [] };

const COOKIE_KEYBOARD_KEY_OPTIONS = [
  'ESC','F1','F2','F3','F4','F5','F6','F7','F8','F9','F10','F11','F12',
  'PRINT SCREEN','SCROLL LOCK','PAUSE',
  '`','1','2','3','4','5','6','7','8','9','0','-','=','BACKSPACE',
  'TAB','Q','W','E','R','T','Y','U','I','O','P','[',']','\\',
  'CAPS LOCK','A','S','D','F','G','H','J','K','L',';','\'','ENTER',
  'LEFT SHIFT','Z','X','C','V','B','N','M',',','.','/','RIGHT SHIFT',
  'LEFT CTRL','LEFT WIN','LEFT ALT','SPACE','RIGHT ALT','RIGHT WIN','MENU','RIGHT CTRL',
  'INSERT','HOME','PAGE UP','DELETE','END','PAGE DOWN','UP','LEFT','DOWN','RIGHT',
  'NUM LOCK','NUM /','NUM *','NUM -','NUM 7','NUM 8','NUM 9','NUM +',
  'NUM 4','NUM 5','NUM 6','NUM 1','NUM 2','NUM 3','NUM ENTER','NUM 0','NUM .'
];

const COOKIE_KEYBOARD_ALIASES = {
  'BACK':'BACKSPACE','BKSP':'BACKSPACE',
  'CAPS':'CAPS LOCK','CAPSLOCK':'CAPS LOCK',
  'SHIFT':'LEFT SHIFT','LSHIFT':'LEFT SHIFT','RSHIFT':'RIGHT SHIFT',
  'CTRL':'LEFT CTRL','CONTROL':'LEFT CTRL','LCTRL':'LEFT CTRL','RCTRL':'RIGHT CTRL',
  'ALT':'LEFT ALT','LALT':'LEFT ALT','RALT':'RIGHT ALT',
  'WIN':'LEFT WIN','LWIN':'LEFT WIN','RWIN':'RIGHT WIN',
  'PGUP':'PAGE UP','PAGEUP':'PAGE UP','PGDN':'PAGE DOWN','PAGEDOWN':'PAGE DOWN',
  'DEL':'DELETE','INS':'INSERT',
  'PRTSC':'PRINT SCREEN','PRT SCR':'PRINT SCREEN','PRTSCR':'PRINT SCREEN','PRINTSCREEN':'PRINT SCREEN',
  'SCRLK':'SCROLL LOCK','SCROLLLOCK':'SCROLL LOCK','BREAK':'PAUSE',
  'ARROWUP':'UP','ARROWDOWN':'DOWN','ARROWLEFT':'LEFT','ARROWRIGHT':'RIGHT',
  'NUMPAD0':'NUM 0','NUMPAD1':'NUM 1','NUMPAD2':'NUM 2','NUMPAD3':'NUM 3','NUMPAD4':'NUM 4',
  'NUMPAD5':'NUM 5','NUMPAD6':'NUM 6','NUMPAD7':'NUM 7','NUMPAD8':'NUM 8','NUMPAD9':'NUM 9',
  'NUMPADENTER':'NUM ENTER','NUMENTER':'NUM ENTER','NUMPAD+':'NUM +','NUMPADPLUS':'NUM +',
  'NUMPAD-':'NUM -','NUMPADMINUS':'NUM -','NUMPAD*':'NUM *','NUMPADMULTIPLY':'NUM *',
  'NUMPAD/':'NUM /','NUMPADDIVIDE':'NUM /','NUMPAD.':'NUM .','NUMPADDECIMAL':'NUM .',
  'NUMLOCK':'NUM LOCK'
};

const COOKIE_KEYBOARD_FUNCTION = [
  {k:'ESC',w:1.15,gapAfter:.8},
  {k:'F1'},{k:'F2'},{k:'F3'},{k:'F4',gapAfter:.45},
  {k:'F5'},{k:'F6'},{k:'F7'},{k:'F8',gapAfter:.45},
  {k:'F9'},{k:'F10'},{k:'F11'},{k:'F12',gapAfter:.65},
  {k:'PRINT SCREEN',label:'Prt Sc',w:1.18},{k:'SCROLL LOCK',label:'Scr Lk',w:1.18},{k:'PAUSE',label:'Pause',w:1.18}
];

const COOKIE_KEYBOARD_MAIN = [
  [
    {k:'`',label:'~\n`'},{k:'1',label:'!\n1'},{k:'2',label:'@\n2'},{k:'3',label:'#\n3'},{k:'4',label:'$\n4'},
    {k:'5',label:'%\n5'},{k:'6',label:'^\n6'},{k:'7',label:'&\n7'},{k:'8',label:'*\n8'},{k:'9',label:'(\n9'},
    {k:'0',label:')\n0'},{k:'-',label:'_\n-'},{k:'=',label:'+\n='},{k:'BACKSPACE',label:'Backspace',w:2.0}
  ],
  [
    {k:'TAB',label:'Tab',w:1.5},{k:'Q'},{k:'W'},{k:'E'},{k:'R'},{k:'T'},{k:'Y'},{k:'U'},{k:'I'},{k:'O'},{k:'P'},
    {k:'[',label:'{\n['},{k:']',label:'}\n]'},{k:'\\',label:'|\n\\',w:1.5}
  ],
  [
    {k:'CAPS LOCK',label:'Caps Lock',w:1.8},{k:'A'},{k:'S'},{k:'D'},{k:'F'},{k:'G'},{k:'H'},{k:'J'},{k:'K'},{k:'L'},
    {k:';',label:':\n;'},{k:"'",label:'"\n\''},{k:'ENTER',label:'Enter',w:2.2}
  ],
  [
    {k:'LEFT SHIFT',label:'Shift',w:2.3},{k:'Z'},{k:'X'},{k:'C'},{k:'V'},{k:'B'},{k:'N'},{k:'M'},
    {k:',',label:'<\n,'},{k:'.',label:'>\n.'},{k:'/',label:'?\n/'},{k:'RIGHT SHIFT',label:'Shift',w:2.7}
  ],
  [
    {k:'LEFT CTRL',label:'Ctrl',w:1.45},{k:'LEFT WIN',label:'Win',w:1.2},{k:'LEFT ALT',label:'Alt',w:1.2},
    {k:'SPACE',label:'',w:6.25},{k:'RIGHT ALT',label:'Alt',w:1.2},{k:'RIGHT WIN',label:'Win',w:1.2},
    {k:'MENU',label:'Menu',w:1.2},{k:'RIGHT CTRL',label:'Ctrl',w:1.45}
  ]
];

const COOKIE_KEYBOARD_NAV = [
  [{k:'INSERT',label:'Insert'},{k:'HOME',label:'Home'},{k:'PAGE UP',label:'Pg Up'}],
  [{k:'DELETE',label:'Delete'},{k:'END',label:'End'},{k:'PAGE DOWN',label:'Pg Dn'}],
  [{spacer:true},{spacer:true},{spacer:true}],
  [{spacer:true},{k:'UP',label:'▲'},{spacer:true}],
  [{k:'LEFT',label:'◀'},{k:'DOWN',label:'▼'},{k:'RIGHT',label:'▶'}]
];

const COOKIE_KEYBOARD_NUMPAD = [
  {k:'NUM LOCK',label:'Num\nLock',col:1,row:1},{k:'NUM /',label:'/',col:2,row:1},{k:'NUM *',label:'*',col:3,row:1},{k:'NUM -',label:'−',col:4,row:1},
  {k:'NUM 7',label:'7\nHome',col:1,row:2},{k:'NUM 8',label:'8\n▲',col:2,row:2},{k:'NUM 9',label:'9\nPgUp',col:3,row:2},{k:'NUM +',label:'+',col:4,row:2,h:2},
  {k:'NUM 4',label:'4\n◀',col:1,row:3},{k:'NUM 5',label:'5',col:2,row:3},{k:'NUM 6',label:'6\n▶',col:3,row:3},
  {k:'NUM 1',label:'1\nEnd',col:1,row:4},{k:'NUM 2',label:'2\n▼',col:2,row:4},{k:'NUM 3',label:'3\nPgDn',col:3,row:4},{k:'NUM ENTER',label:'Enter',col:4,row:4,h:2},
  {k:'NUM 0',label:'0\nIns',col:1,row:5,w:2},{k:'NUM .',label:'.\nDel',col:3,row:5}
];

function normalizeGuideKey(key){
  let k=String(key||'').trim().toUpperCase().replace(/\s+/g,' ');
  const compact=k.replace(/\s+/g,'');
  return COOKIE_KEYBOARD_ALIASES[k]||COOKIE_KEYBOARD_ALIASES[compact]||k;
}

function keyOptionDatalistHtml(){
  return '<datalist id="ckKeyGuideKeyOptions">'+COOKIE_KEYBOARD_KEY_OPTIONS.map(k=>'<option value="'+escapeHtml(k)+'"></option>').join('')+'</datalist>';
}


function closeKeyGuideModal(){
  document.getElementById('ckKeyGuideModal')?.remove();
}

function keyGuideInfo(key){
  const wanted=normalizeGuideKey(key);
  return COOKIE_KEY_GUIDE.find(x=>normalizeGuideKey(x.key)===wanted)||null;
}


function keyboardKeyHtml(item, extraClass){
  if(item?.spacer)return '<span class="ck-mech-key-spacer"></span>';
  const info=keyGuideInfo(item.k);
  const active=!!info;
  const style=[
    `--key-w:${item.w||1}`,
    `--key-h:${item.h||1}`,
    item.gapAfter?`--key-gap:${item.gapAfter}`:'',
    item.col?`grid-column:${item.col} / span ${item.w||1}`:'',
    item.row?`grid-row:${item.row} / span ${item.h||1}`:''
  ].filter(Boolean).join(';');
  const label=String(item.label ?? item.k).split('\n').map(x=>'<span>'+escapeHtml(x)+'</span>').join('');
  return '<button type="button" class="ck-mech-key '+(extraClass||'')+' '+(active?('is-bound '+escapeHtml(info.tone||'default')):'')+'" '+
    'data-mech-key="'+escapeHtml(item.k)+'" style="'+style+'">'+
      '<span class="ck-keycap-top">'+label+'</span>'+
      (active?'<i class="ck-key-led"></i>':'')+
    '</button>';
}

function updateMechanicalKeyInfo(key){
  const info=keyGuideInfo(key);
  const panel=document.getElementById('ckMechInfo');
  if(!panel)return;

  document.querySelectorAll('.ck-mech-key').forEach(el=>{
    el.classList.toggle('selected',normalizeGuideKey(el.dataset.mechKey)===normalizeGuideKey(key) && !!info);
  });

  if(!info){
    panel.innerHTML=
      '<div class="ck-mech-info-empty"><span>UNASSIGNED KEY</span><b>'+escapeHtml(key)+'</b>'+
      '<small>현재 선택한 가이드에 등록되지 않은 키입니다.</small></div>';
    return;
  }

  panel.innerHTML=
    '<div class="ck-mech-info-key '+escapeHtml(info.tone||'default')+'">'+escapeHtml(info.key)+'</div>'+
    '<div class="ck-mech-info-copy"><span>COOKIE KEY BIND</span><b>'+escapeHtml(info.title)+'</b>'+
    '<small>'+escapeHtml(info.desc||'')+'</small></div>';
}

function setKeyGuideCategory(categoryId){
  const cat=COOKIE_KEY_GUIDE_CATEGORIES.find(c=>Number(c.id)===Number(categoryId))||COOKIE_KEY_GUIDE_CATEGORIES[0]||null;
  activeKeyGuideCategoryId=cat?.id??null;
  COOKIE_KEY_GUIDE=Array.isArray(cat?.items)?cat.items:[];
  renderKeyGuideCategoryTabs();
  renderMechanicalKeyboard();
}

function renderKeyGuideCategoryTabs(){
  const tabs=document.getElementById('ckKeyCategoryTabs');
  if(!tabs)return;
  tabs.innerHTML=COOKIE_KEY_GUIDE_CATEGORIES.map(cat=>
    '<button type="button" class="ck-key-category-tab '+(Number(cat.id)===Number(activeKeyGuideCategoryId)?'active':'')+
    '" data-key-category="'+Number(cat.id)+'">'+
      '<span>'+escapeHtml(cat.icon||'⌨️')+'</span><b>'+escapeHtml(cat.label||'단축키')+'</b>'+
    '</button>'
  ).join('');

  tabs.querySelectorAll('[data-key-category]').forEach(btn=>{
    btn.addEventListener('click',()=>setKeyGuideCategory(Number(btn.dataset.keyCategory)));
  });
}

function renderMechanicalKeyboard(){
  const layout=document.getElementById('ckMechLayout');
  const list=document.getElementById('ckMechBoundList');
  if(!layout||!list)return;

  renderKeyGuideCategoryTabs();

  const fnRow='<div class="ck-mech-function-row">'+COOKIE_KEYBOARD_FUNCTION.map(k=>keyboardKeyHtml(k,'function-key')).join('')+'</div>';
  const mainRows=COOKIE_KEYBOARD_MAIN.map(row=>'<div class="ck-mech-row">'+row.map(k=>keyboardKeyHtml(k)).join('')+'</div>').join('');
  const navRows=COOKIE_KEYBOARD_NAV.map(row=>'<div class="ck-mech-nav-row">'+row.map(k=>keyboardKeyHtml(k,'nav-key')).join('')+'</div>').join('');
  const numpad=COOKIE_KEYBOARD_NUMPAD.map(k=>keyboardKeyHtml(k,'numpad-key')).join('');

  layout.innerHTML=
    fnRow+
    '<div class="ck-mech-full-body">'+
      '<div class="ck-mech-main-block">'+mainRows+'</div>'+
      '<div class="ck-mech-nav-block">'+navRows+'</div>'+
      '<div class="ck-mech-numpad-block">'+numpad+'</div>'+
    '</div>';

  list.innerHTML=COOKIE_KEY_GUIDE.length?COOKIE_KEY_GUIDE.map(item=>
    '<button type="button" class="ck-mech-bound-item '+escapeHtml(item.tone||'default')+'" data-bound-key="'+escapeHtml(item.key)+'">'+
      '<kbd>'+escapeHtml(item.key)+'</kbd>'+
      '<span><b>'+escapeHtml(item.title)+'</b><small>'+escapeHtml(item.desc||'')+'</small></span>'+
    '</button>'
  ).join(''):'<div class="ck-key-category-empty">이 버튼에 등록된 단축키가 없습니다.</div>';

  layout.querySelectorAll('.ck-mech-key').forEach(btn=>{
    btn.addEventListener('click',()=>{
      btn.classList.add('pressed');
      setTimeout(()=>btn.classList.remove('pressed'),130);
      updateMechanicalKeyInfo(btn.dataset.mechKey);
    });
  });

  list.querySelectorAll('[data-bound-key]').forEach(btn=>{
    btn.addEventListener('click',()=>{
      const key=btn.dataset.boundKey;
      const keyboardKey=[...layout.querySelectorAll('.ck-mech-key')].find(
        x=>normalizeGuideKey(x.dataset.mechKey)===normalizeGuideKey(key)
      );
      if(keyboardKey){
        keyboardKey.classList.add('pressed');
        setTimeout(()=>keyboardKey.classList.remove('pressed'),130);
      }
      updateMechanicalKeyInfo(key);
    });
  });

  updateMechanicalKeyInfo(COOKIE_KEY_GUIDE[0]?.key||'P');
}

function openKeyGuideModal(){
  closeKeyGuideModal();

  const modal=document.createElement('div');
  modal.id='ckKeyGuideModal';
  modal.className='ck-key-overlay ck-key-mechanical-overlay';
  modal.innerHTML=
    '<div class="ck-mechanical-modal">'+
      '<div class="ck-key-head ck-mech-head">'+
        '<div><span>COOKIE CONTROL CENTER</span><b>기계식 키 가이드</b>'+
        '<small>내가 사용할 수 있는 카테고리만 표시됩니다. 버튼을 바꿔 단축키를 확인하세요.</small></div>'+
        '<button id="ckKeyGuideClose" type="button">×</button>'+
      '</div>'+
      '<div class="ck-key-category-tabs" id="ckKeyCategoryTabs"><span>불러오는 중…</span></div>'+
      '<div class="ck-mech-body">'+
        '<div class="ck-mech-board-wrap"><div class="ck-mech-board">'+
          '<div class="ck-mech-board-brand"><span>COOKIE</span><b>MECHANICAL 104 FULL SIZE</b><i></i></div>'+
          '<div class="ck-mech-rgb-strip"></div>'+
          '<div id="ckMechLayout" class="ck-mech-layout"><div class="ck-mech-loading">키 설정을 불러오는 중…</div></div>'+
          '<div class="ck-mech-case-bottom"><span>COOKIE SERVER</span><i>ROLE BASED CONTROL GUIDE</i></div>'+
        '</div></div>'+
        '<div class="ck-mech-lower"><div id="ckMechInfo" class="ck-mech-info"></div>'+
        '<div id="ckMechBoundList" class="ck-mech-bound-list"></div></div>'+
      '</div>'+
      keyOptionDatalistHtml()+
    '</div>';

  document.body.appendChild(modal);
  document.getElementById('ckKeyGuideClose')?.addEventListener('click',closeKeyGuideModal);
  modal.addEventListener('mousedown',e=>{if(e.target===modal)closeKeyGuideModal();});

  COOKIE_KEY_GUIDE=[];
  COOKIE_KEY_GUIDE_CATEGORIES=[];
  activeKeyGuideCategoryId=null;
  fetch('https://cookie_admin/requestKeyGuide',{
    method:'POST',headers:{'Content-Type':'application/json'},body:'{}'
  }).catch(()=>{});
}

function keyGuideFactionOptions(selected){
  const set=new Set((selected||[]).map(Number));
  return (keyGuideAdminData.factions||[]).map(f=>
    '<label class="ck-keycat-faction-chip">'+
      '<input type="checkbox" value="'+Number(f.id)+'" '+(set.has(Number(f.id))?'checked':'')+'>'+
      '<span>'+escapeHtml((f.emoji?f.emoji+' ':'')+(f.name||f.key||('팩션 '+f.id)))+'</span>'+
    '</label>'
  ).join('')||'<span class="ck-keycat-no-faction">활성 팩션이 없습니다.</span>';
}

function keyGuideAdminItemHtml(row,index){
  return '<div class="ck-keyadm-row" data-key-row data-id="'+(row.id||'')+'">'+
    '<div class="ck-keyadm-order">'+String(index+1).padStart(2,'0')+'</div>'+
    '<label>키<input class="ck-keyadm-key" list="ckKeyGuideKeyOptions" maxlength="24" value="'+escapeHtml(row.key||'')+'" placeholder="예: G"></label>'+
    '<label>기능명<input class="ck-keyadm-title" maxlength="50" value="'+escapeHtml(row.title||'')+'" placeholder="예: 수갑"></label>'+
    '<label class="wide">설명<input class="ck-keyadm-desc" maxlength="160" value="'+escapeHtml(row.desc||'')+'" placeholder="유저에게 보일 설명"></label>'+
    '<label>색상<select class="ck-keyadm-tone">'+
      ['default','phone','menu','chat','info','voice','warning','police','medical','mechanic'].map(t=>
        '<option value="'+t+'" '+((row.tone||'default')===t?'selected':'')+'>'+t+'</option>'
      ).join('')+
    '</select></label>'+
    '<label class="ck-keyadm-enabled"><input class="ck-keyadm-active" type="checkbox" '+(row.enabled!==false?'checked':'')+'><span>표시</span></label>'+
    '<div class="ck-keyadm-actions">'+
      '<button type="button" class="ck-keyadm-up" title="위로">↑</button>'+
      '<button type="button" class="ck-keyadm-down" title="아래로">↓</button>'+
      '<button type="button" class="ck-keyadm-remove" title="삭제">×</button>'+
    '</div>'+
  '</div>';
}

function keyGuideCategoryHtml(cat,index){
  const mode=cat.visibilityMode==='factions'?'factions':'all';
  const items=Array.isArray(cat.items)?cat.items:[];
  return '<section class="ck-keycat-card" data-keycat data-id="'+(cat.id||'')+'" data-category-key="'+escapeHtml(cat.categoryKey||'')+'">'+
    '<div class="ck-keycat-top">'+
      '<div class="ck-keycat-order">'+String(index+1).padStart(2,'0')+'</div>'+
      '<label>아이콘<input class="ck-keycat-icon" maxlength="16" value="'+escapeHtml(cat.icon||'⌨️')+'" placeholder="🚓"></label>'+
      '<label>버튼 이름<input class="ck-keycat-label" maxlength="60" value="'+escapeHtml(cat.label||'')+'" placeholder="예: 경찰 단축키"></label>'+
      '<label>테마<select class="ck-keycat-tone">'+
        ['default','phone','menu','chat','info','voice','warning','police','medical','mechanic'].map(t=>
          '<option value="'+t+'" '+((cat.tone||'default')===t?'selected':'')+'>'+t+'</option>'
        ).join('')+
      '</select></label>'+
      '<label>공개 대상<select class="ck-keycat-mode">'+
        '<option value="all" '+(mode==='all'?'selected':'')+'>모든 유저</option>'+
        '<option value="factions" '+(mode==='factions'?'selected':'')+'>선택한 팩션만</option>'+
      '</select></label>'+
      '<label class="ck-keyadm-enabled"><input class="ck-keycat-active" type="checkbox" '+(cat.enabled!==false?'checked':'')+'><span>버튼 표시</span></label>'+
      '<div class="ck-keycat-actions">'+
        '<button type="button" class="ck-keycat-up" title="위로">↑</button>'+
        '<button type="button" class="ck-keycat-down" title="아래로">↓</button>'+
        '<button type="button" class="ck-keycat-remove" title="버튼 삭제">×</button>'+
      '</div>'+
    '</div>'+
    '<div class="ck-keycat-factions '+(mode==='factions'?'':'hidden')+'">'+
      '<b>이 버튼을 볼 수 있는 팩션</b><div class="ck-keycat-faction-list">'+keyGuideFactionOptions(cat.factionIds)+'</div>'+
    '</div>'+
    '<div class="ck-keycat-items-head"><div><b>단축키 목록</b><small>이 버튼을 눌렀을 때 유저에게 표시되는 키들입니다.</small></div>'+
      '<button type="button" class="ck-keycat-add-item">+ 키 추가</button></div>'+
    '<div class="ck-keyadm-list" data-key-items>'+
      items.map((row,i)=>keyGuideAdminItemHtml(row,i)).join('')+
    '</div>'+
  '</section>';
}

function renderKeyGuideAdmin(){
  const body=document.getElementById('keyGuideSysBody');
  if(!body)return;

  if(!keyGuideAdminData||!Array.isArray(keyGuideAdminData.categories)){
    body.innerHTML='<div class="ck-skin-empty">설정을 불러오는 중…</div>';
    return;
  }

  body.innerHTML=
    keyOptionDatalistHtml()+
    '<div class="ck-keyadm-note"><b>권한형 키 가이드</b><span><strong>버튼마다 공개할 팩션을 선택</strong>할 수 있습니다. 선택되지 않은 팩션/일반 시민에게는 해당 버튼 자체가 보이지 않습니다. 실제 FiveM 키 바인딩은 각 기능 리소스 설정을 따릅니다.</span></div>'+
    '<div id="ckKeyCatRows" class="ck-keycat-list">'+
      keyGuideAdminData.categories.map((cat,index)=>keyGuideCategoryHtml(cat,index)).join('')+
    '</div>';

  bindKeyGuideAdmin();
}

function bindKeyGuideItemRows(scope){
  (scope||document).querySelectorAll('[data-key-row]').forEach(row=>{
    if(row.dataset.bound==='1')return;
    row.dataset.bound='1';

    row.querySelector('.ck-keyadm-remove')?.addEventListener('click',()=>{
      const wrap=row.parentElement;
      row.remove();
      renumberKeyGuideItems(wrap);
    });
    row.querySelector('.ck-keyadm-up')?.addEventListener('click',()=>{
      const wrap=row.parentElement, prev=row.previousElementSibling;
      if(prev)wrap.insertBefore(row,prev);
      renumberKeyGuideItems(wrap);
    });
    row.querySelector('.ck-keyadm-down')?.addEventListener('click',()=>{
      const wrap=row.parentElement, next=row.nextElementSibling;
      if(next)wrap.insertBefore(next,row);
      renumberKeyGuideItems(wrap);
    });
  });
}

function renumberKeyGuideItems(wrap){
  if(!wrap)return;
  wrap.querySelectorAll(':scope > [data-key-row]').forEach((row,index)=>{
    const num=row.querySelector('.ck-keyadm-order');
    if(num)num.textContent=String(index+1).padStart(2,'0');
  });
}

function renumberKeyGuideCategories(){
  document.querySelectorAll('#ckKeyCatRows > [data-keycat]').forEach((cat,index)=>{
    const num=cat.querySelector('.ck-keycat-order');
    if(num)num.textContent=String(index+1).padStart(2,'0');
  });
}

function bindKeyGuideAdmin(){
  const wrap=document.getElementById('ckKeyCatRows');
  if(!wrap)return;

  wrap.querySelectorAll('[data-keycat]').forEach(cat=>{
    if(cat.dataset.bound!=='1'){
      cat.dataset.bound='1';

      cat.querySelector('.ck-keycat-mode')?.addEventListener('change',e=>{
        cat.querySelector('.ck-keycat-factions')?.classList.toggle('hidden',e.target.value!=='factions');
      });

      cat.querySelector('.ck-keycat-remove')?.addEventListener('click',()=>{
        if(!confirm('이 버튼과 안의 단축키를 모두 삭제할까요?'))return;
        cat.remove();
        renumberKeyGuideCategories();
      });

      cat.querySelector('.ck-keycat-up')?.addEventListener('click',()=>{
        const prev=cat.previousElementSibling;
        if(prev)wrap.insertBefore(cat,prev);
        renumberKeyGuideCategories();
      });

      cat.querySelector('.ck-keycat-down')?.addEventListener('click',()=>{
        const next=cat.nextElementSibling;
        if(next)wrap.insertBefore(next,cat);
        renumberKeyGuideCategories();
      });

      cat.querySelector('.ck-keycat-add-item')?.addEventListener('click',()=>{
        const items=cat.querySelector('[data-key-items]');
        if(!items)return;
        const tmp=document.createElement('div');
        tmp.innerHTML=keyGuideAdminItemHtml({key:'',title:'',desc:'',tone:cat.querySelector('.ck-keycat-tone')?.value||'default',enabled:true},items.children.length);
        const row=tmp.firstElementChild;
        items.appendChild(row);
        bindKeyGuideItemRows(cat);
        renumberKeyGuideItems(items);
        row.querySelector('.ck-keyadm-key')?.focus();
      });
    }

    bindKeyGuideItemRows(cat);
  });
}

function collectKeyGuideAdmin(){
  return {
    categories:[...document.querySelectorAll('#ckKeyCatRows > [data-keycat]')].map((cat,index)=>{
      const mode=cat.querySelector('.ck-keycat-mode')?.value||'all';
      const factionIds=mode==='factions'
        ? [...cat.querySelectorAll('.ck-keycat-faction-list input[type="checkbox"]:checked')].map(x=>Number(x.value)).filter(Boolean)
        : [];

      let categoryKey=(cat.dataset.categoryKey||'').trim();
      if(!categoryKey){
        const label=(cat.querySelector('.ck-keycat-label')?.value||'').trim().toLowerCase();
        categoryKey=label.replace(/[^a-z0-9가-힣]+/g,'_').replace(/^_+|_+$/g,'')||('guide_'+Date.now()+'_'+index);
      }

      return {
        id:Number(cat.dataset.id)||null,
        categoryKey,
        icon:(cat.querySelector('.ck-keycat-icon')?.value||'').trim(),
        label:(cat.querySelector('.ck-keycat-label')?.value||'').trim(),
        tone:cat.querySelector('.ck-keycat-tone')?.value||'default',
        visibilityMode:mode,
        factionIds,
        enabled:!!cat.querySelector('.ck-keycat-active')?.checked,
        items:[...cat.querySelectorAll('[data-key-items] > [data-key-row]')].map(row=>({
          id:Number(row.dataset.id)||null,
          key:(row.querySelector('.ck-keyadm-key')?.value||'').trim(),
          title:(row.querySelector('.ck-keyadm-title')?.value||'').trim(),
          desc:(row.querySelector('.ck-keyadm-desc')?.value||'').trim(),
          tone:row.querySelector('.ck-keyadm-tone')?.value||'default',
          enabled:!!row.querySelector('.ck-keyadm-active')?.checked,
        }))
      };
    })
  };
}

document.getElementById('keyGuideAdd')?.addEventListener('click',()=>{
  const wrap=document.getElementById('ckKeyCatRows');
  if(!wrap)return;

  const tmp=document.createElement('div');
  tmp.innerHTML=keyGuideCategoryHtml({
    categoryKey:'',
    label:'새 단축키',
    icon:'⌨️',
    tone:'default',
    visibilityMode:'all',
    factionIds:[],
    enabled:true,
    items:[]
  },wrap.children.length);

  const cat=tmp.firstElementChild;
  wrap.appendChild(cat);
  bindKeyGuideAdmin();
  renumberKeyGuideCategories();
  cat.querySelector('.ck-keycat-label')?.focus();
});

document.getElementById('keyGuideSysSave')?.addEventListener('click',()=>{
  const b=document.getElementById('keyGuideSysSave');
  b.disabled=true;b.textContent='저장 중…';
  fetch('https://cookie_admin/saveKeyGuideAdmin',{
    method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify(collectKeyGuideAdmin())
  }).catch(()=>{
    b.disabled=false;b.textContent='저장';
  });
});

let coupleData = null;
let coupleBuyBusy = false;
let coupleLoadToken = 0;
let couplePendingBreakup = false;
let coupleProposalTimer = null;
let coupleInteractionData = null;
let coupleProposalData = null;

function coupleMoney(v){
  return Number(v||0).toLocaleString('ko-KR') + '원';
}
function coupleDateText(value){
  if(!value)return '-';
  const d=new Date(String(value).replace(' ','T'));
  if(Number.isNaN(d.getTime()))return String(value).slice(0,10);
  return `${d.getFullYear()}.${String(d.getMonth()+1).padStart(2,'0')}.${String(d.getDate()).padStart(2,'0')}`;
}
function closeCoupleModal(){
  document.getElementById('ckCoupleModal')?.remove();
  coupleData=null;
  couplePendingBreakup=false;
}
function openCoupleModal(){
  closeCoupleModal();
  coupleBuyBusy=false;
  const m=document.createElement('div');
  m.id='ckCoupleModal';
  m.className='ck-couple-overlay';
  m.innerHTML=
    '<div class="ck-couple-modal">'+
      '<div class="ck-couple-head">'+
        '<div><span>COOKIE RELATIONSHIP</span><b>커플 시스템</b><small>도시에서 만난 소중한 사람과 오늘부터 함께 기록하세요.</small></div>'+
        '<button id="ckCoupleClose">×</button>'+
      '</div>'+
      '<div id="ckCoupleBody"><div class="ck-couple-loading">커플 정보를 불러오는 중…</div></div>'+
    '</div>';
  document.body.appendChild(m);
  document.getElementById('ckCoupleClose').onclick=closeCoupleModal;
  m.addEventListener('mousedown',e=>{if(e.target===m)closeCoupleModal();});

  // 서버 응답 전에도 구매 영역 자체는 보이게 한다.
  coupleData={shopEnabled:false,ringPrice:0,ringCount:0,me:{name:'불러오는 중',gobun:null},relationship:null};
  renderCoupleModal();
  const pre=document.getElementById('ckCoupleBuyRing');
  if(pre){pre.disabled=true;pre.textContent='커플링 상점 불러오는 중…';}

  const token=++coupleLoadToken;
  const requestCoupleState=(attempt)=>{
    fetch('https://cookie_admin/requestCouple',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})
      .catch(()=>{})
      .finally(()=>{
        setTimeout(()=>{
          if(token!==coupleLoadToken||coupleData?.ringPrice>0||coupleData?.relationship)return;
          if(attempt<3){
            requestCoupleState(attempt+1);
          }else{
            const buy=document.getElementById('ckCoupleBuyRing');
            if(buy){
              buy.disabled=false;
              buy.textContent='상점 연결 다시 시도';
              buy.onclick=()=>{
                buy.disabled=true;
                buy.textContent='다시 불러오는 중…';
                requestCoupleState(1);
              };
            }
            showToast('커플 시스템 응답이 없습니다. 서버의 cookie_admin 콘솔 오류를 확인해주세요.',true);
          }
        },1800);
      });
  };
  requestCoupleState(1);
}
function coupleRingShopHtml(d){
  const enabled=!!d.shopEnabled;
  return '<div class="ck-couple-shop ck-couple-shop-primary">'+
    '<div class="ck-couple-shop-head"><div><span>COOKIE RING SHOP</span><b>커플링 구매</b><small>고백에 사용할 반지를 준비하세요.</small></div><strong>'+coupleMoney(d.ringPrice||0)+'</strong></div>'+
    '<div class="ck-couple-shop-content">'+
      '<div><span>보유 중인 반지</span><b>'+Number(d.ringCount||0)+'개</b></div>'+
      '<div><span>결제 방식</span><b>은행 계좌</b></div>'+
      '<div><span>고백 키</span><b>CAPSLOCK</b></div>'+
    '</div>'+
    '<button id="ckCoupleBuyRing" class="ck-couple-buy" '+(enabled?'':'disabled')+'>'+(enabled?('커플링 구매 · '+coupleMoney(d.ringPrice||0)):'현재 판매 중지')+'</button>'+
    '<p class="ck-couple-ring-warning">구매한 커플링은 상대방을 바라보고 CAPSLOCK → 고백하기에서 사용합니다.</p>'+
  '</div>';
}
function bindCoupleRingBuy(d){
  const buy=document.getElementById('ckCoupleBuyRing');
  if(!buy)return;
  buy.addEventListener('click',()=>{
    if(coupleBuyBusy||!d.shopEnabled)return;
    coupleBuyBusy=true;
    buy.disabled=true;
    buy.textContent='구매 처리 중…';
    fetch('https://cookie_admin/buyCoupleRing',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).catch(()=>{
      coupleBuyBusy=false;
      buy.disabled=false;
      buy.textContent='커플링 구매 · '+coupleMoney(d.ringPrice||0);
    });
  });
}

function renderCoupleModal(){
  const body=document.getElementById('ckCoupleBody');
  if(!body||!coupleData)return;
  const d=coupleData;
  const rel=d.relationship;

  if(rel){
    body.innerHTML=
      '<div class="ck-couple-together">'+
        '<div class="ck-couple-hearts"><i>♥</i><i>♥</i><i>♥</i></div>'+
        '<span>TOGETHER</span>'+
        '<strong>'+Number(rel.days||1)+'일차</strong>'+
        '<p>'+escapeHtml(d.me?.name||'나')+' <b>♥</b> '+escapeHtml(rel.partner?.name||'연인')+'</p>'+
        '<small>'+coupleDateText(rel.startedAt)+'부터 함께하고 있어요.</small>'+
      '</div>'+
      '<div class="ck-couple-info-grid">'+
        '<div><span>내 이름</span><b>'+escapeHtml(d.me?.name||'-')+'</b><small>'+(d.me?.gobun!=null?'고번 '+escapeHtml(String(d.me.gobun)):'-')+'</small></div>'+
        '<div><span>나의 연인</span><b>'+escapeHtml(rel.partner?.name||'-')+'</b><small>'+(rel.partner?.gobun!=null?'고번 '+escapeHtml(String(rel.partner.gobun)):'-')+'</small></div>'+
      '</div>'+
      '<div class="ck-couple-nametag-preview"><span>머리 위 표시</span><div><b>현재 직업</b><em>♥ '+escapeHtml(rel.partner?.name||'-')+'님 연인</em><strong>'+escapeHtml(d.me?.name||'-')+'</strong></div></div>'+
      '<button id="ckCoupleBreakup" class="ck-couple-breakup" type="button">연인 관계 해제</button>'+
      '<p class="ck-couple-breakup-note">관계를 해제하면 두 사람의 머리 위 연인 표시가 즉시 사라집니다.</p>';

    document.getElementById('ckCoupleBreakup')?.addEventListener('click',()=>{
      if(!couplePendingBreakup){
        couplePendingBreakup=true;
        const b=document.getElementById('ckCoupleBreakup');
        b.textContent='정말 관계를 해제하시겠습니까? 다시 눌러 확인';
        b.classList.add('confirm');
        setTimeout(()=>{
          if(couplePendingBreakup){
            couplePendingBreakup=false;
            if(b){b.textContent='연인 관계 해제';b.classList.remove('confirm');}
          }
        },7000);
        return;
      }
      couplePendingBreakup=false;
      fetch('https://cookie_admin/breakupCouple',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).catch(()=>{});
    });
    return;
  }

  body.innerHTML=
    coupleRingShopHtml(d)+
    '<div class="ck-couple-single-hero">'+
      '<div class="ck-couple-ring-visual"><span>◇</span><i>♥</i></div>'+
      '<div><span>CURRENT STATUS</span><b>아직 솔로입니다.</b><small>커플링을 준비하고 마음에 드는 상대에게 고백해보세요.</small></div>'+
    '</div>'+
    '<div class="ck-couple-guide">'+
      '<b>고백하는 방법</b>'+
      '<div><i>1</i><span>F3 커플 시스템에서 커플링을 구매합니다.</span></div>'+
      '<div><i>2</i><span>커플링을 가진 상태로 가까운 상대방을 바라봅니다.</span></div>'+
      '<div><i>3</i><span><b>CAPSLOCK</b>을 누르고 <b>고백하기</b>를 선택합니다.</span></div>'+
      '<div><i>4</i><span>상대방이 수락하면 그 순간부터 두 사람의 1일차가 시작됩니다.</span></div>'+
    '</div>';

  bindCoupleRingBuy(d);
}

function closeCoupleInteraction(){
  document.getElementById('ckCoupleInteraction')?.remove();
  coupleInteractionData=null;
  fetch('https://cookie_admin/coupleInteractionClose',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).catch(()=>{});
}
function showCoupleInteraction(data){
  document.getElementById('ckCoupleInteraction')?.remove();
  coupleInteractionData=data||{};
  const el=document.createElement('div');
  el.id='ckCoupleInteraction';
  el.className='ck-couple-action-overlay';
  el.innerHTML=
    '<div class="ck-couple-action-card">'+
      '<button id="ckCoupleActionClose">×</button>'+
      '<span>COUPLE INTERACTION</span>'+
      '<h3>'+escapeHtml(data.name||'상대방')+'</h3>'+
      '<small>'+(data.gobun!=null?'고번 '+escapeHtml(String(data.gobun)):'가까운 시민')+'</small>'+
      '<div class="ck-couple-action-ring">◇ <b>커플링 '+Number(data.ringCount||0)+'개 보유</b></div>'+
      '<button id="ckCoupleConfess" class="ck-couple-confess">♥ 고백하기</button>'+
      '<p>고백하면 상대방에게 수락 / 거절 선택창이 나타납니다.</p>'+
    '</div>';
  document.body.appendChild(el);
  document.getElementById('ckCoupleActionClose').onclick=closeCoupleInteraction;
  el.addEventListener('mousedown',e=>{if(e.target===el)closeCoupleInteraction();});
  document.getElementById('ckCoupleConfess').onclick=()=>{
    const target=Number(coupleInteractionData?.target);
    if(!target)return;
    document.getElementById('ckCoupleConfess').disabled=true;
    document.getElementById('ckCoupleConfess').textContent='고백 전달 중…';
    fetch('https://cookie_admin/sendCoupleProposal',{
      method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({target})
    }).catch(()=>{});
  };
}

function closeCoupleProposal(){
  if(coupleProposalTimer){clearInterval(coupleProposalTimer);coupleProposalTimer=null;}
  document.getElementById('ckCoupleProposal')?.remove();
  coupleProposalData=null;
}
function showCoupleProposal(data){
  closeCoupleProposal();
  coupleProposalData=data||{};
  const el=document.createElement('div');
  el.id='ckCoupleProposal';
  el.className='ck-couple-proposal-overlay';
  el.innerHTML=
    '<div class="ck-couple-proposal-card">'+
      '<div class="ck-couple-proposal-heart">♥</div>'+
      '<span>SOMEONE LIKES YOU</span>'+
      '<h2>'+escapeHtml(data.name||'누군가')+'님이 고백하셨습니다.</h2>'+
      '<p>당신의 답변을 기다리고 있습니다.</p>'+
      '<div class="ck-couple-proposal-timer"><i id="ckCoupleProposalGauge"></i></div>'+
      '<small id="ckCoupleProposalSec">'+Number(data.seconds||30)+'초 안에 선택해주세요.</small>'+
      '<div class="ck-couple-proposal-actions">'+
        '<button id="ckCoupleReject">거절</button>'+
        '<button id="ckCoupleAccept">♥ 수락</button>'+
      '</div>'+
    '</div>';
  document.body.appendChild(el);

  let left=Number(data.seconds||30);
  const gauge=document.getElementById('ckCoupleProposalGauge');
  const sec=document.getElementById('ckCoupleProposalSec');
  coupleProposalTimer=setInterval(()=>{
    left=Math.max(0,left-1);
    if(gauge)gauge.style.width=((left/Math.max(1,Number(data.seconds||30)))*100)+'%';
    if(sec)sec.textContent=left+'초 안에 선택해주세요.';
    if(left<=0){clearInterval(coupleProposalTimer);coupleProposalTimer=null;}
  },1000);

  const reply=(accepted)=>{
    document.getElementById('ckCoupleReject').disabled=true;
    document.getElementById('ckCoupleAccept').disabled=true;
    fetch('https://cookie_admin/replyCoupleProposal',{
      method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({id:Number(data.id),accepted:!!accepted})
    }).catch(()=>{});
  };
  document.getElementById('ckCoupleReject').onclick=()=>reply(false);
  document.getElementById('ckCoupleAccept').onclick=()=>reply(true);
}
let attendanceData = null;
let attendanceClaimBusy = false;

function attendanceRewardText(r) {
  if (!r) return '보상 미설정';
  if (r.label && r.label !== '보상 미설정') return r.label;
  if (r.type === 'bank') return '계좌 ' + fmtWon(r.amount || 0);
  if (r.type === 'cash') return '현금 ' + fmtWon(r.amount || 0);
  if (r.type === 'item') return (r.itemName || '아이템') + ' × ' + (Number(r.itemCount) || 0);
  return '보상 미설정';
}

function attendanceRewardIcon(r) {
  if (!r) return '•';
  if (r.type === 'bank') return '₩';
  if (r.type === 'cash') return '₩';
  if (r.type === 'item') return '◆';
  return '·';
}

function closeAttendanceModal() {
  const m = document.getElementById('ckAttendanceModal');
  if (m) m.remove();
}

function openAttendanceModal() {
  // V14: 출석체크는 이벤트 허브 안으로 통합되었습니다.
  openCookieEventHub('attendance', false);
}

function renderAttendanceModal() {
  const body = document.getElementById('ckAttendBody');
  if (!body || !attendanceData) return;

  const d = attendanceData.monthly || attendanceData;
  const claimed = d.claimed || {};
  const rewards = Array.isArray(d.rewards) ? d.rewards : [];
  const nextDay = Number(d.nextDay || 1);
  const progress = Math.max(0, Math.min(28, Number(d.claimedCount || 0)));

  const cards = [];
  for (let day = 1; day <= 28; day++) {
    const r = rewards.find(x => Number(x.day) === day) || { day, type: 'none', label: '보상 미설정' };
    const isClaimed = !!claimed[String(day)];
    const isNext = !isClaimed && day === nextDay && progress < 28;
    const isFuture = !isClaimed && day > nextDay;
    const bonus = day % 7 === 0;

    let state = '';
    if (isClaimed) state = 'claimed';
    else if (isNext) state = 'today';
    else if (isFuture) state = 'locked';

    const status = isClaimed
      ? '<span class="ck-att-state done">완료</span>'
      : isNext
        ? '<span class="ck-att-state today">NEXT</span>'
        : '<span class="ck-att-state">대기</span>';

    cards.push(
      '<div class="ck-att-day ' + state + (bonus ? ' bonus' : '') + '">' +
        '<div class="ck-att-day-top"><b>' + day + '일차</b>' + status + '</div>' +
        '<div class="ck-att-reward-icon">' + attendanceRewardIcon(r) + '</div>' +
        '<div class="ck-att-reward">' + escapeHtml(attendanceRewardText(r)) + '</div>' +
        (bonus ? '<div class="ck-att-bonus">WEEK BONUS</div>' : '') +
        (isClaimed ? '<div class="ck-att-check">✓</div>' : '') +
      '</div>'
    );
  }

  let claimText = '오늘 출석 완료';
  if (d.canClaim) claimText = nextDay + '일차 보상 받기';
  else if (progress >= 28) claimText = '28일 출석 완료';
  else if (!d.enabled) claimText = '출석체크 비활성화';

  body.innerHTML =
    '<div class="ck-att-summary">' +
      '<div><span>' + escapeHtml(d.cycleLabel || '-') + '</span><b>' + escapeHtml(d.title || '월간 출석 체크') + '</b><small>빠뜨린 날이 있어도 보상 순서는 건너뛰지 않습니다.</small></div>' +
      '<div class="ck-att-progress"><strong>' + progress + '</strong><span>/ 28</span></div>' +
    '</div>' +
    '<div class="ck-att-progressbar"><i style="width:' + Math.round(progress / 28 * 100) + '%"></i></div>' +
    '<div class="ck-att-grid">' + cards.join('') + '</div>' +
    '<div class="ck-att-bottom">' +
      '<div class="ck-att-note">' + escapeHtml(d.reason || '오늘 받을 수 있는 출석 보상이 있습니다.') + '</div>' +
      '<button id="ckAttendClaim" class="ck-att-claim" ' + (d.canClaim ? '' : 'disabled') + '>' + claimText + '</button>' +
    '</div>';

  const claim = document.getElementById('ckAttendClaim');
  if (claim) claim.onclick = () => {
    if (!d.canClaim || attendanceClaimBusy) return;
    attendanceClaimBusy = true;
    claim.disabled = true;
    claim.textContent = '보상 지급 중…';
    fetch('https://cookie_admin/claimAttendance', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({mode:'monthly'})
    }).catch(() => {
      attendanceClaimBusy = false;
      claim.disabled = false;
    });
  };
}

let factionView = 'dash';
let factionAdminData = [];
let factionTypesData = [];
let canFactionManage = false;
let myAdminName = '';

const CAD_NAV = [
  { sec: '개요' },
  { key: 'dash', label: '대시보드' },
  { sec: '인사' },
  { key: 'members', label: '팩션원' },
  { sec: '자원' },
  { key: 'vehicles', label: '팩션 차량' },
  { sec: '기록' },
  { key: 'detentions', label: '구금 기록' },
  { key: 'budget', label: '예산', officer: true },
  { sec: '작전' },
  { key: 'incidents', label: '사건', soon: true },
  { key: 'reports', label: '보고서', soon: true },
  { key: 'warrants', label: '영장', soon: true },
  { key: 'bolo', label: '수배', soon: true },
  { key: 'dispatch', label: '배치', soon: true },
];

function cadList(arr, cols, empty) {
  if (!arr || !arr.length) return '<div class="ck-skin-empty">' + empty + '</div>';
  return '<div class="ck-cad-list">' + arr.map(cols).join('') + '</div>';
}

function cadRow(left, right, cls) {
  return '<div class="ck-cad-row"><span>' + left + '</span>' +
    '<span class="' + (cls || '') + '">' + right + '</span></div>';
}

function memberName(m) {
  return (m.nickname && m.nickname !== '') ? m.nickname : (m.citizenid || '-');
}

function memberRowHtml(m, clickable) {
  const dep = m.department ? '<b class="ck-cad-tag">' + escapeHtml(m.department) + '</b>' : '';
  const rank = escapeHtml(m.rank_name || ('G' + m.grade));
  const inner = '<span>' + escapeHtml(memberName(m)) + dep + '</span><span>' + rank + '</span>';
  if (!clickable) return '<div class="ck-cad-row">' + inner + '</div>';
  return '<button class="ck-cad-row ck-cad-mrow" data-cid="' + escapeHtml(m.citizenid) + '">' + inner + '</button>';
}

const BUDGET_CAT = {
  deposit: '입금', withdraw: '출금', purchase: '차량 구매',
  fine_income: '벌금 수입', admin_add: '관리자 추가', admin_take: '관리자 회수',
};

function ledgerLeft(b) {
  const cat = BUDGET_CAT[b.category] || b.category || '기타';
  const who = b.actor_nick || b.actor_citizenid || '알 수 없음';

  let why = (b.reason || '').replace(/^\[관리자\]\s*/, '');
  if (why === cat) why = '';

  return '<span class="ck-led-cat">' + escapeHtml(cat) + '</span>' +
    (why ? ' <span class="ck-led-why">' + escapeHtml(why) + '</span>' : '') +
    '<span class="ck-cad-sub ck-led-meta">' + escapeHtml(who) + '　' + fmtDate(b.created_at) + '</span>';
}

function cadCard(title, body, extra) {
  return '<div class="ck-cad-card">' +
    '<div class="ck-cad-card-h">' + escapeHtml(title) + (extra || '') + '</div>' + body + '</div>';
}

function cadMetric(label, value, tone) {
  return '<div class="ck-cad-metric">' +
    '<p class="ck-cad-metric-l">' + escapeHtml(label) + '</p>' +
    '<p class="ck-cad-metric-v ' + (tone || '') + '">' + value + '</p></div>';
}

function cadViewHtml(f) {
  if (factionView === 'ranks') factionView = 'dash';
  const canBudget = (f.isLeader || f.isOfficer) && f.budget != null;

  const canManage = (f.isLeader || f.isOfficer);

  if (factionView === 'members') {
    const hint = '<p class="ck-cad-sub" style="padding:8px 14px 0">팩션원·계급 변경은 관리자 F3 → 서버 팩션 관리에서 처리됩니다.</p>';
    return cadCard('팩션원 (' + (f.members ? f.members.length : 0) + ')',
      hint + cadList(f.members, (m) => memberRowHtml(m, false), '팩션원이 없습니다'));
  }

  if (factionView === 'ranks') {
    const rows = cadList(f.ranks, (r) => {
      const tag = r.is_leader ? '<b class="ck-cad-tag">리더</b>'
        : (r.is_officer ? '<b class="ck-cad-tag">간부</b>' : '');
      const pay = f.isGov ? ('<span>' + fmtWon(r.salary || 0) + '</span>') : '<span class="ck-cad-sub">급여 없음</span>';
      const inner = '<span>' + escapeHtml(r.rank_name) + tag +
        '<span class="ck-cad-sub">G' + r.grade + '</span></span>' + pay;
      return '<div class="ck-cad-row">' + inner + '</div>';
    }, '계급이 없습니다');
    const hint = '<p class="ck-cad-sub" style="padding:8px 14px 0">계급 추가·삭제·급여 설정은 관리자 F3 → 서버 팩션 관리에서 처리됩니다.</p>';
    return cadCard('계급', hint + rows);
  }
  if (factionView === 'vehicles') {

    const ownedModels = {};
    (f.vehicles || []).forEach((v) => { ownedModels[v.model] = true; });

    const rankOfGrade = (g) => {
      const r = (f.ranks || []).find((x) => x.grade === (g || 0));
      return r ? r.rank_name : ('G' + (g || 0));
    };

    if (!canManage || !f.shop) return owned;

    const ranksAsc = (f.ranks || []).slice().sort((a, b) => a.grade - b.grade);
    const rankNameOf = (g) => {
      const r = ranksAsc.find((x) => x.grade === (g || 0));
      return r ? r.rank_name : ('G' + (g || 0));
    };
    const rankOpts = (g) => ranksAsc.map((r) =>
      '<option value="' + r.grade + '"' + (r.grade === (g || 0) ? ' selected' : '') + '>' +
      escapeHtml(r.rank_name) + '</option>').join('');

    const vcard = (s, bought) => {
      const nm = escapeHtml(s.label || s.model);
      const action = bought
        ? '<span class="ck-vcard-owned">구매됨</span>'
        : '<button class="ck-vcard-buy ck-cad-buy" data-sid="' + s.id + '">구매하기</button>';

      const foot = f.isLeader
        ? '<div class="ck-vcard-foot leader">' +
            '<select class="ck-cad-gsel ck-vcard-gsel" data-sid="' + s.id + '">' +
              rankOpts(s.min_grade) + '</select>' +
            '<span class="ck-vcard-footfix">전용</span>' +
          '</div>'
        : '<div class="ck-vcard-foot">' +
            escapeHtml(rankNameOf(s.min_grade)) + ' 전용' +
          '</div>';

      return '<div class="ck-vcard' + (bought ? ' bought' : '') + '">' +
          '<div class="ck-vcard-img">' +
            '<img src="' + (s.image ? s.image : ('img/veh/' + escapeHtml(s.model) + '.png')) + '" alt="" ' +
              'onerror="this.parentNode.classList.add(\'noimg\');this.remove();">' +
          '</div>' +
          '<div class="ck-vcard-body">' +

            '<p class="ck-vcard-name">' + nm + '</p>' +
            '<p class="ck-vcard-price">' + fmtWon(s.price) + '</p>' +
            '<div class="ck-vcard-btns">' +
              action +
              '<button class="ck-vcard-prev ck-cad-prev" data-model="' + escapeHtml(s.model) +
                '" data-name="' + nm + '">미리보기</button>' +
            '</div>' +
          '</div>' +
          foot +
        '</div>';
    };

    const shop = f.shop || [];
    const boughtList = shop.filter((s) => ownedModels[s.model]);
    const buyList = shop.filter((s) => !ownedModels[s.model]);

    const ownedCards = boughtList.length
      ? '<div class="ck-vcards">' + boughtList.map((s) => vcard(s, true)).join('') + '</div>'
      : '<div class="ck-skin-empty">보유한 차량이 없습니다</div>';

    const buyCards = buyList.length
      ? '<div class="ck-vcards">' + buyList.map((s) => vcard(s, false)).join('') + '</div>'
      : '<div class="ck-skin-empty">구매 가능한 차량이 없습니다</div>';

    return cadCard(escapeHtml(f.name) + ' 전용 차량 (' + boughtList.length + ')', ownedCards) +
      cadCard('차량 구매하기', buyCards);
  }
  if (factionView === 'detentions') {
    return cadCard('구금 기록',
      cadList(f.detentions, (d2) => cadRow(
        escapeHtml(d2.target_name || '-') + ' <span class="ck-cad-sub">' + escapeHtml(d2.charge || '-') + '</span>',
        '벌금 ' + fmtWon(d2.fine_amount)), '구금 기록이 없습니다'));
  }
  if (factionView === 'budget') {
    if (!canBudget) return '<div class="ck-skin-empty">예산은 간부 이상만 열람할 수 있습니다</div>';
    const ledger = cadList(f.budgetLog, (b) => cadRow(ledgerLeft(b),
      (b.delta >= 0 ? '+' : '−') + fmtWon(Math.abs(b.delta)),
      b.delta >= 0 ? 'ck-pos' : 'ck-neg'), '내역이 없습니다');
    return '<div class="ck-cad-bal">' +
        '<p class="ck-cad-metric-l">팩션 예산 잔액</p>' +
        '<p class="ck-cad-bal-v">' + fmtWon(f.budget) + '</p>' +
        '<p class="ck-cad-sub">벌금과 구금 등 공직 활동 수입이 이 예산으로 적립됩니다</p>' +
        '<div class="ck-bal-acts">' +
          '<button id="fbDep" class="ck-toss-btn">입금</button>' +
          '<button id="fbWit" class="ck-toss-btn ghost">출금</button>' +
        '</div>' +
      '</div>' +
      cadCard('예산 내역', ledger);
  }

  const recentDet = cadList((f.detentions || []).slice(0, 5), (d2) => cadRow(
    escapeHtml(d2.target_name || '-') + ' <span class="ck-cad-sub">' + escapeHtml(d2.charge || '-') + '</span>',
    '벌금 ' + fmtWon(d2.fine_amount)), '구금 기록이 없습니다');
  const topMembers = cadList((f.members || []).slice(0, 6), (m) => memberRowHtml(m, false), '팩션원이 없습니다');
  const recentLedger = canBudget
    ? cadCard('최근 예산 내역', cadList((f.budgetLog || []).slice(0, 5), (b) => cadRow(
        ledgerLeft(b),
        (b.delta >= 0 ? '+' : '−') + fmtWon(Math.abs(b.delta)),
        b.delta >= 0 ? 'ck-pos' : 'ck-neg'), '내역이 없습니다'))
    : '';

  return '<div class="ck-cad-metrics">' +
      (canBudget ? cadMetric('팩션 예산', fmtWon(f.budget), 'ck-gold') : '') +
      cadMetric('팩션원', String((f.members || []).length) + '명') +
      cadMetric('구금 기록', String((f.detentions || []).length) + '건') +
      cadMetric('내 계급', escapeHtml(f.myRank || '-')) +
    '</div>' +
    '<div class="ck-cad-grid">' +
      cadCard('최근 구금', recentDet) +
      cadCard('팩션원', topMembers) +
      recentLedger +
    '</div>';
}

function renderCadView() {
  const main = document.getElementById('cadMain');
  if (!main || !factionData) return;
  main.innerHTML = cadViewHtml(factionData);

  document.querySelectorAll('#cadNav .ck-cad-navbtn').forEach((b) =>
    b.classList.toggle('active', b.dataset.view === factionView));

  const dep = document.getElementById('fbDep');
  const wit = document.getElementById('fbWit');
  if (dep) dep.addEventListener('click', () => openBudgetDialog('deposit'));
  if (wit) wit.addEventListener('click', () => openBudgetDialog('withdraw'));

  main.querySelectorAll('.ck-cad-mrow').forEach((b) => b.addEventListener('click', () => {
    const m = (factionData.members || []).find((x) => x.citizenid === b.dataset.cid);
    if (m) openMemberDialog(m);
  }));

  main.querySelectorAll('.ck-cad-rrow').forEach((b) => b.addEventListener('click', () => {
    const r = (factionData.ranks || []).find((x) => String(x.grade) === b.dataset.g);
    if (r) openRankDialog(r);
  }));
  const addR = document.getElementById('frAdd');
  if (addR) addR.addEventListener('click', () => openRankDialog(null));

  main.querySelectorAll('.ck-cad-buy').forEach((b) => b.addEventListener('click', () => {
    b.disabled = true;
    fcPost('facBuyVehicle', { id: parseInt(b.dataset.sid, 10) });
  }));

  main.querySelectorAll('.ck-cad-prev').forEach((b) => b.addEventListener('click', () =>
    facPreview(b.dataset.model, b.dataset.name)));

  main.querySelectorAll('.ck-cad-gsel').forEach((sel) => sel.addEventListener('change', () =>
    fcPost('facShopGrade', {
      id: parseInt(sel.dataset.sid, 10),
      grade: parseInt(sel.value, 10),
    })));
}

function openMyFaction() {
  if (!factionData) { showToast('소속된 팩션이 없습니다', true); return; }
  document.getElementById('mfConsole').classList.remove('hidden');
}

function closeMyFaction() {
  const c = document.getElementById('mfConsole');
  if (c) c.classList.add('hidden');
}

let fmCid = null;

function openMemberDialog(m) {
  if (!factionData || !(factionData.isLeader || factionData.isOfficer)) return;
  fmCid = m.citizenid;
  document.getElementById('fmTitle').textContent = memberName(m);
  document.getElementById('fmGrade').innerHTML = (factionData.ranks || []).map((r) =>
    '<option value="' + r.grade + '"' + (r.grade === m.grade ? ' selected' : '') + '>' +
    escapeHtml(r.rank_name) + '</option>').join('');
  document.getElementById('fmDep').innerHTML =
    '<option value="">부서 없음</option>' +
    (factionData.departments || []).map((d) =>
      '<option value="' + escapeHtml(d) + '"' + (d === m.department ? ' selected' : '') + '>' +
      escapeHtml(d) + '</option>').join('');
  document.getElementById('fmModal').classList.remove('hidden');
}

function closeMemberDialog() {
  document.getElementById('fmModal').classList.add('hidden');
  fmCid = null;
}

let frEditing = null;

function openRankDialog(r) {
  if (!factionData || !factionData.isLeader) return;
  frEditing = r || null;
  document.getElementById('frTitle').textContent = r ? '계급 수정' : '계급 추가';
  const g = document.getElementById('frGrade');
  g.value = r ? r.grade : '';
  g.disabled = false;
  document.getElementById('frName').value = r ? r.rank_name : '';
  document.getElementById('frSalary').value = r ? (r.salary || 0) : 0;
  document.getElementById('frOfficer').checked = !!(r && (r.is_officer === 1 || r.is_officer === true));
  document.getElementById('frLeader').checked = !!(r && (r.is_leader === 1 || r.is_leader === true));
  document.getElementById('frDel').classList.toggle('hidden', !r);
  document.getElementById('frModal').classList.remove('hidden');
}

function closeRankDialog() {
  document.getElementById('frModal').classList.add('hidden');
  frEditing = null;
}

let fbMode = 'deposit';

function openBudgetDialog(mode) {
  fbMode = mode;
  const dep = (mode === 'deposit');
  document.getElementById('fbTitle').textContent = dep ? '예산 입금' : '예산 출금';
  document.getElementById('fbSub').textContent = dep ? '얼마를 입금할까요?' : '얼마를 출금할까요?';
  const ok = document.getElementById('fbOk');
  ok.textContent = dep ? '입금하기' : '출금하기';
  ok.classList.toggle('danger', !dep);
  document.getElementById('fbWhyWrap').classList.toggle('hidden', dep);
  document.getElementById('fbConfirm').classList.toggle('hidden', dep);
  document.getElementById('fbAmt').value = '';
  document.getElementById('fbWhy').value = '';
  document.getElementById('fbModal').classList.remove('hidden');
  document.getElementById('fbAmt').focus();
}

function closeBudgetDialog() {
  document.getElementById('fbModal').classList.add('hidden');
}

function submitBudgetDialog() {
  const amt = parseInt(document.getElementById('fbAmt').value, 10);
  const why = document.getElementById('fbWhy').value.trim();
  if (!amt || amt <= 0) { showToast('금액을 입력하세요', true); return; }
  if (fbMode === 'withdraw' && why.length < 2) { showToast('출금 사유를 입력하세요', true); return; }
  fetch('https://cookie_admin/' + (fbMode === 'deposit' ? 'factionDeposit' : 'factionWithdraw'), {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ amount: amt, reason: why }),
  }).catch(() => {});
  closeBudgetDialog();
}

function factionBadgeInner(f) {
  const fb = escapeHtml((f.name || '?').slice(0, 1));
  const src = f.imageUrl ? f.imageUrl : (f.imageFile ? ('img/' + f.imageFile) : null);
  if (!src) return fb;
  return '<img src="' + escapeHtml(src) + '" alt="" data-fb="' + fb +
    '" onerror="this.parentNode.textContent=this.dataset.fb">';
}

function renderFactionPane(f) {
  const el = document.getElementById('paneFaction');
  if (!el) return;
  if (!f) { el.innerHTML = '<div class="ck-skin-empty">소속된 팩션이 없습니다</div>'; return; }
  factionData = f;

  const canBudget = (f.isLeader || f.isOfficer) && f.budget != null;
  const role = f.isLeader ? '리더' : (f.isOfficer ? '간부' : '일반');

  let nav = '';
  CAD_NAV.forEach((n) => {
    if (n.sec) { nav += '<p class="ck-cad-sec">' + escapeHtml(n.sec) + '</p>'; return; }
    if (n.officer && !canBudget) return;
    if (n.soon) {
      nav += '<button class="ck-cad-navbtn soon" disabled>' + escapeHtml(n.label) +
        '<span class="ck-cad-soon">준비 중</span></button>';
      return;
    }
    nav += '<button class="ck-cad-navbtn" data-view="' + n.key + '">' + escapeHtml(n.label) + '</button>';
  });

  el.innerHTML =
    '<div class="ck-cad">' +
      '<aside class="ck-cad-nav" id="cadNav">' +
        '<div class="ck-cad-brand">' +
          '<p class="ck-cad-brand-n">' + escapeHtml(f.name) + '</p>' +
        '</div>' + nav +
      '</aside>' +
      '<main class="ck-cad-main" id="cadMain"></main>' +
    '</div>';

  document.querySelectorAll('#cadNav .ck-cad-navbtn[data-view]').forEach((b) => {
    b.addEventListener('click', () => { factionView = b.dataset.view; renderCadView(); });
  });

  const valid = CAD_NAV.some((n) => n.key === factionView && !n.soon && (!n.officer || canBudget));
  if (!valid) factionView = 'dash';
  renderCadView();
}

let fcView = 'overview';

function openMembersDialog(f) {
  const list = document.getElementById('fmemList');
  if (!list) return;
  const mem = f.members || [];
  document.getElementById('fmemTitle').textContent = f.name;
  document.getElementById('fmemSub').textContent = '팩션원 ' + mem.length + '명';
  list.innerHTML = mem.length
    ? mem.map((m2) =>
        '<div class="ck-toss-mrow">' +
          '<span>' + escapeHtml(m2.nickname || m2.citizenid) +
            (m2.department ? '<span class="ck-toss-mdep">' + escapeHtml(m2.department) + '</span>' : '') +
          '</span>' +
          '<b>' + escapeHtml(m2.rank_name || ('G' + m2.grade)) + '</b>' +
        '</div>').join('')
    : '<div class="ck-skin-empty">팩션원이 없습니다</div>';
  document.getElementById('fmemModal').classList.remove('hidden');
}

function closeMembersDialog() {
  document.getElementById('fmemModal').classList.add('hidden');
}

let baMode = 'add';
let baFactionId = 0;

function openBudgetAdjust(mode, factionId, factionName) {
  baMode = (mode === 'take') ? 'take' : 'add';
  baFactionId = factionId;
  const add = (baMode === 'add');
  document.getElementById('baTitle').textContent = add ? '예산 추가' : '예산 회수';
  document.getElementById('baSub').textContent =
    (factionName || '') + (add ? ' 예산에 금액을 추가합니다' : ' 예산에서 금액을 회수합니다');
  const ok = document.getElementById('baOk');
  ok.textContent = add ? '추가' : '회수';
  ok.classList.toggle('danger', !add);
  document.getElementById('baAmt').value = '';
  document.getElementById('baWhy').value = '';
  document.getElementById('baModal').classList.remove('hidden');
  document.getElementById('baAmt').focus();
}

function closeBudgetAdjust() {
  document.getElementById('baModal').classList.add('hidden');
}

function submitBudgetAdjust() {
  const amt = parseInt(document.getElementById('baAmt').value, 10) || 0;
  const why = document.getElementById('baWhy').value.trim();
  if (amt <= 0) { showToast('금액을 입력하세요', true); return; }
  if (why.length < 2) { showToast('사유를 입력하세요', true); return; }
  fcPost('factionBudgetAdjust', {
    factionId: baFactionId, amount: amt, reason: why, mode: baMode,
  });
  closeBudgetAdjust();
}

function openFactionConsole() {
  const c = document.getElementById('facConsole');
  if (!c) return;
  c.classList.remove('hidden');
  fetch('https://cookie_admin/requestFactionList', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
  }).catch(() => {});
}

function closeFactionConsole() {
  const c = document.getElementById('facConsole');
  if (c) c.classList.add('hidden');
}

function fcTypeLabel(k) {
  const t = (factionTypesData || []).find((x) => x.key === k);
  return t ? t.label : k;
}

function fcPost(path, body) {
  return fetch('https://cookie_admin/' + path, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  }).catch(() => {});
}

function fcMetric(label, value, tone) {
  return '<div class="ck-fc-metric"><p class="ck-fc-metric-l">' + escapeHtml(label) + '</p>' +
    '<p class="ck-fc-metric-v ' + (tone || '') + '">' + value + '</p></div>';
}

function fcPlayerOptions() {
  return (currentPlayers || []).map((p) =>
    '<option value="' + p.serverId + '">[' + p.serverId + '] ' +
    escapeHtml(p.name || p.nickname || '-') + '</option>').join('');
}

function fcRenderNav() {
  const nav = document.getElementById('fcNav');
  if (!nav) return;
  let h =
    '<div class="ck-fc-brand">' +
      '<p class="ck-fc-brand-n">서버 팩션 관리</p>' +
    '</div>' +
    '<p class="ck-fc-sec">개요</p>' +
    '<button class="ck-fc-navbtn' + (fcView === 'overview' ? ' active' : '') + '" data-fv="overview">대시보드</button>' +
    '<p class="ck-fc-sec">관리</p>' +
    '<button class="ck-fc-navbtn' + (fcView === 'create' ? ' active' : '') + '" data-fv="create">새 팩션 만들기</button>' +
    '<p class="ck-fc-sec">팩션 ' + factionAdminData.length + '</p>';

  factionAdminData.forEach((f) => {
    h += '<button class="ck-fc-navbtn' + (fcView === f.id ? ' active' : '') + '" data-fv="' + f.id + '">' +
      escapeHtml(f.name) + '<span class="ck-fc-navtag">' + escapeHtml(fcTypeLabel(f.faction_type)) + '</span></button>';
  });
  nav.innerHTML = h;

  nav.querySelectorAll('.ck-fc-navbtn').forEach((b) => b.addEventListener('click', () => {
    const v = b.dataset.fv;
    fcView = (v === 'overview' || v === 'create') ? v : parseInt(v, 10);
    renderFacMain();
  }));
}

function buildLineupCard(f) {
  const shopByModel = {};
  (f.shop || []).forEach((s) => { shopByModel[s.model] = s; });

  const lineup = (vehicleCatalog || []).filter((v) => v.job === f.name);

  let rows;
  if (!lineup.length) {
    rows = '<div class="ck-skin-empty">차량 라인업이 없습니다</div>';
  } else {
    rows = lineup.map((v) => {
      const s = shopByModel[v.model];
      const nm = '<span class="ck-fc-lname">' + escapeHtml(v.name || v.model) +
        ' <span class="ck-fc-hint">' + escapeHtml(v.model) + '</span></span>';
      const right = s
        ? '<b>' + fmtWon(s.price) + '</b>' +
          '<button class="ck-fc-xbtn ck-fc-shopdel" data-sid="' + s.id + '">삭제</button>'
        : '<input type="number" class="ck-fc-pinput" data-model="' + escapeHtml(v.model) + '" min="0" placeholder="가격">' +
          '<button class="ck-fc-abtn ck-fc-shopadd" data-model="' + escapeHtml(v.model) +
            '" data-name="' + escapeHtml(v.name || v.model) + '">등록</button>';
      return '<div class="ck-fc-shoprow' + (s ? ' on' : '') + '">' + nm + right + '</div>';
    }).join('');
  }

  return '<div class="ck-fc-card">' +
      '<p class="ck-fc-card-h">소속 차량 등록 및 가격 책정</p>' +
      '<div class="ck-fc-body-p">' +
        '<input type="text" id="fsSearch" class="ck-fc-lsearch" placeholder="차량 검색" autocomplete="off">' +
        '<div class="ck-fc-lineup" id="fsLineup">' + rows + '</div>' +
      '</div>' +
    '</div>';
}

const EMOJI_PRESET = ['👮', '🚔', '🛡️', '⚖️', '🚒', '🚑', '🏥', '🔧', '🚕', '🚚',
                      '💼', '🎤', '🍀', '💀', '🔫', '🃏', '🐺', '👑', '🍪', '⭐'];

let armAdmData = null;
let armAdmTab = 'weapon';

function armAdmCatalog() {
  const c = (armAdmData && armAdmData.catalog) || {};
  return c[armAdmTab] || [];
}

function armAdmGradeOpts(sel) {
  const ranks = (armAdmData && armAdmData.ranks) || [];
  if (!ranks.length) return '<option value="0">전원</option>';
  return ranks.map((r) =>
    '<option value="' + r.grade + '"' + (r.grade === sel ? ' selected' : '') + '>' +
    escapeHtml(r.rank_name) + '</option>').join('');
}

function renderArmoryAdmin() {
  const box = document.getElementById('faArmory');
  if (!box) return;

  const tabs = ARM_TABS.map((t) =>
    '<button class="ck-fc-seg' + (armAdmTab === t.key ? ' active' : '') + '" data-atab="' + t.key + '">' +
    t.label + '</button>').join('');

  const bindTabs = () => box.querySelectorAll('[data-atab]').forEach((b) =>
    b.addEventListener('click', () => { armAdmTab = b.dataset.atab; renderArmoryAdmin(); }));

  if (!armAdmData) {
    box.innerHTML =
      '<div class="ck-fc-segs">' + tabs + '</div>' +
      '<div class="ck-skin-empty">무장고 목록을 불러오는 중입니다</div>';
    bindTabs();
    return;
  }

  const byItem = {};
  (armAdmData.rows || []).forEach((r) => { byItem[r.item] = r; });

  const list = armAdmCatalog();
  const rows = list.length ? list.map((it) => {
    const on = byItem[it.item];
    const nm = '<span class="ck-fc-lname">' + escapeHtml(it.label) +
      '<span class="ck-arm-group">' + escapeHtml(it.group || '') + '</span></span>';

    const right = on
      ? '<button class="ck-fc-abtn ck-arm-tog' + (on.active ? '' : ' off') + '" data-aid="' + on.id + '">' +
          (on.active ? '활성' : '비활성') + '</button>' +
        '<button class="ck-fc-xbtn ck-arm-del" data-aid="' + on.id + '">해제</button>'
      : '<button class="ck-fc-abtn ck-arm-add" data-item="' + escapeHtml(it.item) +
          '" data-label="' + escapeHtml(it.label) + '"' +
          (it.ammo ? ' data-ammo="' + escapeHtml(it.ammo) + '"' : '') + '>등록</button>';

    return '<div class="ck-fc-shoprow' + (on ? ' on' : '') + '">' + nm + right + '</div>';
  }).join('') : '<div class="ck-skin-empty">항목이 없습니다</div>';

  box.innerHTML =
    '<div class="ck-fc-segs" id="faArmTabs">' + tabs + '</div>' +
    '<input type="text" id="faArmSearch" class="ck-fc-lsearch" placeholder="품목 검색" autocomplete="off">' +
    '<div class="ck-fc-lineup" id="faArmList">' + rows + '</div>';

  bindTabs();

  box.querySelectorAll('.ck-arm-add').forEach((b) => b.addEventListener('click', () => {
    fcPost('armorySave', {
      factionId: armAdmData.factionId,
      kind: armAdmTab,
      item: b.dataset.item,
      label: b.dataset.label,
      ammoItem: b.dataset.ammo || null,
      price: 0,
      minGrade: 0,
      active: true,
    });
  }));

  box.querySelectorAll('.ck-arm-del').forEach((b) => b.addEventListener('click', () =>
    fcPost('armoryDelete', { id: parseInt(b.dataset.aid, 10), factionId: armAdmData.factionId })));

  const resave = (id, patch) => {
    const row = (armAdmData.rows || []).find((r) => r.id === id);
    if (!row) return;
    fcPost('armorySave', Object.assign({
      factionId: armAdmData.factionId,
      kind: row.kind, item: row.item, label: row.label, ammoItem: row.ammo_item,
      price: row.price, minGrade: row.min_grade, active: !!row.active,
    }, patch));
  };

  box.querySelectorAll('.ck-arm-tog').forEach((b) => b.addEventListener('click', () => {
    const id = parseInt(b.dataset.aid, 10);
    const row = (armAdmData.rows || []).find((r) => r.id === id);
    if (!row) return;
    resave(id, { active: !row.active });
  }));

  const s = document.getElementById('faArmSearch');
  if (s) s.addEventListener('input', () => {
    const q = s.value.trim().toLowerCase();
    box.querySelectorAll('#faArmList .ck-fc-shoprow').forEach((r) => {
      r.style.display = (!q || r.textContent.toLowerCase().indexOf(q) !== -1) ? '' : 'none';
    });
  });
}

function fcRankOptions(f, selected){
  return (f.ranks||[]).slice().sort((a,b)=>Number(b.grade)-Number(a.grade)).map((r)=>
    '<option value="'+Number(r.grade)+'"'+(Number(r.grade)===Number(selected)?' selected':'')+'>'+escapeHtml(r.rank_name||('G'+r.grade))+'</option>'
  ).join('');
}

function fcRankAdminSection(f){
  const gov=!!f.is_gov;
  const rows=(f.ranks||[]).slice().sort((a,b)=>Number(b.grade)-Number(a.grade)).map((r)=>
    '<div class="ck-fa-rankrow" data-old-grade="'+Number(r.grade)+'">'+
      '<label><span>G</span><input class="ck-fa-rgrade" type="number" min="0" max="50" value="'+Number(r.grade)+'"></label>'+
      '<input class="ck-fa-rname" type="text" maxlength="40" value="'+escapeHtml(r.rank_name||'')+'" placeholder="계급명">'+
      (gov?'<label class="ck-fa-salary"><input class="ck-fa-rsalary" type="number" min="0" max="1000000000" value="'+Number(r.salary||0)+'"><span>원</span></label>':'<span class="ck-fa-no-salary">급여 없음</span>')+
      '<label class="ck-fa-check"><input class="ck-fa-rofficer" type="checkbox" '+((r.is_officer===1||r.is_officer===true)?'checked':'')+'><span>간부</span></label>'+
      '<label class="ck-fa-check"><input class="ck-fa-rleader" type="checkbox" '+((r.is_leader===1||r.is_leader===true)?'checked':'')+'><span>리더</span></label>'+
      '<button class="ck-fc-btn ck-fa-rsave" type="button">저장</button>'+
      '<button class="ck-fc-btn danger ck-fa-rdel" type="button">삭제</button>'+
    '</div>'
  ).join('');
  const salaryHint=gov
    ? '<small>정부 팩션은 계급별 급여가 Qbox 직업 급여에 실시간 반영됩니다.</small>'
    : '<small>사설·범죄 등 비정부 팩션은 급여가 지급되지 않습니다.</small>';
  return '<div class="ck-fc-card ck-fa-wide">'+
    '<p class="ck-fc-card-h">계급 관리 '+(gov?'<span class="ck-fa-govchip">정부 급여 적용</span>':'')+'</p>'+
    '<div class="ck-fc-body-p">'+salaryHint+
      '<div class="ck-fa-rankhead"><span>등급</span><span>계급명</span><span>'+(gov?'급여':'급여')+'</span><span>권한</span><span>관리</span></div>'+
      '<div class="ck-fa-ranklist">'+(rows||'<div class="ck-skin-empty">등록된 계급이 없습니다</div>')+'</div>'+
      '<div class="ck-fa-ranknew">'+
        '<label><span>G</span><input id="faNewRankGrade" type="number" min="0" max="50" placeholder="0"></label>'+
        '<input id="faNewRankName" type="text" maxlength="40" placeholder="새 계급명">'+
        (gov?'<label class="ck-fa-salary"><input id="faNewRankSalary" type="number" min="0" max="1000000000" value="0"><span>원</span></label>':'<span class="ck-fa-no-salary">급여 없음</span>')+
        '<label class="ck-fa-check"><input id="faNewRankOfficer" type="checkbox"><span>간부</span></label>'+
        '<label class="ck-fa-check"><input id="faNewRankLeader" type="checkbox"><span>리더</span></label>'+
        '<button id="faNewRankAdd" class="ck-fc-btn primary" type="button">계급 추가</button>'+
      '</div>'+
    '</div></div>';
}

function fcMemberAdminSection(f){
  const rows=(f.members||[]).map((m)=>{
    const online=!!m.online;
    const duty=!!m.duty;
    return '<div class="ck-fa-memberrow" data-cid="'+escapeHtml(m.citizenid||'')+'">'+
      '<div class="ck-fa-memberwho"><b>'+escapeHtml(m.nickname||m.citizenid||'-')+'</b><small>'+escapeHtml(m.gobun?('['+m.gobun+'] '):'')+escapeHtml(m.citizenid||'')+'</small></div>'+
      '<select class="ck-fc-select ck-fa-mgrade">'+fcRankOptions(f,m.grade)+'</select>'+
      '<span class="ck-fa-mstate '+(online?'online':'')+'">'+(online?'접속 중':'오프라인')+'</span>'+
      (f.is_gov?'<span class="ck-fa-duty '+(duty?'on':'off')+'">'+(duty?'출근':'퇴근')+'</span>':'<span class="ck-fa-duty neutral">상시</span>')+
      '<div class="ck-fa-mactions">'+
        '<button class="ck-fc-btn ck-fa-msave" type="button">계급 저장</button>'+
        (f.is_gov&&duty?'<button class="ck-fc-btn warn ck-fa-moff" type="button">강제 퇴근</button>':'')+
        '<button class="ck-fc-btn danger ck-fa-mremove" type="button">해임</button>'+
      '</div>'+
    '</div>';
  }).join('');
  return '<div class="ck-fc-card ck-fa-wide">'+
    '<p class="ck-fc-card-h">팩션원 관리</p>'+
    '<div class="ck-fc-body-p">'+
      '<div class="ck-fa-memberreason"><input id="faMemberReason" type="text" maxlength="300" placeholder="해임 사유 (필수)"></div>'+
      '<div class="ck-fa-memberlist">'+(rows||'<div class="ck-skin-empty">팩션원이 없습니다</div>')+'</div>'+
    '</div></div>';
}

function fcWarningAdminSection(f){
  const warns=f.warnings||[];
  const active=Number(f.warning_count||0);
  const rows=warns.map((w)=>
    '<div class="ck-fa-warnrow '+((w.active===1||w.active===true)?'active':'revoked')+'">'+
      '<div><b>'+escapeHtml(w.reason||'-')+'</b><small>'+escapeHtml(w.admin_name||'관리자')+' · '+escapeHtml(w.created_at||'')+'</small></div>'+
      ((w.active===1||w.active===true)?'<button class="ck-fc-btn ck-fa-wrevoke" data-wid="'+Number(w.id)+'" type="button">경고 회수</button>':'<span>회수됨</span>')+
    '</div>'
  ).join('');
  return '<div class="ck-fc-card ck-fa-wide">'+
    '<p class="ck-fc-card-h">팩션 경고 <span class="ck-fa-warncount">활성 '+active+'회</span></p>'+
    '<div class="ck-fc-body-p">'+
      '<div class="ck-fa-warnadd"><input id="faWarnReason" type="text" maxlength="300" placeholder="팩션 경고 사유"><button id="faWarnAdd" class="ck-fc-btn warn" type="button">경고 부여</button></div>'+
      '<div class="ck-fa-warnlist">'+(rows||'<div class="ck-skin-empty">경고 기록이 없습니다</div>')+'</div>'+
    '</div></div>';
}

function bindFactionAdminV2(main,f){
  main.querySelectorAll('.ck-fa-rsave').forEach((b)=>b.addEventListener('click',()=>{
    const row=b.closest('.ck-fa-rankrow'); if(!row)return;
    fcPost('factionRankSaveAdmin',{factionId:f.id,oldGrade:Number(row.dataset.oldGrade),grade:Number(row.querySelector('.ck-fa-rgrade')?.value),name:row.querySelector('.ck-fa-rname')?.value.trim()||'',salary:f.is_gov?Number(row.querySelector('.ck-fa-rsalary')?.value||0):0,isOfficer:!!row.querySelector('.ck-fa-rofficer')?.checked,isLeader:!!row.querySelector('.ck-fa-rleader')?.checked});
  }));
  main.querySelectorAll('.ck-fa-rdel').forEach((b)=>b.addEventListener('click',()=>{
    const row=b.closest('.ck-fa-rankrow'); if(!row)return;
    fcPost('factionRankDeleteAdmin',{factionId:f.id,grade:Number(row.dataset.oldGrade)});
  }));
  document.getElementById('faNewRankAdd')?.addEventListener('click',()=>{
    fcPost('factionRankSaveAdmin',{factionId:f.id,grade:Number(document.getElementById('faNewRankGrade')?.value),name:document.getElementById('faNewRankName')?.value.trim()||'',salary:f.is_gov?Number(document.getElementById('faNewRankSalary')?.value||0):0,isOfficer:!!document.getElementById('faNewRankOfficer')?.checked,isLeader:!!document.getElementById('faNewRankLeader')?.checked});
  });
  main.querySelectorAll('.ck-fa-msave').forEach((b)=>b.addEventListener('click',()=>{
    const row=b.closest('.ck-fa-memberrow'); if(!row)return;
    fcPost('factionMemberRankAdmin',{factionId:f.id,citizenid:row.dataset.cid,grade:Number(row.querySelector('.ck-fa-mgrade')?.value)});
  }));
  main.querySelectorAll('.ck-fa-moff').forEach((b)=>b.addEventListener('click',()=>{
    const row=b.closest('.ck-fa-memberrow'); if(!row)return;
    fcPost('factionForceOffDutyAdmin',{factionId:f.id,citizenid:row.dataset.cid});
  }));
  main.querySelectorAll('.ck-fa-mremove').forEach((b)=>b.addEventListener('click',()=>{
    const row=b.closest('.ck-fa-memberrow'); if(!row)return;
    const member=(f.members||[]).find((m)=>String(m.citizenid||'')===String(row.dataset.cid||''));
    if(!member){showToast('팩션원을 찾을 수 없습니다',true);return;}
    openFactionDismissConfirm(f,member);
  }));
  document.getElementById('faWarnAdd')?.addEventListener('click',()=>{
    const reason=document.getElementById('faWarnReason')?.value.trim()||'';
    if(reason.length<2){showToast('경고 사유를 입력하세요',true);return;}
    fcPost('factionWarningAddAdmin',{factionId:f.id,reason:reason});
  });
  main.querySelectorAll('.ck-fa-wrevoke').forEach((b)=>b.addEventListener('click',()=>fcPost('factionWarningRevokeAdmin',{factionId:f.id,warningId:Number(b.dataset.wid)})));
}


function openFactionDismissConfirm(f, member) {
  document.getElementById('ckFactionDismissOverlay')?.remove();
  const overlay = document.createElement('div');
  overlay.id = 'ckFactionDismissOverlay';
  overlay.className = 'ck-fa-dismiss-overlay';
  overlay.innerHTML =
    '<div class="ck-fa-dismiss-modal">' +
      '<div class="ck-fa-dismiss-icon">!</div>' +
      '<h3>팩션 해임 경고</h3>' +
      '<p><b>' + escapeHtml(member.nickname || member.citizenid || '-') + '</b> 님을 <b>' + escapeHtml(f.name || '팩션') + '</b>에서 해임합니다.</p>' +
      '<p class="ck-fa-dismiss-warn">리더·간부 여부와 관계없이 소속, 팩션 직업, 리더 권한이 즉시 제거됩니다.</p>' +
      '<label>해임 사유<input id="ckFactionDismissReason" type="text" maxlength="300" placeholder="해임 사유를 입력하세요"></label>' +
      '<div class="ck-fa-dismiss-actions"><button id="ckFactionDismissCancel" class="ck-fc-btn">취소</button><button id="ckFactionDismissConfirm" class="ck-fc-btn danger">해임 확정</button></div>' +
    '</div>';
  document.body.appendChild(overlay);
  const input = document.getElementById('ckFactionDismissReason');
  setTimeout(() => input?.focus(), 0);
  document.getElementById('ckFactionDismissCancel').onclick = () => overlay.remove();
  document.getElementById('ckFactionDismissConfirm').onclick = () => {
    const reason = (input?.value || '').trim();
    if (reason.length < 2) { showToast('해임 사유를 2글자 이상 입력하세요', true); return; }
    fcPost('factionMemberRemoveAdmin', { factionId: f.id, citizenid: member.citizenid, reason: reason });
    overlay.remove();
  };
}


// F3 > 팩션 관리 > 팩션 NPC. Catalog pricing is shared with intranet.
let ciNpcFaction = null, ciNpcRows=[];
function ciNpcScenarioOptions(selected) {
  const value = String(selected || 'WORLD_HUMAN_STAND_MOBILE');
  const list = [
    ['WORLD_HUMAN_STAND_MOBILE', '휴대폰 보며 대기'],
    ['WORLD_HUMAN_CLIPBOARD', '서류 확인'],
    ['WORLD_HUMAN_GUARD_STAND', '경비 자세'],
    ['WORLD_HUMAN_STAND_IMPATIENT', '일반 대기'],
    ['WORLD_HUMAN_AA_COFFEE', '커피 마시기'],
    ['NONE', '행동 없음'],
  ];
  return list.map(([v,l]) => '<option value="'+v+'" '+(v===value?'selected':'')+'>'+l+'</option>').join('');
}

function ciRenderNpc() {
  const box=document.getElementById('ciFactionNpc');
  if (!box || Number(ciNpcFaction)!==Number(fcView)) return;

  const rows=ciNpcRows.map(n=>{
    const id=Number(n.id);
    return '<div class="ck-fnpc-admin-card" data-ci-npc-card="'+id+'">'+
      '<div class="ck-fnpc-admin-top"><div><b>#'+id+' · '+escapeHtml(n.label||'판매 NPC')+'</b><small>'+Number(n.x).toFixed(1)+', '+Number(n.y).toFixed(1)+', '+Number(n.z).toFixed(1)+' · '+Number(n.heading||0).toFixed(0)+'°</small></div><span class="ck-fnpc-live">설치됨</span></div>'+
      '<div class="ck-fnpc-edit-grid">'+
        '<label>NPC 이름<input data-ci-npc-label="'+id+'" maxlength="60" value="'+escapeHtml(n.label||'팩션 판매 담당자')+'"></label>'+
        '<label>NPC 모델<input data-ci-npc-model="'+id+'" maxlength="60" value="'+escapeHtml(n.model||'a_m_y_business_01')+'"></label>'+
        '<label>대기 행동<select data-ci-npc-scenario="'+id+'">'+ciNpcScenarioOptions(n.scenario)+'</select></label>'+
      '</div>'+
      '<div class="ck-fnpc-admin-actions">'+
        '<button class="ck-fc-btn primary" data-ci-npc-save="'+id+'">설정 저장</button>'+
        '<button class="ck-fc-abtn" data-ci-npc-reposition="'+id+'">내 위치·방향으로 이동</button>'+
        '<button class="ck-fc-xbtn" data-ci-npc-del="'+id+'">삭제</button>'+
      '</div>'+
    '</div>';
  }).join('');

  box.innerHTML=
    '<p class="ck-fc-sec">팩션 상점 NPC는 해당 팩션 소속자만 이용합니다. 가까이 가면 전용 HUD가 표시되며, E키로 상품 상점을 엽니다.</p>'+ 
    '<div class="ck-fnpc-list">'+(rows||'<div class="ck-fnpc-empty">설치된 팩션 NPC가 없습니다.</div>')+'</div>'+ 
    '<div class="ck-fnpc-create">'+
      '<div class="ck-fnpc-create-title">새 상점 NPC 설치</div>'+
      '<div class="ck-fnpc-edit-grid">'+
        '<label>NPC 이름<input id="ciNpcLabel" maxlength="60" placeholder="예: 장비 판매 담당자"></label>'+ 
        '<label>NPC 모델<input id="ciNpcModel" maxlength="60" value="a_m_y_business_01"></label>'+ 
        '<label>대기 행동<select id="ciNpcScenario">'+ciNpcScenarioOptions('WORLD_HUMAN_STAND_MOBILE')+'</select></label>'+ 
      '</div><button class="ck-fc-btn primary" id="ciNpcCreate">현재 내 위치·방향에 NPC 설치</button>'+
    '</div>';

  box.querySelector('#ciNpcCreate').addEventListener('click',()=>{
    const label=box.querySelector('#ciNpcLabel').value.trim()||'팩션 판매 담당자';
    const model=box.querySelector('#ciNpcModel').value.trim();
    const scenario=box.querySelector('#ciNpcScenario').value;
    if (!/^[a-zA-Z0-9_]{3,60}$/.test(model))return showToast('NPC 모델명을 확인하세요',true);
    fcPost('ciFactionNpcPlace',{factionId:ciNpcFaction,label,model,scenario});
  });

  box.querySelectorAll('[data-ci-npc-save]').forEach(b=>b.addEventListener('click',()=>{
    const id=Number(b.dataset.ciNpcSave);
    const label=box.querySelector('[data-ci-npc-label="'+id+'"]').value.trim();
    const model=box.querySelector('[data-ci-npc-model="'+id+'"]').value.trim();
    const scenario=box.querySelector('[data-ci-npc-scenario="'+id+'"]').value;
    if (!label)return showToast('NPC 이름을 입력하세요',true);
    if (!/^[a-zA-Z0-9_]{3,60}$/.test(model))return showToast('NPC 모델명을 확인하세요',true);
    fcPost('ciFactionNpcUpdate',{factionId:ciNpcFaction,id,label,model,scenario});
    showToast('NPC 설정을 저장했습니다');
  }));

  box.querySelectorAll('[data-ci-npc-reposition]').forEach(b=>b.addEventListener('click',()=>{
    if(confirm('해당 NPC를 현재 내 위치와 바라보는 방향으로 옮길까요?'))fcPost('ciFactionNpcPlace',{factionId:ciNpcFaction,id:Number(b.dataset.ciNpcReposition)});
  }));
  box.querySelectorAll('[data-ci-npc-del]').forEach(b=>b.addEventListener('click',()=>{
    if(confirm('NPC를 삭제할까요?'))fcPost('ciFactionNpcDelete',{factionId:ciNpcFaction,id:Number(b.dataset.ciNpcDel)});
  }));
}
// F3 > 팩션 관리 > 선택된 팩션 > 인트라넷 관리
let ciCatalogFactionId = null;
let ciCatalogData = [];
function ciRequestCatalog(fid) {
  return fcPost('ciCatalogAdminList', { factionId: fid });
}
function ciCatalogRender() {
  const box = document.getElementById('ciCatalogAdmin');
  if (!box || ciCatalogFactionId !== fcView) return;
  const rows = ciCatalogData.map((r) => '<div class="ck-fc-shoprow">' +
    '<span class="ck-fc-lname">' + escapeHtml(r.label || '') + '<small> (' + escapeHtml(r.item_code || '') + ')</small></span>' +
    '<input class="ck-fc-pinput" aria-label="가격" type="number" min="0" max="2000000000" value="' + Number(r.price || 0) + '" data-ci-price="' + Number(r.id) + '">' +
    '<label style="display:flex;gap:4px;align-items:center"><input type="checkbox" data-ci-active="' + Number(r.id) + '" ' + (r.active ? 'checked' : '') + '>공개</label>' +
    '<button class="ck-fc-abtn" data-ci-save="' + Number(r.id) + '">수정</button>' +
    '<button class="ck-fc-xbtn" data-ci-delete="' + Number(r.id) + '">삭제</button></div>').join('');
  box.innerHTML = '<p class="ck-fc-sec">이 팩션의 F5 인트라넷에 표시할 판매 안내 품목을 설정합니다.</p>' +
    '<div class="ck-fc-lineup">' + (rows || '<p>등록된 품목이 없습니다.</p>') + '</div>' +
    '<div class="ck-fc-fields">' +
    '<label>품목 코드<input id="ciNewCode" placeholder="water" maxlength="80"></label>' +
    '<label>표시 이름<input id="ciNewLabel" placeholder="생수" maxlength="100"></label>' +
    '<label>판매 가격 (원)<input id="ciNewPrice" type="number" min="0" max="2000000000" value="1000"></label>' +
    '<label>설명<input id="ciNewDesc" placeholder="판매 품목 설명" maxlength="500"></label></div>' +
    '<button class="ck-fc-btn primary" id="ciAddItem">품목 등록</button>';
  box.querySelector('#ciAddItem').addEventListener('click', () => {
    const code = box.querySelector('#ciNewCode').value.trim();
    const label = box.querySelector('#ciNewLabel').value.trim();
    const price = Number(box.querySelector('#ciNewPrice').value);
    if (!/^[A-Za-z0-9_:-]{1,80}$/.test(code) || !label || !Number.isSafeInteger(price) || price < 0 || price > 2000000000) return showToast('품목 코드/이름/가격을 확인하세요',true);
    fcPost('ciCatalogAdminSave',{factionId:ciCatalogFactionId,itemCode:code,label,price,description:box.querySelector('#ciNewDesc').value.trim(),active:true});
  });
  box.querySelectorAll('[data-ci-save]').forEach(b => b.addEventListener('click', () => {
    const id=Number(b.dataset.ciSave),r=ciCatalogData.find(x=>Number(x.id)===id);
    if(!r)return;
    const price=Number(box.querySelector('[data-ci-price="'+id+'"]').value);
    if(!Number.isSafeInteger(price)||price<0||price>2000000000)return showToast('가격 범위를 확인하세요',true);
    fcPost('ciCatalogAdminSave',{factionId:ciCatalogFactionId,itemCode:r.item_code,label:r.label,description:r.description || '',price,active:box.querySelector('[data-ci-active="'+id+'"]').checked});
  }));
  box.querySelectorAll('[data-ci-delete]').forEach(b => b.addEventListener('click',()=>{
    if(confirm('이 품목을 삭제할까요?'))fcPost('ciCatalogAdminDelete',{factionId:ciCatalogFactionId,id:Number(b.dataset.ciDelete)});
  }));
}
function renderFacMain() {
  const main = document.getElementById('fcMain');
  if (!main) return;
  fcRenderNav();

  const title = document.getElementById('fcTitle');
  const sub = document.getElementById('fcSub');

  if (fcView === 'create') {
    title.textContent = '새 팩션 만들기';
    sub.textContent = '';
    const segs = (factionTypesData || []).map((t, i) =>
      '<button class="ck-fc-seg' + (i === 0 ? ' active' : '') + '" data-ftype="' + t.key + '">' +
      escapeHtml(t.label) + '</button>').join('');

    main.innerHTML =
      '<div class="ck-fc-card">' +
        '<p class="ck-fc-card-h">팩션 타입</p>' +
        '<div class="ck-fc-body-p">' +
          '<div class="ck-fc-segs" id="faTypes">' + segs + '</div>' +
          '<div class="ck-fc-fields">' +
            '<label>조직 이름<input type="text" id="faName" placeholder="쿠키 경찰국" maxlength="60" autocomplete="off"></label>' +
            '<label>조직 색상<input type="text" id="faColor" placeholder="#2F6FED" maxlength="10" autocomplete="off"></label>' +
            '<label>조직 성향<input type="text" id="faDisp" placeholder="정부 / 범죄" maxlength="40" autocomplete="off"></label>' +
            '<label>조직 업무<input type="text" id="faDuty" placeholder="로스산토스 남부 치안" maxlength="120" autocomplete="off"></label>' +
          '</div>' +
          '<button id="faCreate" class="ck-fc-btn primary">팩션 생성</button>' +
        '</div>' +
      '</div>';

    let faType = (factionTypesData[0] && factionTypesData[0].key) || 'police';
    main.querySelectorAll('#faTypes .ck-fc-seg').forEach((b) => b.addEventListener('click', () => {
      faType = b.dataset.ftype;
      main.querySelectorAll('#faTypes .ck-fc-seg').forEach((x) =>
        x.classList.toggle('active', x.dataset.ftype === faType));
    }));
    document.getElementById('faCreate').addEventListener('click', () => {
      const name = document.getElementById('faName').value.trim();
      if (name.length < 2) { showToast('조직 이름을 입력하세요', true); return; }

      fcPost('factionCreate', {
        type: faType, name: name,
        color: document.getElementById('faColor').value.trim(),
        disposition: document.getElementById('faDisp').value.trim(),
        duty: document.getElementById('faDuty').value.trim(),
      });
    });
    return;
  }

  if (typeof fcView === 'number') {
    const f = factionAdminData.find((x) => x.id === fcView);
    if (!f) { fcView = 'overview'; renderFacMain(); return; }

    title.textContent = f.name;
    sub.textContent = '';

    main.innerHTML =
      '<div class="ck-fc-metrics">' +
        '<div class="ck-fc-metric">' +
          '<p class="ck-fc-metric-l">예산</p>' +
          '<p class="ck-fc-metric-v gold">' + fmtWon(f.budget) + '</p>' +
          '<div class="ck-fc-badj">' +
            '<button id="baAddBtn" class="ck-fc-badd">추가</button>' +
            '<button id="baTakeBtn" class="ck-fc-btake">회수</button>' +
          '</div>' +
        '</div>' +
        '<button class="ck-fc-metric ck-fc-mclick" id="feMembersBtn">' +
          '<p class="ck-fc-metric-l">팩션원</p>' +
          '<p class="ck-fc-metric-v">' + (f.member_count || 0) + '명</p>' +
        '</button>' +
        '<div class="ck-fc-metric">' +
          '<p class="ck-fc-metric-l">리더</p>' +
          '<p class="ck-fc-metric-v ck-fc-leadername">' +
            escapeHtml(f.leader_nickname || (f.leader_citizenid ? f.leader_citizenid : '미지정')) + '</p>' +
        '</div>' +
      '</div>' +
      fcRankAdminSection(f) +
      '<div class="ck-fc-grid">' +
        '<div class="ck-fc-card">' +
          '<p class="ck-fc-card-h">기본 정보</p>' +
          '<div class="ck-fc-body-p">' +
            '<div class="ck-fc-fields">' +
              '<label>조직 이름<input type="text" id="feName" value="' + escapeHtml(f.name) + '" maxlength="60"></label>' +
              '<label>조직 색상<input type="text" id="feColor" value="' + escapeHtml(f.color || '#2F6FED') + '" maxlength="7" placeholder="#000000"></label>' +
              '<label>조직 성향<input type="text" id="feDisp" value="' + escapeHtml(f.disposition || '') + '" maxlength="40" placeholder="정부 / 범죄"></label>' +
              '<label>조직 업무<input type="text" id="feDuty" value="' + escapeHtml(f.duty || '') + '" maxlength="120" placeholder="로스산토스 남부 치안"></label>' +
              '<label>네임태그 이모지' +
                '<input type="text" id="feEmoji" value="' + escapeHtml(f.emoji || '') + '" maxlength="64" placeholder="👮 / 외부 이모지 붙여넣기">' +
              '</label>' +
              '<label>네임태그 소속 표기' +
                '<input type="text" id="feTagName" value="' + escapeHtml(f.tag_name || '') + '" maxlength="20" placeholder="경찰국">' +
              '</label>' +
            '</div>' +
            '<div class="ck-fc-emopick" id="feEmoPick">' +
              EMOJI_PRESET.map((e) => '<button class="ck-fc-emo" data-emo="' + e + '">' + e + '</button>').join('') +
            '</div>' +
            '<button id="feSave" class="ck-fc-btn primary">저장</button>' +
          '</div>' +
        '</div>' +
        '<div class="ck-fc-card">' +
          '<p class="ck-fc-card-h">인사</p>' +
          '<div class="ck-fc-body-p">' +
            '<select id="feTarget" class="ck-fc-select">' + fcPlayerOptions() + '</select>' +
            '<div class="ck-fc-btns">' +
              '<button id="feLeader" class="ck-fc-btn primary">리더 임명</button>' +
              '<button id="feMember" class="ck-fc-btn">팩션원 추가</button>' +
              '<button id="feDismiss" class="ck-fc-btn danger">해임</button>' +
            '</div>' +
          '</div>' +
        '</div>' +
      '</div>' +
      fcMemberAdminSection(f) +
      fcWarningAdminSection(f) +
      '<div class="ck-fc-card">' +
        '<p class="ck-fc-card-h">무장고 품목 등록</p>' +
        '<div class="ck-fc-body-p" id="faArmory"></div>' +
      '</div>' +
      '<div class="ck-fc-card"><p class="ck-fc-card-h">인트라넷 관리 · 판매 품목 / 가격</p><div class="ck-fc-body-p" id="ciCatalogAdmin">목록 불러오는 중...</div></div>' +
      '<div class="ck-fc-card"><p class="ck-fc-card-h">팩션 NPC 관리</p><div class="ck-fc-body-p" id="ciFactionNpc">NPC 정보 불러오는 중...</div></div>' +
      '<div class="ck-fc-footer"><button id="feDel" class="ck-fc-delbtn">팩션 제거</button></div>';

    armAdmData = null;
    renderArmoryAdmin();
    fcPost('requestArmoryAdmin', { factionId: f.id });
    ciCatalogFactionId = f.id; ciCatalogData = []; ciRequestCatalog(f.id);
    ciNpcFaction = f.id; ciNpcRows=[]; fcPost('ciFactionNpcList',{factionId:f.id});

    const memBtn = document.getElementById('feMembersBtn');
    if (memBtn) memBtn.addEventListener('click', () => openMembersDialog(f));

    const addB = document.getElementById('baAddBtn');
    const takeB = document.getElementById('baTakeBtn');
    if (addB) addB.addEventListener('click', () => openBudgetAdjust('add', f.id, f.name));
    if (takeB) takeB.addEventListener('click', () => openBudgetAdjust('take', f.id, f.name));

    main.querySelectorAll('.ck-fc-emo').forEach((b) => b.addEventListener('click', () => {
      document.getElementById('feEmoji').value = b.dataset.emo;
    }));

    const tgt = () => parseInt(document.getElementById('feTarget').value, 10) || 0;
    document.getElementById('feSave').addEventListener('click', () => {
      const rgb = document.getElementById('feColor').value.trim().toUpperCase();
      if (!/^#[0-9A-F]{6}$/.test(rgb)) { showToast('조직 색상은 #000000 형식으로 입력하세요', true); return; }
      fcPost('factionUpdate', {
      id: f.id,
      name: document.getElementById('feName').value.trim(),
      color: rgb,
      disposition: document.getElementById('feDisp').value.trim(),
      duty: document.getElementById('feDuty').value.trim(),
      emoji: document.getElementById('feEmoji').value.trim(),
      tagName: document.getElementById('feTagName').value.trim(),
    });
    });

    main.querySelectorAll('.ck-fc-shopadd').forEach((b) => b.addEventListener('click', () => {
      const inp = main.querySelector('.ck-fc-pinput[data-model="' + b.dataset.model + '"]');
      const price = inp ? (parseInt(inp.value, 10) || 0) : 0;
      if (price <= 0) { showToast('가격을 입력하세요', true); return; }
      fcPost('factionShopSave', {
        factionId: f.id,
        model: b.dataset.model,
        label: b.dataset.name,
        price: price,
        minGrade: 0,
      });
    }));
    main.querySelectorAll('.ck-fc-shopdel').forEach((b) => b.addEventListener('click', () =>
      fcPost('factionShopDelete', { id: parseInt(b.dataset.sid, 10) })));

    const fsSearch = document.getElementById('fsSearch');
    if (fsSearch) {
      fsSearch.addEventListener('input', () => {
        const q = fsSearch.value.trim().toLowerCase();
        main.querySelectorAll('#fsLineup .ck-fc-shoprow').forEach((r) => {
          r.style.display = (!q || r.textContent.toLowerCase().indexOf(q) !== -1) ? '' : 'none';
        });
      });
    }
    document.getElementById('feLeader').addEventListener('click', () =>
      fcPost('factionSetLeader', { id: f.id, targetServerId: tgt() }));
    document.getElementById('feMember').addEventListener('click', () =>
      fcPost('factionAddMember', { id: f.id, targetServerId: tgt() }));
    document.getElementById('feDismiss').addEventListener('click', () => {
      const sid = tgt();
      const member = (f.members || []).find((m) => Number(m.server_id || 0) === sid);
      if (!member) { showToast('선택한 접속자는 이 팩션 소속이 아닙니다', true); return; }
      openFactionDismissConfirm(f, member);
    });
    document.getElementById('feDel').addEventListener('click', () =>
      fcPost('factionDelete', { id: f.id }));
    bindFactionAdminV2(main, f);
    return;
  }

  title.textContent = '팩션 관리';
  sub.textContent = '';

  const totalBudget = factionAdminData.reduce((a, x) => a + Number(x.budget || 0), 0);
  const totalMembers = factionAdminData.reduce((a, x) => a + Number(x.member_count || 0), 0);

  const cards = factionAdminData.length ? factionAdminData.map((f) =>
    '<button class="ck-fc-fcard" data-fv="' + f.id + '">' +
      '<div class="ck-fc-fcard-h"><span>' + escapeHtml(f.name) + '</span>' +
        '<span class="ck-fc-tag">' + escapeHtml(fcTypeLabel(f.faction_type)) + '</span></div>' +
      '<div class="ck-fc-fcard-b">' +
        '<span>예산 <b>' + fmtWon(f.budget) + '</b></span>' +
        '<span>팩션원 <b>' + (f.member_count || 0) + '명</b></span>' +
        '<span>직업 <b>' + escapeHtml(f.job_name) + '</b></span>' +
      '</div>' +
    '</button>').join('') : '<div class="ck-skin-empty">생성된 팩션이 없습니다 — 좌측 [새 팩션 만들기]</div>';

  main.innerHTML =
    '<div class="ck-fc-metrics">' +
      fcMetric('팩션', factionAdminData.length + '개') +
      fcMetric('총 예산', fmtWon(totalBudget), 'gold') +
      fcMetric('총 팩션원', totalMembers + '명') +
    '</div>' +
    '<div class="ck-fc-cards">' + cards + '</div>';

  main.querySelectorAll('.ck-fc-fcard').forEach((b) => b.addEventListener('click', () => {
    fcView = parseInt(b.dataset.fv, 10);
    renderFacMain();
  }));
}

function renderFactionAdmin(list, types) {
  factionAdminData = list || [];
  if (types && types.length) factionTypesData = types;

  factionsData = factionAdminData;
  refreshGarageShop();
  renderGarageStat();
  if (vehSpawnMode === 'lspd') renderVehList();

  if (typeof fcView === 'number' && !factionAdminData.some((f) => f.id === fcView)) fcView = 'overview';
  renderFacMain();
}

function renderShell(d) {
  shellTabs = d.tabs || [];
  isAdminUser = !!d.isAdmin;
  myMugshotData = d.myMugshot || null;

  // 서버가 F3를 열 때 보내는 모든 시민직 레벨 데이터를 반드시 보관한다.
  // V2에서 이 대입이 빠져 모달이 항상 빈 배열([])을 읽던 문제 수정.
  jobLevelsData = Array.isArray(d.jobLevels) ? d.jobLevels : [];

  skinData = d.skins || { rp: [], admin: [], private: [] };
  personalStorageData = d.personalStorage || { vehicle: [], cosmetic: [], chair: [], skin: [], summary: {} };
  factionsData = d.factions || [];
  refreshGarageShop();
  renderRootTabs();

  if (isAdminUser && d.me) {
    renderPanel(d);
    renderAdminDash(d);
  }

  renderFactionPane(d.faction);
  renderUserPane(d.user);
  renderJobPane(d.job);

  const onDuty = !!(d.me && d.me.state === 'duty');
  const want = (isAdminUser && onDuty) ? 'admin' : 'user';
  const has = (k) => shellTabs.some((t) => t.key === k);
  setRootTab(has(want) ? want : (shellTabs[0] ? shellTabs[0].key : 'user'));

  showRolePick();
}

function renderPanel(d) {
  document.getElementById('meName').textContent = d.me.name;
  document.getElementById('meLevelName').textContent = LEVEL_NAME[d.me.level] || '-';
  document.getElementById('meLevel').textContent = 'LV' + d.me.level;
  const total = d.me.totalMinute || 0;
  const duty = d.me.dutyMinute || 0;
  const rp = Math.max(0, total - duty);
  document.getElementById('rpTime').textContent = formatTime(rp);
  document.getElementById('dutyTime').textContent = formatTime(duty);

  const mug = document.getElementById('meMug');
  if (d.myMugshot) { mug.src = d.myMugshot; } else { mug.removeAttribute('src'); }

  currentFeatures = d.features || [];
  currentPlayers = d.players || [];
  skinData = d.skins || { rp: [], admin: [], private: [] };
  personalStorageData = d.personalStorage || { vehicle: [], cosmetic: [], chair: [], skin: [], summary: {} };
  weaponCatalog = d.weapons || [];

  vehicleCatalog = d.vehicleCatalog || [];
  vehicleBrandOrder = d.vehicleBrandOrder || [];
  vehicleMajorOrder = d.vehicleMajorOrder || [];
  vehiclePerms = d.vehiclePerms || { spawn: false, exhibit: false };
  currentState = d.me.state || currentState;
  setupVehicleTabs();

  const pwBtn = document.getElementById('pwBtn');
  if (pwBtn) {
    if ((d.me.level || 0) >= 5 && !d.me.hasPw) pwBtn.classList.remove('hidden');
    else pwBtn.classList.add('hidden');
  }

  const pwResetBtn = document.getElementById('pwResetBtn');
  if (pwResetBtn) {
    if (d.me.isDev) pwResetBtn.classList.remove('hidden');
    else pwResetBtn.classList.add('hidden');
  }

  adminTeamsData = d.adminTeams || [];

  myLevel = d.me.level || 0;
  myEffectiveLevel = d.me.effectiveLevel || 0;
  myHasPw = !!d.me.hasPw;

  const grantBtn = document.getElementById('grantBtn');
  if (grantBtn) grantBtn.classList.add('hidden');

  myAdminName = (d.me && d.me.name) || '';

  const posSection = document.getElementById('posSection');
  if (posSection) {

    posSection.classList.add('hidden');
  }

  const rtabZones = document.getElementById('rtabZones');
  if (rtabZones) {
    if (myEffectiveLevel >= 5) rtabZones.classList.remove('hidden');
    else rtabZones.classList.add('hidden');
  }
  const rtabBeacons = document.getElementById('rtabBeacons');
  if (rtabBeacons) rtabBeacons.classList.toggle('hidden', myEffectiveLevel < 5);

  factionTypesData = d.factionTypes || [];
  canFactionManage = !!(d.factionPerms && d.factionPerms.manage);
  const rtabFac = document.getElementById('rtabFactions');
  if (rtabFac) rtabFac.classList.toggle('hidden', !canFactionManage);

  const rtabNpc = document.getElementById('rtabNpcs');
  if (rtabNpc) rtabNpc.classList.toggle('hidden', !(d.npcPerms && d.npcPerms.edit));

  const rtabSystems = document.getElementById('rtabSystems');
  if (rtabSystems) rtabSystems.classList.toggle('hidden', !(d.systemPerms && d.systemPerms.manage));

  const rtabLog = document.getElementById('rtabLogs');
  if (rtabLog) rtabLog.classList.toggle('hidden', !(d.logPerms && d.logPerms.view));

  const nb = document.getElementById('noticeBtn');
  if (nb) nb.classList.toggle('hidden', myEffectiveLevel < CHATMOD_MIN_LEVEL);

  const rb = document.getElementById('rebootBtn');
  if (rb) {
    rb.classList.toggle('hidden', myEffectiveLevel < 5);
    if (rebootExecuting) {
      rb.disabled = true;
      rb.textContent = '리붓 실행 중...';
    } else if (rebootRemain > 0) {
      rb.disabled = true;
      rb.textContent = '리붓까지 ' + rebootRemain + '초';
    } else {
      rb.disabled = false;
      rb.textContent = '서버 리붓 (60초)';
    }
  }

  const rtabNews = document.getElementById('rtabNews');
  if (rtabNews) rtabNews.classList.toggle('hidden', myEffectiveLevel < CHATMOD_MIN_LEVEL);

  setRightPane('dash');
  closeZoneDelModal();
  closeZoneNewModal();

  const posResult = document.getElementById('posResult');
  if (posResult) posResult.classList.add('hidden');
  setPosSectionOpen(false);

  if (myLevel >= 5 && !myHasPw) {
    showToast('비밀번호 설정 후 LV5 권한이 발효됩니다', false, 'neutral');
  }

  document.getElementById('pCount').textContent = currentPlayers.length;

  const list = document.getElementById('playerList');
  list.innerHTML = '';
  currentPlayers.forEach((p) => {
    const row = document.createElement('div');
    row.className = 'ck-player';

    row.innerHTML =
      '<span class="ck-player-id">[' + p.serverId + ']</span>' +
      '<span class="ck-player-name">' + escapeHtml(p.name) + '</span>' +
      (p.onboarded ? '' : '<span class="ck-player-tag">미온보딩</span>');
    row.addEventListener('click', () => openTargetModal(p));
    list.appendChild(row);
  });

  applyState(d.me.state);
}

function formatTime(min) {
  if (!min || min < 60) return (min || 0) + '분';
  const h = Math.floor(min / 60);
  const m = min % 60;
  return h + '시간 ' + (m > 0 ? m + '분' : '');
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}

function closePanel() {
  // V14.2.7: F3/상위 패널이 닫힐 때 body 직속 이벤트 허브가 남지 않게
  // 먼저 허브를 닫는다. standalone이면 Lua closeEventHub까지 호출되어
  // NUI focus도 함께 반환된다.
  try {
    if (document.getElementById('ckEventModal')) closeCookieEventHub();
  } catch (_) {}
  try { closeSystemWindows(); } catch (_) {}
  try { resetConsoles(); } catch (_) {}
  overlay.classList.remove('capture-hide');
  overlay.classList.remove('zone-only');
  overlay.classList.add('hidden');
  fetch('https://cookie_admin/close', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: '{}'
  }).catch(() => {});
}

function resetConsoles() {
  const hide = (id) => {
    const el = document.getElementById(id);
    if (el) el.classList.add('hidden');
  };

  hide('boxEdit');
  hide('npcConsole');
  hide('npcEditBar');
  overlay.classList.remove('npc-edit');

  document.querySelectorAll('[id$="Modal"]').forEach((el) => el.classList.add('hidden'));

  try { closeFactionConsole(); } catch (e) {}
  try { closeMyFaction(); } catch (e) {}

  npcView = 'list';
  npcDraft = null;
}

function showToast(message, isWarn, tone) {
  const wrap = document.getElementById('toastWrap');
  const toast = document.createElement('div');
  let cls = 'ck-toast';
  if (isWarn) cls += ' warn';
  else if (tone === 'toggle-on') cls += ' toggle-on';
  else if (tone === 'toggle-off') cls += ' toggle-off';
  else if (tone === 'neutral') cls += ' neutral';
  toast.className = cls;
  toast.innerHTML =
    '<div class="ck-toast-inner">' +
      '<img class="logo" src="logo.png" alt="">' +
      '<span class="msg">' + escapeHtml(message) + '</span>' +
      '<span class="dot"></span>' +
    '</div>' +
    '<div class="ck-toast-gauge"><div class="ck-toast-gauge-fill"></div></div>';
  wrap.appendChild(toast);
  const fill = toast.querySelector('.ck-toast-gauge-fill');
  if (fill) {
    requestAnimationFrame(() => { fill.style.transition = 'width 5000ms linear'; fill.style.width = '0%'; });
  }
  setTimeout(() => {
    toast.classList.add('out');
    setTimeout(() => toast.remove(), 300);
  }, 5000);
}

function showCookieAlert(message, isWarn) {
  const wrap = document.getElementById('cookieAlertWrap');
  if (!wrap) return;
  const card = document.createElement('div');
  card.className = 'ck-balert' + (isWarn ? ' warn' : '');
  card.innerHTML =
    '<div class="ck-balert-row">' +
      '<img class="logo" src="logo.png" alt="">' +
      '<div class="ck-balert-body">' +
        '<div class="ck-balert-title">쿠키 서버 알림</div>' +
        '<div class="msg">' + escapeHtml(message) + '</div>' +
      '</div>' +
    '</div>' +
    '<div class="ck-balert-gauge"><div class="ck-balert-gauge-fill"></div></div>';
  wrap.appendChild(card);
  const fill = card.querySelector('.ck-balert-gauge-fill');
  if (fill) {
    requestAnimationFrame(() => { fill.style.transition = 'width 5000ms linear'; fill.style.width = '0%'; });
  }
  setTimeout(() => { card.classList.add('out'); setTimeout(() => card.remove(), 300); }, 5000);
}

const dutyModal = document.getElementById('dutyModal');
const armory = document.getElementById('armory');

let armData = null;
let armTab = 'weapon';
const ARM_TABS = [
  { key: 'weapon', label: '무기' },
  { key: 'ammo', label: '총알' },
  { key: 'armor', label: '방탄복' },
];

function openZoneOverlay(which) {
  overlay.classList.remove('hidden');
  overlay.classList.add('zone-only');
  dutyModal.classList.toggle('hidden', which !== 'duty');
  armory.classList.toggle('hidden', which !== 'armory');
}

function closeZoneOverlay(tellClient) {
  overlay.classList.remove('zone-only');
  overlay.classList.add('hidden');
  dutyModal.classList.add('hidden');
  armory.classList.add('hidden');
  if (tellClient !== false) fcPost('closeZoneUi', {});
}

function renderDuty(d) {
  const on = !!d.onDuty;

  document.getElementById('dutyTitle').textContent = on ? '뱃지 반납' : '뱃지 착용';
  document.getElementById('dutySub').textContent = on
    ? '반납하면 근무가 종료됩니다'
    : '착용하면 근무가 시작됩니다';

  document.getElementById('dutyState').innerHTML =
    '<div class="ck-duty-row"><span>소속</span><b>' + escapeHtml(d.faction || '-') + '</b></div>' +
    '<div class="ck-duty-row"><span>계급</span><b>' + escapeHtml(d.rankName || '-') + '</b></div>' +
    '<div class="ck-duty-row"><span>상태</span>' +
      '<b class="' + (on ? 'on' : 'off') + '">' + (on ? '근무 중' : '퇴근') + '</b></div>' +
    '<div class="ck-duty-row"><span>근무 시간</span><b>' +
      (on ? ('착용 중 누적, ' + (d.idleMin || 30) + '분 무활동 시 중지') : '뱃지 착용 시 누적') +
    '</b></div>';

  const ok = document.getElementById('dutyOk');
  ok.textContent = on ? '뱃지 반납' : '뱃지 착용';
  ok.classList.toggle('danger', on);

  openZoneOverlay('duty');
}

function armImg(it) {
  if (it.kind === 'armor') {
    return '<div class="ck-arm-img noimg"></div>';
  }
  const src = 'nui://ox_inventory/web/images/' + String(it.img || it.item).toLowerCase() + '.png';
  return '<div class="ck-arm-img">' +
      '<img src="' + src + '" alt="" ' +
        'onerror="this.parentNode.classList.add(\'noimg\');this.remove();">' +
    '</div>';
}

function armCard(it) {
  const off = !armData.onDuty;
  const locked = !!it.locked || off;

  const qty = (it.kind === 'ammo')
    ? '<input type="number" class="ck-arm-qty" id="q_' + it.id + '" value="1" min="1" max="' +
        (armData.maxQty || 20) + '">'
    : '';

  let btn;
  if (off) {
    btn = '<button class="ck-arm-buy locked" disabled>근무 중에만 무장</button>';
  } else if (it.locked) {
    btn = '<button class="ck-arm-buy locked" disabled>' +
      escapeHtml(it.rankName || '상위 계급') + ' 이상</button>';
  } else {
    btn = '<button class="ck-arm-buy" data-buy="' + it.id + '">무장하기</button>';
  }

  const price = (armData.charge && it.price > 0) ? fmtWon(it.price) : '국가 지원';

  const nameLabel = (it.kind === 'ammo') ? '총알이름' : (it.kind === 'armor') ? '방탄복' : '무기이름';

  return '<div class="ck-arm-card' + (locked ? ' locked' : '') + '">' +
      armImg(it) +
      '<div class="ck-arm-cbody">' +
        '<p class="ck-arm-crow"><span>' + nameLabel + '</span>' +
          '<b>' + escapeHtml(it.label) + '</b></p>' +
        '<p class="ck-arm-crow"><span>가격</span>' +
          '<b class="gold">' + price + '</b></p>' +
        '<div class="ck-arm-cact">' + qty + btn + '</div>' +
      '</div>' +
    '</div>';
}

function renderArmory(d) {
  armData = d;

  document.getElementById('armTitle').textContent = (d.faction || '팩션') + ' 무장고';
  document.getElementById('armSub').textContent = d.onDuty
    ? (d.rankName || '-')
    : '근무를 시작해야 무장할 수 있습니다';

  const tabs = document.getElementById('armTabs');
  tabs.innerHTML = ARM_TABS.map((t) =>
    '<button class="ck-arm-tab' + (armTab === t.key ? ' active' : '') + '" data-tab="' + t.key + '">' +
      t.label + '</button>').join('');
  tabs.querySelectorAll('[data-tab]').forEach((b) => b.addEventListener('click', () => {
    armTab = b.dataset.tab;
    renderArmory(armData);
  }));

  const rows = (d.items || []).filter((it) => it.kind === armTab);
  const list = document.getElementById('armList');
  list.innerHTML = rows.length
    ? rows.map(armCard).join('')
    : '<div class="ck-skin-empty">등록된 품목이 없습니다</div>';

  list.querySelectorAll('[data-buy]').forEach((b) => b.addEventListener('click', () => {
    const id = parseInt(b.dataset.buy, 10);
    const qEl = document.getElementById('q_' + id);
    fcPost('armoryBuy', { id, qty: qEl ? parseInt(qEl.value, 10) || 1 : 1 });
  }));

  const inv = document.getElementById('armInv');
  inv.innerHTML = (d.inv || []).length
    ? (d.inv || []).map((i) =>
        '<div class="ck-arm-irow"><span>' + escapeHtml(i.label) + '</span>' +
          '<b>' + (i.count || 1) + '</b></div>').join('')
    : '<div class="ck-skin-empty">비어 있습니다</div>';

  openZoneOverlay('armory');
}

document.getElementById('dutyCancel').addEventListener('click', () => closeZoneOverlay());
document.getElementById('dutyOk').addEventListener('click', () => fcPost('dutyToggle', {}));
document.getElementById('armClose').addEventListener('click', () => closeZoneOverlay());

document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  if (overlay.classList.contains('zone-only')) closeZoneOverlay();
});

window.addEventListener('message', (e) => {
  const d = e.data;
  if (d.action === 'rebootCountdown') {
    applyRebootCountdown(d.seconds);
    return;
  }
  if (d.action === 'newsList') {
    newsData = d.rows || [];
    renderNewsList();
    return;
  }
  if (d.action === 'dutyOpen') {
    renderDuty(d);
    return;
  }
  if (d.action === 'armoryOpen') {
    renderArmory(d);
    return;
  }
  if (d.action === 'zoneUiClose') {
    closeZoneOverlay(false);
    return;
  }
  if (d.action === 'convenienceAdmin') {
    convenienceAdminRows = Array.isArray(d.rows) ? d.rows : [];
    renderConvenienceAdmin();
    return;
  }
  if (d.action === 'jobShopAdmin') {
    const payload = d.data || {};
    jobShopAdminRows = Array.isArray(payload.rows) ? payload.rows : [];
    jobShopAdminJobs = payload.jobs || {};
    renderJobShopAdmin();
    return;
  }

  if (d.action === 'npcAdmin') {
    npcData = d;
    renderNpcMain();
    return;
  }
  if (d.action === 'npcEditUi') {
    renderNpcEditUi(d);
    return;
  }

  if (d.action === 'npcHails') {
    npcHails = d;
    if (npcView === 'hail') renderNpcHails();
    return;
  }

  if (d.action === 'npcTruck') {
    npcTruck = d;
    if (npcView === 'truck') renderNpcTruck();
    return;
  }

  if (d.action === 'npcTaxiPay') { npcTaxiPay=d.data||{}; if(npcView==='hail') renderNpcHails(); return; }
  if (d.action === 'npcTruckPay') { npcTruckPay=d.data||{}; if(npcView==='truck') renderNpcTruck(); return; }
  if (d.action === 'npcMechanic') {
    npcMechanic = d.data || null;
    if (npcMechanic && npcMechanic.npcId) mechanicNpc = Number(npcMechanic.npcId);
    if (npcView === 'mechanic') renderNpcMechanic();
    return;
  }
  if (d.action === 'npcDelivery') { window.__npcDelivery=d.data||{}; if(npcView==='delivery') renderNpcDelivery(); return; }
  if (d.action === 'npcLabor') {
    npcLabor = d.data || null;
    if (npcLabor && npcLabor.npcId) laborNpc = Number(npcLabor.npcId);
    if (npcView === 'labor') renderNpcLabor();
    return;
  }

  if (d.action === 'fishingSystemData') {
    fishingSystemData = d.data || null;
    renderFishingSystem();
    return;
  }
  if (d.action === 'miningSystemData') {
    miningSystemData = d.data || null;
    miningSystemError = '';
    renderMiningSystem();
    const b=document.getElementById('miningSysSave'); if(b){b.disabled=false;b.textContent='저장';}
    return;
  }
  if (d.action === 'miningSystemError') {
    miningSystemData = null;
    miningSystemError = String(d.message || '광산 설정을 불러오지 못했습니다');
    renderMiningSystem();
    return;
  }

  if (d.action === 'npcFishingAdmin') {
    npcFishing = d.data || null;
    if (npcFishing && npcFishing.npcId) fishingNpc = Number(npcFishing.npcId);
    if (npcView === 'fishing') renderNpcFishing();
    return;
  }

  if (d.action === 'npcMiningAdmin') {
    npcMining = d.data || null;
    if (npcMining && npcMining.npcId) miningNpc = Number(npcMining.npcId);
    if (npcView === 'mining') renderNpcMining();
    return;
  }

  if (d.action === 'npcTags') {
    const box = document.getElementById('npcTags');
    if (!box) return;
    const list = d.tags || [];

    while (box.children.length < list.length) {
      const el = document.createElement('div');
      el.className = 'ck-npctag';
      box.appendChild(el);
    }
    for (let i = 0; i < box.children.length; i++) {
      const el = box.children[i];
      const t = list[i];
      if (!t) { el.classList.add('hidden'); continue; }
      if (el.textContent !== t.label) el.textContent = t.label;
      el.style.left = (t.x * 100) + '%';
      el.style.top = (t.y * 100) + '%';
      el.style.opacity = t.a;
      el.classList.remove('hidden');
    }
    return;
  }

  if (d.action === 'npcBadge') {
    const el = document.getElementById('npcBadge');
    if (!el) return;
    if (!d.show) { el.classList.add('hidden'); return; }
    el.querySelector('.ck-npcbadge-t').textContent = d.text || '대화하기';
    el.style.left = (d.x * 100) + '%';
    el.style.top = (d.y * 100) + '%';
    el.classList.remove('hidden');
    return;
  }
  if (d.action === 'npcPlaced') {

    if (npcDraft) {
      npcDraft.x = d.x; npcDraft.y = d.y; npcDraft.z = d.z; npcDraft.heading = d.heading;
      npcDraft.model = d.model;
      npcDraft.scenario = d.scenario || '';
      npcDraft.components = d.components || [];
    }
    document.getElementById('npcEditBar').classList.add('hidden');
    overlay.classList.remove('npc-edit');
    document.getElementById('npcConsole').classList.remove('hidden');
    renderNpcMain();
    return;
  }
  if (d.action === 'npcEditCancel') {
    document.getElementById('npcEditBar').classList.add('hidden');
    overlay.classList.remove('npc-edit');
    document.getElementById('npcConsole').classList.remove('hidden');
    renderNpcMain();
    return;
  }

  if (d.action === 'armoryCatalog') {

    armAdmData = {
      factionId: d.factionId,
      catalog: d.catalog || {},
      rows: (armAdmData && armAdmData.factionId === d.factionId && armAdmData.rows) || [],
      ranks: (armAdmData && armAdmData.factionId === d.factionId && armAdmData.ranks) || [],
    };
    renderArmoryAdmin();
    return;
  }
  if (d.action === 'armoryAdmin') {
    armAdmData = {
      factionId: d.factionId,
      catalog: (d.catalog && d.catalog.weapon) ? d.catalog : ((armAdmData && armAdmData.catalog) || {}),
      rows: d.rows || [],
      ranks: d.ranks || [],
    };
    renderArmoryAdmin();
    return;
  }

  if (d.action === 'grantItemCatalog') {
    grantItemCatalog = Array.isArray(d.items) ? d.items : [];
    renderGrantItemOptions();
    if (d.error) showToast(d.error, true);
    return;
  }
  if (d.action === 'mailboxData') {
    mailboxRows = Array.isArray(d.rows) ? d.rows : [];
    renderMailbox();
    return;
  }
  if (d.action === 'grantMailResult') {
    grantMailBusy = false;
    const send = document.getElementById('gmSend');
    if (send) { send.disabled = false; send.textContent = '우편 발송'; }
    if (d.ok) closeGrantMailModal();
    return;
  }

  if (d.action === 'open') {

    resetConsoles();

    renderShell(d);
    overlay.classList.remove('zone-only');
    overlay.classList.remove('hidden');
  } else if (d.action === 'close') {
    resetConsoles();
    overlay.classList.add('hidden');
  } else if (d.action === 'mugshot') {

    myMugshotData = d.myMugshot || null;

    const mugEl = document.getElementById('meMug');
    if (mugEl && myMugshotData) mugEl.src = myMugshotData;

    const uAvatar = document.querySelector('.ck-me-avatar');
    if (uAvatar) {
      uAvatar.innerHTML = myMugshotData ? '<img src="' + myMugshotData + '" alt="">' : '';
    }
  } else if (d.action === 'toast') {
    showToast(d.message, d.isWarn, d.tone);
  } else if (d.action === 'cookieAlert') {
    showCookieAlert(d.message, d.isWarn);
  } else if (d.action === 'stateChanged') {
    applyState(d.state);
  } else if (d.action === 'factionPane') {
    renderFactionPane(d.faction);
  } else if (d.action === 'ciFactionNpcData') {
    if(Number(d.factionId)===Number(ciNpcFaction)){ciNpcRows=d.rows||[];ciRenderNpc();}
  } else if (d.action === 'ciCatalogAdminData') {
    if (Number(d.factionId) === Number(ciCatalogFactionId)) { ciCatalogData = d.rows || []; ciCatalogRender(); }
  } else if (d.action === 'factionAdminList') {
    renderFactionAdmin(d.factions || [], d.types || []);
  } else if (d.action === 'hideForCapture') {

    overlay.classList.toggle('capture-hide', !!d.on);
  } else if (d.action === 'logs') {
    renderLogs(d.kind, d.rows || []);
  } else if (d.action === 'vehShot') {
    resizeAndSaveVehShot(d.model, d.data);
  } else if (d.action === 'grantList') {
    renderGrantList(d.players || []);
  } else if (d.action === 'toggleState') {
    setToggleVisual(TOGGLE_BTN[d.toggle], !!d.on);
  } else if (d.action === 'posResult') {
    setCenterUI(d.vec3, d.vec4);
    setSummaryUI(d.summary || '-');

    applyShapeUI(d.shape);
    setSliderUI('radius', d.radius);
    setSliderUI('length', d.length);
    setSliderUI('width', d.width);
    setSliderUI('heading', d.heading);
    setToggleVisual('posPreviewBtn', !!d.preview);
    document.getElementById('posResult').classList.remove('hidden');
    setPosSectionOpen(true);

        if (zoneWalkPolyUiHidden) {
      document.getElementById('zoneNewModal')?.classList.remove('hidden');
      zoneWalkPolyUiHidden = false;
    }
lastPosResult = { shape: d.shape, vec3: d.vec3, summary: d.summary };
    if (zoneNewOpen) renderZoneNewCoords();
  } else if (d.action === 'exhibitList') {
    renderExhibitList(d.list || [], d.limited || [], d.factions || []);
  } else if (d.action === 'lspdFleet') {
    renderLspdFleet(d.list || []);
  } else if (d.action === 'afkZoneConfigData') {
    afkZoneCoordData = d.data || {};
    renderAfkZoneCoords();
  } else if (d.action === 'zoneList') {
    zoneRows = d.zones || [];
    zoneFactions = d.factions || {};
    renderZones();
    renderBeacons();
    renderZoneFactionPick();
  } else if (d.action === 'zonePreviewState') {
    applyZonePreviewUI(!!d.on, d.label);
  } else if (d.action === 'posPreviewState') {
    setToggleVisual('posPreviewBtn', !!d.on);
  } else if (d.action === 'boxEditState') {

    if (d.shape) applyShapeUI(d.shape);
    setSliderUI('radius', d.radius);
    setSliderUI('length', d.length);
    setSliderUI('width', d.width);
    setSliderUI('heading', d.heading);
    setSummaryUI(d.summary);
    setCenterUI(d.vec3, d.vec4);
    if (d.session) setToggleVisual('posPreviewBtn', true);
    applyBoxEditUI(!!d.session, !!d.ui);

    if (d.vec3) lastPosResult = { shape: d.shape || (lastPosResult && lastPosResult.shape), vec3: d.vec3, summary: d.summary };

    if (zoneNewOpen) {
      document.getElementById('zoneNewModal').classList.toggle('hidden', !!d.session);
      if (!d.session) renderZoneNewCoords();
    }
  }
});

function setToggleVisual(id, on) {
  const el = document.getElementById(id);
  if (!el) return;
  el.classList.toggle('on', on);
  el.setAttribute('aria-pressed', on ? 'true' : 'false');
  const state = el.querySelector('.ck-tg-state');
  if (state) state.textContent = on ? 'ON' : 'OFF';
}

const TOGGLE_BTN = {
  noclip: 'noclipToggle',
  superjump: 'jumpToggle',
  stamina: 'staminaToggle',
  sprint: 'sprintToggle',
};
const TOGGLE_EP = {
  noclipToggle: 'toggleNoclip',
  jumpToggle: 'toggleSuperJump',
  staminaToggle: 'toggleStamina',
  sprintToggle: 'toggleSprint',
};

Object.keys(TOGGLE_EP).forEach((id) => {
  const el = document.getElementById(id);
  if (!el) return;
  el.addEventListener('click', () => {
    fetch('https://cookie_admin/' + TOGGLE_EP[id], { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' }).catch(() => {});
  });
});

function requestExtract(shape) {
  fetch('https://cookie_admin/extractPos', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ shape: shape }),
  }).catch(() => {});
}
document.getElementById('posBtnCircle').addEventListener('click', () => requestExtract('circle'));
document.getElementById('posBtnBox').addEventListener('click', () => requestExtract('box'));

function setPosSectionOpen(open) {
  document.getElementById('posBody').classList.toggle('hidden', !open);
  document.getElementById('posToggle').setAttribute('aria-expanded', open ? 'true' : 'false');
  document.querySelector('#posToggle .ck-pos-caret').textContent = open ? '▼' : '▶';
}
document.getElementById('posToggle').addEventListener('click', () => {
  const open = document.getElementById('posBody').classList.contains('hidden');
  setPosSectionOpen(open);
});

function applyShapeUI(shape) {
  const isBox = shape === 'box';
  const isPoly = shape === 'poly';
  document.getElementById('posBoxCtl').classList.toggle('hidden', !isBox);
  document.getElementById('posCircleCtl').classList.toggle('hidden', isBox || isPoly);
  document.getElementById('beditBoxCtl').classList.toggle('hidden', !isBox);
  document.getElementById('beditCircleCtl').classList.toggle('hidden', isBox || isPoly);
  document.getElementById('boxEditTitle').textContent = isPoly ? '이동형 다각형' : (isBox ? '네모 편집' : '원형 편집');
}

function setSummaryUI(text) {
  if (!text) return;
  document.getElementById('posSummary').textContent = text;
  document.getElementById('boxEditSum').textContent = text;
}

function setCenterUI(vec3, vec4) {
  if (vec3) {
    document.getElementById('posVec3').textContent = 'center = ' + vec3;
    document.getElementById('boxEditCenter').textContent = vec3;
  }
  if (vec4) document.getElementById('posVec4').textContent = vec4;
}

let draggingSlider = null;

function setSliderUI(key, value) {
  if (typeof value !== 'number') return;
  const rounded = Math.round(value * 10) / 10;
  document.querySelectorAll('.ck-pos-slider[data-key="' + key + '"]').forEach((i) => {
    if (i === draggingSlider) return;
    i.value = rounded;
  });
  document.querySelectorAll('.ck-pos-num[data-key="' + key + '"]').forEach((i) => {

    if (document.activeElement !== i) i.value = rounded;
  });
}

function applyShapeValueResponse(res) {
  if (!res) return;
  setSummaryUI(res.summary);
  setSliderUI('radius', res.radius);
  setSliderUI('length', res.length);
  setSliderUI('width', res.width);
  setSliderUI('heading', res.heading);
}

const reqSeq = {};

function sendShapeValue(key, v) {
  const seq = (reqSeq[key] = (reqSeq[key] || 0) + 1);
  fetch('https://cookie_admin/setPosShapeValue', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ key: key, value: v }),
  })
    .then((r) => r.json())
    .then((res) => {
      if (seq !== reqSeq[key]) return;
      applyShapeValueResponse(res);
    })
    .catch(() => {});
}

const lastSent = {};
document.querySelectorAll('.ck-pos-slider').forEach((input) => {
  const key = input.dataset.key;

  input.addEventListener('pointerdown', () => { draggingSlider = input; });

  input.addEventListener('input', (e) => {
    const v = Number(e.target.value);
    setSliderUI(key, v);
    if (lastSent[key] === v) return;
    lastSent[key] = v;
    sendShapeValue(key, v);
  });

  input.addEventListener('change', () => {
    draggingSlider = null;
    sendShapeValue(key, Number(input.value));
  });
});

window.addEventListener('pointerup', () => { draggingSlider = null; });
window.addEventListener('blur', () => { draggingSlider = null; });

document.querySelectorAll('.ck-pos-num').forEach((input) => {
  input.addEventListener('change', (e) => {
    const key = input.dataset.key;
    const v = Number(e.target.value);
    if (!isFinite(v)) return;
    lastSent[key] = v;
    sendShapeValue(key, v);
  });

  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') { e.preventDefault(); input.blur(); }
  });
});

document.querySelectorAll('.ck-nudge-btn').forEach((btn) => {
  btn.addEventListener('click', () => {
    const step = Number(document.getElementById('nudgeStep').value) || 0.5;
    const dx = Number(btn.dataset.dx) * step;
    const dy = Number(btn.dataset.dy) * step;
    fetch('https://cookie_admin/nudgePosCenter', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ dx: dx, dy: dy }),
    })
      .then((r) => r.json())
      .then((res) => {
        if (!res) return;
        setSummaryUI(res.summary);
        setCenterUI(res.vec3, res.vec4);
      })
      .catch(() => {});
  });
});

function postSimple(ep) {
  fetch('https://cookie_admin/' + ep, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' }).catch(() => {});
}
document.getElementById('boxEditBtn').addEventListener('click', () => postSimple('enterBoxEdit'));
document.getElementById('boxEditConfirm').addEventListener('click', () => postSimple('confirmBoxEdit'));
document.getElementById('boxEditCancel').addEventListener('click', () => postSimple('cancelBoxEdit'));

function applyBoxEditUI(session, ui) {
  overlay.classList.toggle('hidden', session);
  document.getElementById('boxEdit').classList.toggle('hidden', !(session && ui));
}

document.getElementById('posPreviewBtn').addEventListener('click', () => {
  fetch('https://cookie_admin/togglePosPreview', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' }).catch(() => {});
});

function copyText(text) {
  if (navigator.clipboard && navigator.clipboard.writeText) {
    return navigator.clipboard.writeText(text).then(() => true).catch(() => legacyCopy(text));
  }
  return Promise.resolve(legacyCopy(text));
}
function legacyCopy(text) {
  try {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    const ok = document.execCommand('copy');
    ta.remove();
    return ok;
  } catch (err) {
    return false;
  }
}
document.querySelectorAll('.ck-pos-copy').forEach((btn) => {
  btn.addEventListener('click', () => {
    const text = document.getElementById(btn.dataset.target).textContent;
    copyText(text).then((ok) => {
      if (ok) {
        btn.classList.add('copied');
        setTimeout(() => btn.classList.remove('copied'), 900);
      } else {
        showToast('클립보드 복사 실패 — 채팅에서 복사하세요', true);
      }
    });
  });
});

let zoneRows = [];
let zoneFilter = 'all';
let beaconFilter = 'all';
const BEACON_TYPES = new Set(['garage','wardrobe','convenience','jobshop','tuningshop','atm','duty','armory','charzone','kuji','newbie_verify','teleport',
  'afk_enter',
  'afk_leave',]);
let zoneNewMode = 'zone';
let zoneDelTarget = null;
let zoneFactions = {};

const ZONE_TYPE_LABEL = {

  safezone: '보호구역',
  afkzone: '잠수존 범위',
  afk_enter: '잠수존 입장',
  afk_leave: '잠수존 퇴장',
  charzone: '커마존',
  garage: '차고',
  wardrobe: '옷장',
  convenience: '편의점',
  jobshop: '직업상점',
  tuningshop: '튜닝샵',
  atm: 'ATM',
  duty: '근무존',
  armory: '무장존',
  kuji: '쿠지',
  newbie_verify: '뉴비 인증',
  teleport: '텔레포트',
  fishing: '낚시 포인트',
  mining: '광산',

  garage_lspd: '차고(구)', garage_lssd: '차고(구)',
  wardrobe_lspd: '옷장(구)', wardrobe_lssd: '옷장(구)',
  duty_lspd: '근무존(구)', armory_lspd: '무장존(구)',
};

const ZONE_NEEDS_FACTION = { duty: true, armory: true, garage: true, wardrobe: true, charzone: true };

const FISHING_REGION_LABEL = {
  freshwater: '내륙/민물', coast: '일반 연안', north: '북부 연안', west: '서부 연안',
  south: '남부 연안', east: '동부 연안', city: '도심 연안', offshore: '외해/심해',
};
function fishingRegionLabel(key) { return FISHING_REGION_LABEL[key] || '일반 연안'; }

function fmtNum(n) {
  if (typeof n !== 'number') return '-';
  return Number.isInteger(n) ? String(n) : n.toFixed(1);
}

function zoneMeta(z) {
  const c = 'center ' + fmtNum(z.cx) + ', ' + fmtNum(z.cy) + ', ' + fmtNum(z.cz);
  const base = (z.shape === 'sphere')
    ? ('sphere · r=' + fmtNum(z.radius) + 'm · ' + c)
    : (z.shape === 'poly')
      ? ('이동형 다각형 · ' + ((z.polyPoints || []).length) + '개 지점 · ' + c)
      : ('box · ' + fmtNum(z.length) + '×' + fmtNum(z.width) + 'm · ' + fmtNum(z.heading) + '° · ' + c);
  if (z.type === 'teleport') {
    return base + ' → ' + fmtNum(z.teleportX) + ', ' + fmtNum(z.teleportY) + ', ' + fmtNum(z.teleportZ) + ' · ' + fmtNum(z.teleportH) + '°';
  }
  return base;
}

const zoneGroupCollapsed = {};

function facOf(id) {
  if (!id) return null;
  return zoneFactions[String(id)] || zoneFactions[id] || null;
}

function zoneRowEl(z) {
  {
    const row = document.createElement('div');
    row.className = 'ck-zone t-' + z.type;

    const main = document.createElement('div');
    main.className = 'ck-zone-main';
    const name = document.createElement('div');
    name.className = 'ck-zone-name';
    name.textContent = z.label;

    main.appendChild(name);

    const tag = document.createElement('span');
    tag.className = 'ck-zone-tag';
    tag.textContent = (z.type === 'fishing')
      ? ('낚시 포인트 · ' + (z.fishingType === 'boat' ? '선상' : '일반') + ' · ' + fishingRegionLabel(z.fishingRegion))
      : (z.type === 'mining' ? '광산 · 범위 내 자유 채굴' : (ZONE_TYPE_LABEL[z.type] || z.type));

    if (ZONE_NEEDS_FACTION[z.type]) {
      const fac = facOf(z.factionId);
      const chip = document.createElement('button');

      const missing = !z.factionId;
      chip.className = 'ck-zone-fac' + (missing ? ' empty' : '');
      chip.textContent = fac ? fac.name : (missing ? '공용' : ('삭제된 소속 #' + z.factionId));
      chip.title = missing
        ? '공용 · 모든 유저가 이용할 수 있습니다'
        : '클릭해서 소속을 바꿉니다';
      chip.addEventListener('click', (e) => { e.stopPropagation(); openZoneFacModal(z); });
      main.appendChild(chip);
    }

    const acts = document.createElement('div');
    acts.className = 'ck-zone-acts';

    const prev = document.createElement('button');
    prev.className = 'ck-zone-act';
    prev.textContent = '미리보기';
    prev.addEventListener('click', () => {

      previewMetaPending = zoneMeta(z);
      fetch('https://cookie_admin/previewZone', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(z),
      }).catch(() => {});
    });
    acts.appendChild(prev);

    const edit = document.createElement('button');
    edit.className = 'ck-zone-act';
    edit.textContent = '편집';
    edit.addEventListener('click', () => {

      fetch('https://cookie_admin/editZone', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(z),
      }).catch(() => {});
    });
    acts.appendChild(edit);

    if (z.type === 'fishing') {
      const fs = document.createElement('button');
      fs.className = 'ck-zone-act';
      fs.textContent = '낚시설정';
      fs.addEventListener('click', () => openFishingPointSettings(z));
      acts.appendChild(fs);
    }

    if (z.type === 'mining') {
      const ms = document.createElement('button');
      ms.className = 'ck-zone-act';
      ms.textContent = '광산설정';
      ms.addEventListener('click', () => openMiningZoneSettings(z));
      acts.appendChild(ms);
    }

    if (z.type === 'teleport') {
      const target = document.createElement('button');
      target.className = 'ck-zone-act';
      target.textContent = '목적지';
      target.addEventListener('click', () => {
        const x = prompt('목적지 X 좌표', String(z.teleportX ?? ''));
        if (x === null) return;
        const y = prompt('목적지 Y 좌표', String(z.teleportY ?? ''));
        if (y === null) return;
        const zz = prompt('목적지 Z 좌표', String(z.teleportZ ?? ''));
        if (zz === null) return;
        const h = prompt('도착 방향 Heading', String(z.teleportH ?? 0));
        if (h === null) return;

        const nx = Number(x), ny = Number(y), nz = Number(zz), nh = Number(h);
        if (![nx, ny, nz, nh].every(Number.isFinite)) {
          showToast('목적지 좌표를 숫자로 입력하세요', true);
          return;
        }

        fetch('https://cookie_admin/updateTeleportTarget', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ ...z, teleportX: nx, teleportY: ny, teleportZ: nz, teleportH: nh }),
        }).catch(() => {});
      });
      acts.appendChild(target);
    }

    const del = document.createElement('button');
    del.className = 'ck-zone-act danger';
    del.textContent = '삭제';
    del.addEventListener('click', () => openZoneDelModal(z));
    acts.appendChild(del);

    row.appendChild(main);
    row.appendChild(tag);
    row.appendChild(acts);
    return row;
  }
}

function renderZones() {
  const list = document.getElementById('zoneList');
  list.innerHTML = '';

  const rows = zoneRows.filter((z) => !BEACON_TYPES.has(z.type)).filter((z) => zoneFilter === 'all' || z.type === zoneFilter);
  if (rows.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'ck-zone-empty';
    const cnt = zoneRows.filter((z) => !BEACON_TYPES.has(z.type)).length;
    empty.textContent = cnt === 0 ? '등록된 좌표가 없습니다' : '이 필터에 해당하는 좌표가 없습니다';
    list.appendChild(empty);
    return;
  }

  const groups = {};
  rows.forEach((z) => {
    const key = z.factionId ? String(z.factionId) : '';
    (groups[key] = groups[key] || []).push(z);
  });

  const keys = Object.keys(groups).filter((k) => k !== '').sort((a, b) => Number(a) - Number(b));
  if (groups['']) keys.push('');

  keys.forEach((key) => {
    const items = groups[key];
    const fac = key ? facOf(key) : null;
    const title = fac ? fac.name : (key ? ('소속 #' + key) : '공용');

    const head = document.createElement('button');
    head.className = 'ck-zgrp' + (zoneGroupCollapsed[key] ? ' collapsed' : '');
    head.innerHTML =
      '<span class="ck-zgrp-arrow">▾</span>' +
      '<span class="ck-zgrp-name">' + escapeHtml(title) + '</span>' +
      '<span class="ck-zgrp-count">' + items.length + '</span>';
    head.addEventListener('click', () => {
      zoneGroupCollapsed[key] = !zoneGroupCollapsed[key];
      renderZones();
    });
    list.appendChild(head);

    if (zoneGroupCollapsed[key]) return;

    const body = document.createElement('div');
    body.className = 'ck-zgrp-body';
    items.forEach((z) => body.appendChild(zoneRowEl(z)));
    list.appendChild(body);
  });
}

function renderBeacons() {
  const list = document.getElementById('beaconList');
  if (!list) return;
  list.innerHTML = '';
  const rows = zoneRows.filter((z) => BEACON_TYPES.has(z.type)).filter((z) => beaconFilter === 'all' || z.type === beaconFilter);
  if (!rows.length) { const e=document.createElement('div'); e.className='ck-zone-empty'; e.textContent='등록된 비콘이 없습니다'; list.appendChild(e); return; }
  const groups={}; rows.forEach(z=>{const k=z.factionId?String(z.factionId):'';(groups[k]=groups[k]||[]).push(z);});
  const keys=Object.keys(groups).filter(k=>k!=='').sort((a,b)=>Number(a)-Number(b)); if(groups['']) keys.push('');
  keys.forEach(key=>{ const items=groups[key], fac=key?facOf(key):null, title=fac?fac.name:(key?('소속 #'+key):'공용');
    const head=document.createElement('button'); head.className='ck-zgrp'+(zoneGroupCollapsed['b:'+key]?' collapsed':'');
    head.innerHTML='<span class="ck-zgrp-arrow">▾</span><span class="ck-zgrp-name">'+escapeHtml(title)+'</span><span class="ck-zgrp-count">'+items.length+'</span>';
    head.addEventListener('click',()=>{zoneGroupCollapsed['b:'+key]=!zoneGroupCollapsed['b:'+key];renderBeacons();}); list.appendChild(head);
    if(zoneGroupCollapsed['b:'+key]) return; const body=document.createElement('div'); body.className='ck-zgrp-body'; items.forEach(z=>body.appendChild(zoneRowEl(z))); list.appendChild(body);
  });
}


// ── 편의점 공용 상품 관리 ─────────────────────────────────
let convenienceAdminRows = [];

function convPost(path, body) {
  return fetch('https://cookie_admin/' + path, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body || {}),
  }).catch(() => {});
}

function renderConvenienceAdmin() {
  const list = document.getElementById('convFoodList');
  if (!list) return;

  if (!convenienceAdminRows.length) {
    list.innerHTML = '<div class="ck-zone-empty">등록된 편의점 상품이 없습니다. 위에서 아이템 코드와 가격을 입력해 추가하세요.</div>';
    return;
  }

  list.innerHTML = convenienceAdminRows.map((r) =>
    '<div class="ck-conv-row" data-convid="' + Number(r.id || 0) + '">' +
      '<div class="ck-conv-code" title="' + escapeHtml(r.item_name || '') + '">' + escapeHtml(r.item_name || '') + '</div>' +
      '<input class="ck-conv-input conv-label" type="text" maxlength="80" value="' + escapeHtml(r.label || '') + '">' +
      '<input class="ck-conv-input conv-price" type="number" min="0" step="1" value="' + Number(r.price || 0) + '">' +
      '<select class="ck-conv-select conv-active">' +
        '<option value="1"' + (Number(r.active) === 1 ? ' selected' : '') + '>판매중</option>' +
        '<option value="0"' + (Number(r.active) !== 1 ? ' selected' : '') + '>판매중지</option>' +
      '</select>' +
      '<button class="ck-conv-btn save conv-save">저장</button>' +
      '<button class="ck-conv-btn del conv-del">삭제</button>' +
    '</div>'
  ).join('');

  list.querySelectorAll('.conv-save').forEach((btn) => btn.addEventListener('click', () => {
    const row = btn.closest('.ck-conv-row');
    const id = Number(row && row.dataset.convid) || 0;
    const old = convenienceAdminRows.find((x) => Number(x.id) === id);
    if (!old) return;
    convPost('saveConvenienceFood', {
      id,
      itemName: old.item_name,
      label: row.querySelector('.conv-label').value.trim(),
      price: parseInt(row.querySelector('.conv-price').value, 10) || 0,
      active: row.querySelector('.conv-active').value === '1',
      sortOrder: Number(old.sort_order || 0),
    });
  }));

  list.querySelectorAll('.conv-del').forEach((btn) => btn.addEventListener('click', () => {
    const row = btn.closest('.ck-conv-row');
    const id = Number(row && row.dataset.convid) || 0;
    if (!id) return;
    if (!confirm('이 편의점 상품을 삭제할까요?')) return;
    convPost('deleteConvenienceFood', { id });
  }));
}

function requestConvenienceAdmin() {
  convPost('requestConvenienceAdmin', {});
}

const convAddBtn = document.getElementById('convAddBtn');
if (convAddBtn) convAddBtn.addEventListener('click', () => {
  const item = document.getElementById('convNewItem').value.trim().toLowerCase();
  const label = document.getElementById('convNewLabel').value.trim();
  const price = parseInt(document.getElementById('convNewPrice').value, 10);
  if (!item) { showToast('아이템 코드를 입력하세요', true); return; }
  if (!label) { showToast('표시 이름을 입력하세요', true); return; }
  if (!Number.isFinite(price) || price < 0) { showToast('가격을 입력하세요', true); return; }
  convPost('saveConvenienceFood', { itemName: item, label, price, active: true, sortOrder: 0 });
  document.getElementById('convNewItem').value = '';
  document.getElementById('convNewLabel').value = '';
  document.getElementById('convNewPrice').value = '';
});

const convRefreshBtn = document.getElementById('convRefreshBtn');
if (convRefreshBtn) convRefreshBtn.addEventListener('click', requestConvenienceAdmin);

// ── 시민직업 도구 상점 관리 ───────────────────────────────
let jobShopAdminRows = [];
let jobShopAdminJobs = {};

function jobShopPost(path, body) {
  return fetch('https://cookie_admin/' + path, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body || {}),
  }).catch(() => {});
}

function jobShopJobOptions(selected) {
  return Object.entries(jobShopAdminJobs || {}).map(([key, def]) =>
    '<option value="' + escapeHtml(key) + '"' + (key === selected ? ' selected' : '') + '>' +
      escapeHtml((def && def.label) || key) + '</option>'
  ).join('');
}

function renderJobShopAdmin() {
  const addJob = document.getElementById('jobShopNewJob');
  if (addJob) addJob.innerHTML = jobShopJobOptions(addJob.value || 'mechanic');

  const list = document.getElementById('jobShopItemList');
  if (!list) return;
  if (!jobShopAdminRows.length) {
    list.innerHTML = '<div class="ck-zone-empty">등록된 시민직업 도구가 없습니다. 위에서 직업과 아이템을 선택해 추가하세요.</div>';
    return;
  }

  list.innerHTML = jobShopAdminRows.map((r) =>
    '<div class="ck-conv-row" data-jobshopid="' + Number(r.id || 0) + '">' +
      '<select class="ck-conv-select jobshop-job">' + jobShopJobOptions(String(r.job_name || '')) + '</select>' +
      '<div class="ck-conv-code" title="' + escapeHtml(r.item_name || '') + '">' + escapeHtml(r.item_name || '') + '</div>' +
      '<input class="ck-conv-input jobshop-label" type="text" maxlength="80" value="' + escapeHtml(r.label || '') + '">' +
      '<input class="ck-conv-input jobshop-price" type="number" min="0" step="1" value="' + Number(r.price || 0) + '">' +
      '<select class="ck-conv-select jobshop-active">' +
        '<option value="1"' + (Number(r.active) === 1 ? ' selected' : '') + '>판매중</option>' +
        '<option value="0"' + (Number(r.active) !== 1 ? ' selected' : '') + '>판매중지</option>' +
      '</select>' +
      '<button class="ck-conv-btn save jobshop-save">저장</button>' +
      '<button class="ck-conv-btn del jobshop-del">삭제</button>' +
    '</div>'
  ).join('');

  list.querySelectorAll('.jobshop-save').forEach((btn) => btn.addEventListener('click', () => {
    const row = btn.closest('.ck-conv-row');
    const id = Number(row && row.dataset.jobshopid) || 0;
    const old = jobShopAdminRows.find((x) => Number(x.id) === id);
    if (!old) return;
    jobShopPost('saveJobShopItem', {
      id,
      jobName: row.querySelector('.jobshop-job').value,
      itemName: old.item_name,
      label: row.querySelector('.jobshop-label').value.trim(),
      price: parseInt(row.querySelector('.jobshop-price').value, 10) || 0,
      active: row.querySelector('.jobshop-active').value === '1',
      sortOrder: Number(old.sort_order || 0),
    });
  }));

  list.querySelectorAll('.jobshop-del').forEach((btn) => btn.addEventListener('click', () => {
    const row = btn.closest('.ck-conv-row');
    const id = Number(row && row.dataset.jobshopid) || 0;
    if (!id || !confirm('이 직업 도구 상품을 삭제할까요?')) return;
    jobShopPost('deleteJobShopItem', { id });
  }));
}

function requestJobShopAdmin() {
  jobShopPost('requestJobShopAdmin', {});
}

const jobShopAddBtn = document.getElementById('jobShopAddBtn');
if (jobShopAddBtn) jobShopAddBtn.addEventListener('click', () => {
  const jobName = document.getElementById('jobShopNewJob').value;
  const item = document.getElementById('jobShopNewItem').value.trim().toLowerCase();
  const label = document.getElementById('jobShopNewLabel').value.trim();
  const price = parseInt(document.getElementById('jobShopNewPrice').value, 10);
  if (!jobName) { showToast('시민직업을 선택하세요', true); return; }
  if (!item) { showToast('아이템 코드를 입력하세요', true); return; }
  if (!label) { showToast('표시 이름을 입력하세요', true); return; }
  if (!Number.isFinite(price) || price < 0) { showToast('가격을 입력하세요', true); return; }
  jobShopPost('saveJobShopItem', { jobName, itemName: item, label, price, active: true, sortOrder: 0 });
  document.getElementById('jobShopNewItem').value = '';
  document.getElementById('jobShopNewLabel').value = '';
  document.getElementById('jobShopNewPrice').value = '';
});

const jobShopRefreshBtn = document.getElementById('jobShopRefreshBtn');
if (jobShopRefreshBtn) jobShopRefreshBtn.addEventListener('click', requestJobShopAdmin);

let zoneFacTarget = null;

function openZoneFacModal(z) {
  zoneFacTarget = z;
  document.getElementById('zoneFacName').textContent = z.label;

  const wrap = document.getElementById('zoneFacPick');
  const cur = z.factionId ? String(z.factionId) : '';
  const ids = Object.keys(zoneFactions).sort((a, b) => Number(a) - Number(b));

  wrap.innerHTML =
    '<button class="ck-lv-seg' + (cur === '' ? ' active' : '') +
    '" data-fid="">공용</button>' +
    ids.map((id) =>
      '<button class="ck-lv-seg' + (cur === String(id) ? ' active' : '') +
      '" data-fid="' + escapeHtml(String(id)) + '">' + escapeHtml(zoneFactions[id].name) + '</button>'
    ).join('');

  wrap.querySelectorAll('.ck-lv-seg').forEach((b) => {
    b.addEventListener('click', () => {
      wrap.querySelectorAll('.ck-lv-seg').forEach((x) => x.classList.toggle('active', x === b));
    });
  });

  document.getElementById('zoneFacModal').classList.remove('hidden');
}

function closeZoneFacModal() {
  zoneFacTarget = null;
  document.getElementById('zoneFacModal').classList.add('hidden');
}

function openZoneDelModal(z) {
  zoneDelTarget = z;
  document.getElementById('zoneDelName').textContent = z.label;
  document.getElementById('zoneDelModal').classList.remove('hidden');
}
function closeZoneDelModal() {
  zoneDelTarget = null;
  document.getElementById('zoneDelModal').classList.add('hidden');
}
document.getElementById('zoneFacCancel').addEventListener('click', closeZoneFacModal);
document.getElementById('zoneFacSave').addEventListener('click', () => {
  if (!zoneFacTarget) return;
  const sel = document.querySelector('#zoneFacPick .ck-lv-seg.active');
  const fid = sel && sel.dataset.fid ? Number(sel.dataset.fid) : null;
  // fid=null 은 공용 비콘
  fetch('https://cookie_admin/setZoneFaction', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ id: zoneFacTarget.id, factionId: fid }),
  }).catch(() => {});
  closeZoneFacModal();
});

document.getElementById('zoneDelCancel').addEventListener('click', closeZoneDelModal);
document.getElementById('zoneDelConfirm').addEventListener('click', () => {
  if (!zoneDelTarget) return;
  fetch('https://cookie_admin/deleteZone', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id: zoneDelTarget.id }),
  }).catch(() => {});

  closeZoneDelModal();
});

document.querySelectorAll('#zoneFilters .ck-chip').forEach((chip) => {
  chip.addEventListener('click', () => {
    zoneFilter = chip.dataset.filter;
    document.querySelectorAll('#zoneFilters .ck-chip').forEach((c) => c.classList.toggle('active', c === chip));
    renderZones();
  });
});

document.querySelectorAll('#beaconFilters .ck-chip').forEach((chip) => {
  chip.addEventListener('click', () => {
    beaconFilter = chip.dataset.filter;
    document.querySelectorAll('#beaconFilters .ck-chip').forEach((c) => c.classList.toggle('active', c === chip));
    renderBeacons();
  });
});


function ensureFishingZoneUi() {
  const types = document.getElementById('zoneNewTypes');
  if (types && !types.querySelector('[data-type="fishing"]')) {
    const b = document.createElement('button');
    b.className = 'ck-lv-seg';
    b.dataset.type = 'fishing';
    b.textContent = '낚시 포인트';
    types.appendChild(b);
  }
  if (types && !types.querySelector('[data-type="mining"]')) {
    const b = document.createElement('button');
    b.className = 'ck-lv-seg';
    b.dataset.type = 'mining';
    b.textContent = '광산';
    types.appendChild(b);
  }

  const filters = document.getElementById('zoneFilters');
  if (filters && !filters.querySelector('[data-filter="fishing"]')) {
    const b = document.createElement('button');
    b.className = 'ck-chip';
    b.dataset.filter = 'fishing';
    b.textContent = '낚시 포인트';
    filters.appendChild(b);
  }

  if (!document.getElementById('zoneFishingRow')) {
    const label = document.getElementById('zoneNewLabel');
    const anchor = label ? (label.closest('label') || label.parentElement) : null;
    if (anchor && anchor.parentElement) {
      const row = document.createElement('div');
      row.id = 'zoneFishingRow';
      row.className = 'hidden';
      row.style.margin = '16px 0 6px';
      row.innerHTML =
        '<p style="margin:0 0 8px;color:#aaa;font-size:12px">낚시 유형</p>' +
        '<div id="zoneFishingTypes" class="ck-lv-segs">' +
          '<button class="ck-lv-seg active" data-ftype="normal">일반 낚시</button>' +
          '<button class="ck-lv-seg" data-ftype="boat">선상 낚시</button>' +
        '</div>';
      anchor.parentElement.insertBefore(row, anchor);
    }
  }
}

ensureFishingZoneUi();

let zoneNewFishingType = 'normal';
let zoneNewFishingRegion = 'coast';
let zoneNewType = 'safezone';
let zoneNewOpen = false;
let lastPosResult = null;

function renderZoneNewCoords() {
  const box = document.getElementById('zoneNewCoords');
  const save = document.getElementById('zoneNewSave');
  const edit = document.getElementById('zoneNewEdit');

  if (lastPosResult) {
    box.classList.remove('empty');
    box.textContent = lastPosResult.vec3 + ' · ' + lastPosResult.summary;
    save.disabled = false;
    edit.disabled = lastPosResult.shape === 'poly';
  } else {
    box.classList.add('empty');
    box.textContent = '원형 / 네모 / 이동형 범위를 지정하세요';
    save.disabled = true;
    edit.disabled = true;
  }
  const walkBtn = document.getElementById('zoneNewWalkPoly');
  if (walkBtn) walkBtn.classList.toggle('hidden', !['safezone','fishing','mining','afkzone'].includes(zoneNewType));
}

let zoneNewFaction = null;

function renderZoneFactionPick() {
  const wrap = document.getElementById('zoneNewFactions');
  if (!wrap) return;

  const ids = Object.keys(zoneFactions).sort((a, b) => Number(a) - Number(b));

  wrap.innerHTML =
    '<button class="ck-lv-seg' + (zoneNewFaction == null ? ' active' : '') + '" data-fid="">공용</button>' +
    ids.map((id) =>
      '<button class="ck-lv-seg' + (String(zoneNewFaction) === String(id) ? ' active' : '') +
      '" data-fid="' + escapeHtml(String(id)) + '">' + escapeHtml(zoneFactions[id].name) + '</button>'
    ).join('');

  wrap.querySelectorAll('.ck-lv-seg').forEach((b) => {
    b.addEventListener('click', () => {
      zoneNewFaction = b.dataset.fid ? Number(b.dataset.fid) : null;
      wrap.querySelectorAll('.ck-lv-seg').forEach((x) => x.classList.toggle('active', x === b));
    });
  });
}

function syncZoneFactionRow() {
  const row = document.getElementById('zoneFactionRow');
  if (row) row.classList.toggle('hidden', !ZONE_NEEDS_FACTION[zoneNewType]);
  const fish = document.getElementById('zoneFishingRow');
  if (fish) fish.classList.toggle('hidden', zoneNewType !== 'fishing');
  const tp = document.getElementById('teleportTargetRow');
  if (tp) tp.classList.toggle('hidden', zoneNewType !== 'teleport');
}

function openZoneNewModal(mode = 'zone') {
  zoneNewMode = mode === 'beacon' ? 'beacon' : 'zone';
  zoneNewOpen = true;
  lastPosResult = null;
  zoneNewType = zoneNewMode === 'beacon' ? 'garage' : 'safezone';
  zoneNewFishingType = 'normal';
  zoneNewFishingRegion = 'coast';
  zoneNewFaction = null;
  document.querySelectorAll('#zoneNewTypes .ck-lv-seg').forEach((b) =>
    b.classList.toggle('active', b.dataset.type === zoneNewType));
  document.querySelectorAll('#zoneNewTypes .ck-lv-seg').forEach((b) => {
    const isBeacon = BEACON_TYPES.has(b.dataset.type);
    b.classList.toggle('hidden', zoneNewMode === 'beacon' ? !isBeacon : isBeacon);
  });
  const zTitle=document.querySelector('#zoneNewModal .ck-mm-title'); if(zTitle) zTitle.textContent=zoneNewMode==='beacon'?'새 비콘 만들기':'새 좌표 만들기';
  const colorRow = document.getElementById('beaconColorRow'); if (colorRow) colorRow.classList.toggle('hidden', zoneNewMode !== 'beacon');
  const colorInput = document.getElementById('beaconColor'); if (colorInput) colorInput.value = '#4285F4';
  const colorText = document.getElementById('beaconColorText'); if (colorText) colorText.textContent = '#4285F4';
  ['teleportTargetX','teleportTargetY','teleportTargetZ','teleportTargetH'].forEach((id) => {
    const el = document.getElementById(id); if (el) el.value = id === 'teleportTargetH' ? '0' : '';
  });
  document.getElementById('zoneNewLabel').value = '';
  document.querySelectorAll('#zoneFishingTypes .ck-lv-seg').forEach((b) => b.classList.toggle('active', b.dataset.ftype === 'normal'));
  document.querySelectorAll('#zoneFishingRegions .ck-lv-seg').forEach((b) => b.classList.toggle('active', b.dataset.fregion === 'coast'));
  renderZoneFactionPick();
  syncZoneFactionRow();
  renderZoneNewCoords();
  document.getElementById('zoneNewModal').classList.remove('hidden');
}
function closeZoneNewModal() {
  zoneWalkPolyUiHidden = false;

  zoneNewOpen = false;
  document.getElementById('zoneNewModal').classList.add('hidden');
}
document.getElementById('zoneNewBtn').addEventListener('click', () => openZoneNewModal('zone'));
document.getElementById('beaconNewBtn').addEventListener('click', () => openZoneNewModal('beacon'));

document.getElementById('zonePvOffBtn').addEventListener('click', () => {
  fetch('https://cookie_admin/stopPosPreview', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
  }).catch(() => {});
});
document.getElementById('beaconPvOffBtn').addEventListener('click', () => {
  fetch('https://cookie_admin/stopPosPreview', { method:'POST', headers:{'Content-Type':'application/json'}, body:'{}' }).catch(()=>{});
});
document.getElementById('zoneNewCancel').addEventListener('click', closeZoneNewModal);

document.querySelectorAll('#zoneNewTypes .ck-lv-seg').forEach((seg) => {
  seg.addEventListener('click', () => {
    zoneNewType = seg.dataset.type;
    document.querySelectorAll('#zoneNewTypes .ck-lv-seg').forEach((b) => b.classList.toggle('active', b === seg));
    syncZoneFactionRow();
  });
});

document.querySelectorAll('#zoneFishingTypes .ck-lv-seg').forEach((seg) => {
  seg.addEventListener('click', () => {
    zoneNewFishingType = seg.dataset.ftype === 'boat' ? 'boat' : 'normal';
    document.querySelectorAll('#zoneFishingTypes .ck-lv-seg').forEach((b) => b.classList.toggle('active', b === seg));
  });
});

document.querySelectorAll('#zoneFishingRegions .ck-lv-seg').forEach((seg) => {
  seg.addEventListener('click', () => {
    zoneNewFishingRegion = seg.dataset.fregion || 'coast';
    document.querySelectorAll('#zoneFishingRegions .ck-lv-seg').forEach((b) => b.classList.toggle('active', b === seg));
  });
});

document.getElementById('zoneNewExtractCircle').addEventListener('click', () => requestExtract('circle'));
document.getElementById('zoneNewExtractBox').addEventListener('click', () => requestExtract('box'));

let zoneWalkPolyUiHidden = false;

const zoneNewWalkPoly = document.getElementById('zoneNewWalkPoly');
if (zoneNewWalkPoly) zoneNewWalkPoly.addEventListener('click', async () => {
  if (!['safezone','fishing','mining','afkzone'].includes(zoneNewType)) {
    showToast('이동형 범위는 보호구역/낚시 포인트/광산/잠수존에서만 사용할 수 있습니다', true);
    return;
  }

  // V13.9.4: 월드에서 이동형 범위를 찍는 동안 새 좌표 모달이 화면을 가리지 않게 숨긴다.
  const modal = document.getElementById('zoneNewModal');
  if (modal) {
    modal.classList.add('hidden');
    zoneWalkPolyUiHidden = true;
  }
  try {
    const r = await fetch('https://cookie_admin/startWalkZoneCapture', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type: zoneNewType }),
    });
    const d = await r.json().catch(() => ({}));
    if (d && d.ok === false) {
      showToast(d.error || '이동 범위 지정을 시작하지 못했습니다', true);
      document.getElementById('zoneNewModal')?.classList.remove('hidden');
      zoneWalkPolyUiHidden = false;
    }
  } catch (_) {
    document.getElementById('zoneNewModal')?.classList.remove('hidden');
    zoneWalkPolyUiHidden = false;
    showToast('이동 범위 지정을 시작하지 못했습니다', true);
  }
});

document.getElementById('zoneNewEdit').addEventListener('click', () => {
  if (!lastPosResult) return;
  postSimple('enterBoxEdit');
});

const beaconColorInput = document.getElementById('beaconColor');
if (beaconColorInput) beaconColorInput.addEventListener('input', () => {
  const t = document.getElementById('beaconColorText'); if (t) t.textContent = beaconColorInput.value.toUpperCase();
});

document.getElementById('zoneNewSave').addEventListener('click', () => {
  if (!lastPosResult) {
    showToast('먼저 좌표를 추출하세요', true);
    return;
  }
  const label = document.getElementById('zoneNewLabel').value.trim();
  if (!label) {
    showToast('이름을 입력하세요', true);
    return;
  }

  let teleportX = null, teleportY = null, teleportZ = null, teleportH = 0;
  if (zoneNewType === 'teleport') {
    teleportX = Number(document.getElementById('teleportTargetX').value);
    teleportY = Number(document.getElementById('teleportTargetY').value);
    teleportZ = Number(document.getElementById('teleportTargetZ').value);
    teleportH = Number(document.getElementById('teleportTargetH').value || 0);
    if (![teleportX, teleportY, teleportZ, teleportH].every(Number.isFinite) ||
        document.getElementById('teleportTargetX').value.trim() === '' ||
        document.getElementById('teleportTargetY').value.trim() === '' ||
        document.getElementById('teleportTargetZ').value.trim() === '') {
      showToast('텔레포트 목적지 X/Y/Z 좌표를 입력하세요', true);
      return;
    }
  }

  fetch('https://cookie_admin/saveZone', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      type: zoneNewType, label: label, factionId: zoneNewFaction,
      fishingType: zoneNewType === 'fishing' ? zoneNewFishingType : null,
      fishingRegion: zoneNewType === 'fishing' ? zoneNewFishingRegion : null,
      beaconColor: zoneNewMode === 'beacon' ? document.getElementById('beaconColor').value : null,
      teleportX, teleportY, teleportZ, teleportH,
    }),
  }).catch(() => {});

  closeZoneNewModal();
});

let fishPointSettingsTarget = null;
let fishPointSettingsType = 'normal';
let fishPointSettingsRegion = 'coast';
let fishPointSettingsData = null;
let fishPointSettingsError = '';

function zoneLootRowHtml(r, kind) {
  const color = r.gradeColor || r.rarityColor || '#9ca3af';
  const sub = r.gradeLabel || r.rarityLabel || '-';
  return '<div class="ck-zone-loot-row" data-loot-key="'+escapeHtml(r.key)+'">'+
    '<label class="ck-zone-loot-check"><input type="checkbox" '+(r.enabled?'checked':'')+'><span></span></label>'+
    '<i style="background:'+escapeHtml(color)+'"></i>'+
    '<div class="ck-zone-loot-name"><b>'+escapeHtml(r.label)+'</b><small>'+escapeHtml(sub)+'</small></div>'+
    '<label class="ck-zone-loot-weight"><span>가중치</span><input type="number" min="0" max="100000" step="0.01" value="'+Number(r.weight||0)+'"></label>'+
  '</div>';
}

function renderFishingPointFishList() {
  const list=document.getElementById('fishPointFishList');
  if(!list)return;
  const d=fishPointSettingsData;
  if(!d||!Array.isArray(d.fish)){list.innerHTML=fishPointSettingsError?'<div class="ck-skin-empty"><b>'+escapeHtml(fishPointSettingsError)+'</b><br><button id="fishZoneRetry" class="ck-fc-abtn" style="margin-top:12px">다시 불러오기</button></div>':'<div class="ck-skin-empty">어종 설정을 불러오는 중입니다...</div>';const rb=document.getElementById('fishZoneRetry');if(rb)rb.onclick=()=>{fishPointSettingsError='';renderFishingPointFishList();fetch('https://cookie_admin/requestFishingPointFish',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:fishPointSettingsTarget?.id})}).catch(()=>{});};return;}
  const groups={};
  d.fish.forEach(f=>{const k=f.grade||'etc';if(!groups[k])groups[k]={label:f.gradeLabel||k,color:f.gradeColor||'#9ca3af',rows:[]};groups[k].rows.push(f);});
  const order=Array.isArray(d.gradeOrder)?d.gradeOrder:Object.keys(groups);
  list.innerHTML=order.filter(k=>groups[k]).map(k=>{
    const g=groups[k];
    return '<div class="ck-zone-loot-group"><div class="ck-zone-loot-head"><i style="background:'+escapeHtml(g.color)+'"></i><b>'+escapeHtml(g.label)+'</b><span>'+g.rows.filter(x=>x.enabled).length+'/'+g.rows.length+'</span></div>'+g.rows.map(r=>zoneLootRowHtml(r,'fish')).join('')+'</div>';
  }).join('');
  list.querySelectorAll('.ck-zone-loot-row input[type="checkbox"]').forEach(c=>c.addEventListener('change',()=>{}));
}

function openFishingPointSettings(z) {
  fishPointSettingsTarget = z;
  fishPointSettingsData = null;
  fishPointSettingsError = '';
  fishPointSettingsType = z.fishingType === 'boat' ? 'boat' : 'normal';
  fishPointSettingsRegion = z.fishingRegion || (fishPointSettingsType === 'boat' ? 'offshore' : 'coast');
  const name = document.getElementById('fishPointSettingsName');
  if (name) name.textContent = z.label || ('#' + z.id);
  document.querySelectorAll('#fishPointSettingsTypes .ck-lv-seg').forEach((b) => b.classList.toggle('active', b.dataset.ftype === fishPointSettingsType));
  document.querySelectorAll('#fishPointSettingsRegions .ck-lv-seg').forEach((b) => b.classList.toggle('active', b.dataset.fregion === fishPointSettingsRegion));
  renderFishingPointFishList();
  document.getElementById('fishPointSettingsModal')?.classList.remove('hidden');
  fetch('https://cookie_admin/requestFishingPointFish',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:z.id})}).catch(()=>{}); setTimeout(()=>{if(fishPointSettingsTarget&&Number(fishPointSettingsTarget.id)===Number(z.id)&&!fishPointSettingsData){fishPointSettingsError='어종 설정 DB 응답이 없습니다. 서버 콘솔의 [cookie_admin] V159 fish request 로그를 확인하세요.';renderFishingPointFishList();}},8000);
}
function closeFishingPointSettings() {
  document.getElementById('fishPointSettingsModal')?.classList.add('hidden');
  fishPointSettingsTarget = null;
  fishPointSettingsData = null;
}

document.querySelectorAll('#fishPointSettingsTypes .ck-lv-seg').forEach((b) => b.addEventListener('click', () => {
  fishPointSettingsType = b.dataset.ftype === 'boat' ? 'boat' : 'normal';
  document.querySelectorAll('#fishPointSettingsTypes .ck-lv-seg').forEach((x) => x.classList.toggle('active', x === b));
}));
document.querySelectorAll('#fishPointSettingsRegions .ck-lv-seg').forEach((b) => b.addEventListener('click', () => {
  fishPointSettingsRegion = b.dataset.fregion || 'coast';
  document.querySelectorAll('#fishPointSettingsRegions .ck-lv-seg').forEach((x) => x.classList.toggle('active', x === b));
}));
document.getElementById('fishPointAllOn')?.addEventListener('click',()=>document.querySelectorAll('#fishPointFishList .ck-zone-loot-row input[type="checkbox"]').forEach(x=>x.checked=true));
document.getElementById('fishPointAllOff')?.addEventListener('click',()=>document.querySelectorAll('#fishPointFishList .ck-zone-loot-row input[type="checkbox"]').forEach(x=>x.checked=false));
document.getElementById('fishPointSettingsCancel')?.addEventListener('click', closeFishingPointSettings);
document.getElementById('fishPointSettingsSave')?.addEventListener('click', () => {
  if (!fishPointSettingsTarget) return;
  const rows=[...document.querySelectorAll('#fishPointFishList .ck-zone-loot-row')].map(row=>({
    key:row.dataset.lootKey,
    enabled:!!row.querySelector('input[type="checkbox"]')?.checked,
    weight:Math.max(0,Number(row.querySelector('.ck-zone-loot-weight input')?.value)||0)
  }));
  if(!rows.some(r=>r.enabled&&r.weight>0)){showToast('최소 1종 이상의 물고기를 ON으로 설정하세요',true);return;}
  fetch('https://cookie_admin/updateFishingPointSettings',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:fishPointSettingsTarget.id,fishingType:fishPointSettingsType,fishingRegion:fishPointSettingsRegion})}).catch(()=>{});
  fetch('https://cookie_admin/saveFishingPointFish',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({zoneId:fishPointSettingsTarget.id,fish:rows})}).catch(()=>{});
  closeFishingPointSettings();
});

let miningZoneSettingsTarget=null;
let miningZoneSettingsData=null;
let miningZoneSettingsError='';
function renderMiningZoneMinerals(){
  const list=document.getElementById('miningZoneMineralList');
  if(!list)return;
  const d=miningZoneSettingsData;
  if(!d||!Array.isArray(d.minerals)){list.innerHTML=miningZoneSettingsError?'<div class="ck-skin-empty"><b>'+escapeHtml(miningZoneSettingsError)+'</b><br><button id="miningZoneRetry" class="ck-fc-abtn" style="margin-top:12px">다시 불러오기</button></div>':'<div class="ck-skin-empty">광물 설정을 불러오는 중입니다...</div>';const rb=document.getElementById('miningZoneRetry');if(rb)rb.onclick=()=>{miningZoneSettingsError='';renderMiningZoneMinerals();fetch('https://cookie_admin/requestMiningZoneSettings',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:miningZoneSettingsTarget?.id})}).catch(()=>{});};return;}
  const groups={};
  d.minerals.forEach(m=>{const k=m.rarity||'etc';if(!groups[k])groups[k]={label:m.rarityLabel||k,color:m.rarityColor||'#9ca3af',rows:[]};groups[k].rows.push(m);});
  const order=Array.isArray(d.rarityOrder)?d.rarityOrder:Object.keys(groups);
  list.innerHTML=order.filter(k=>groups[k]).map(k=>{
    const g=groups[k];
    return '<div class="ck-zone-loot-group"><div class="ck-zone-loot-head"><i style="background:'+escapeHtml(g.color)+'"></i><b>'+escapeHtml(g.label)+'</b><span>'+g.rows.filter(x=>x.enabled).length+'/'+g.rows.length+'</span></div>'+g.rows.map(r=>zoneLootRowHtml(r,'mineral')).join('')+'</div>';
  }).join('');
}
function openMiningZoneSettings(z){
  miningZoneSettingsTarget=z;miningZoneSettingsData=null;miningZoneSettingsError='';
  const n=document.getElementById('miningZoneSettingsName');if(n)n.textContent=z.label||('#'+z.id);
  renderMiningZoneMinerals();
  document.getElementById('miningZoneSettingsModal')?.classList.remove('hidden');
  fetch('https://cookie_admin/requestMiningZoneSettings',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:z.id})}).catch(()=>{});setTimeout(()=>{if(miningZoneSettingsTarget&&Number(miningZoneSettingsTarget.id)===Number(z.id)&&!miningZoneSettingsData){miningZoneSettingsError='5초 동안 광물 설정 응답이 없습니다.';renderMiningZoneMinerals();}},5000);
}
function closeMiningZoneSettings(){document.getElementById('miningZoneSettingsModal')?.classList.add('hidden');miningZoneSettingsTarget=null;miningZoneSettingsData=null;}
document.getElementById('miningZoneAllOn')?.addEventListener('click',()=>document.querySelectorAll('#miningZoneMineralList .ck-zone-loot-row input[type="checkbox"]').forEach(x=>x.checked=true));
document.getElementById('miningZoneAllOff')?.addEventListener('click',()=>document.querySelectorAll('#miningZoneMineralList .ck-zone-loot-row input[type="checkbox"]').forEach(x=>x.checked=false));
document.getElementById('miningZoneSettingsCancel')?.addEventListener('click',closeMiningZoneSettings);
document.getElementById('miningZoneSettingsSave')?.addEventListener('click',()=>{
  if(!miningZoneSettingsTarget)return;
  const rows=[...document.querySelectorAll('#miningZoneMineralList .ck-zone-loot-row')].map(row=>({key:row.dataset.lootKey,enabled:!!row.querySelector('input[type="checkbox"]')?.checked,weight:Math.max(0,Number(row.querySelector('.ck-zone-loot-weight input')?.value)||0)}));
  if(!rows.some(r=>r.enabled&&r.weight>0)){showToast('최소 1종 이상의 광물을 ON으로 설정하세요',true);return;}
  fetch('https://cookie_admin/saveMiningZoneSettings',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({zoneId:miningZoneSettingsTarget.id,minerals:rows})}).catch(()=>{});
  closeMiningZoneSettings();
});

let previewMetaPending = '';
function applyZonePreviewUI(on, label) {
  overlay.classList.toggle('hidden', on);
  document.getElementById('zonePreviewBar').classList.toggle('hidden', !on);
  if (label) document.getElementById('zonePreviewName').textContent = label;
  document.getElementById('zonePreviewMeta').textContent = on ? previewMetaPending : '';
}
document.getElementById('zonePreviewClose').addEventListener('click', () => {
  fetch('https://cookie_admin/closeZonePreview', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
  }).catch(() => {});
});

let npcData = null;
let npcView = 'list';
let npcDraft = null;
let npcFishing = null;
let fishingNpc = null;
let npcMining = null;
let miningNpc = null;

function openNpcConsole() {
  document.getElementById('npcConsole').classList.remove('hidden');
  fcPost('requestNpcAdmin', {});
  renderNpcMain();
}

function closeNpcConsole() {
  document.getElementById('npcConsole').classList.add('hidden');
  fcPost('npcEditStop', {});
}

function npcNewDraft() {
  return { id: 0, label: '', model: 'a_m_y_business_01', scenario: '', components: [],
           x: null, y: null, z: null, heading: 0, job_key: '' };
}

function npcScenarioLabel(key) {
  const s = (npcData.scenarios || []).find((x) => x.key === (key || ''));
  return s ? s.label : '없음';
}

function npcJobLabel(key) {
  const j = (npcData.jobKeys || []).find((x) => x.key === (key || ''));
  return j ? j.label : '없음';
}

function npcJobOptions(sel) {
  return (npcData.jobKeys || [{ key: '', label: '없음 (대화 안 함)' }]).map((j) =>
    '<option value="' + escapeHtml(j.key) + '"' + (j.key === (sel || '') ? ' selected' : '') + '>' +
      escapeHtml(j.label) + '</option>').join('');
}

function npcCollect() {
  if (!npcDraft) return;
  const l = document.getElementById('npcLabel');
  const j = document.getElementById('npcJob');
  if (l) npcDraft.label = l.value.trim();
  if (j) npcDraft.job_key = j.value;
}

function renderNpcEditUi(d) {
  document.getElementById('npcVModel').innerHTML =
    escapeHtml(d.modelLabel) + '<i id="npcVGroup">' + escapeHtml(d.modelGroup || '') + '</i>';
  document.getElementById('npcVScen').textContent = d.scenarioLabel;
  document.getElementById('npcVZ').textContent = d.z;
  document.getElementById('npcVRot').textContent = d.heading + '°';

  const box = document.getElementById('npcComps');
  box.innerHTML = (d.comps || []).map((c) => {
    const isProp = c.key.charAt(0) === 'p';
    const id = c.key.slice(1);
    return '<div class="ck-npced-row">' +
        '<span class="ck-npced-l">' + escapeHtml(c.label) + '</span>' +
        '<button class="ck-npced-b" data-act="comp" data-id="' + id + '" data-prop="' +
          (isProp ? 1 : 0) + '" data-d="-1">‹</button>' +
        '<span class="ck-npced-v' + (c.changed ? ' on' : '') + '">' + escapeHtml(c.value) + '</span>' +
        '<button class="ck-npced-b" data-act="comp" data-id="' + id + '" data-prop="' +
          (isProp ? 1 : 0) + '" data-d="1">›</button>' +
        '<button class="ck-npced-b tex" data-act="comp" data-id="' + id + '" data-prop="' +
          (isProp ? 1 : 0) + '" data-d="1" data-tex="1" title="색 변경">색</button>' +
      '</div>';
  }).join('');
}

document.getElementById('npcEditBar').addEventListener('click', (e) => {
  const b = e.target.closest('[data-act]');
  if (!b) return;

  const act = b.dataset.act;
  if (act === 'model') {
    fcPost('npcModel', { d: parseInt(b.dataset.d, 10) });
  } else if (act === 'scenario') {
    fcPost('npcScenario', { d: parseInt(b.dataset.d, 10) });
  } else if (act === 'comp') {
    fcPost('npcComp', {
      id: parseInt(b.dataset.id, 10),
      prop: b.dataset.prop === '1',
      d: parseInt(b.dataset.d, 10),
      tex: b.dataset.tex === '1',
    });
  } else if (act === 'move') {
    fcPost('npcMove', {
      dx: parseInt(b.dataset.dx || '0', 10),
      dy: parseInt(b.dataset.dy || '0', 10),
      dz: parseInt(b.dataset.dz || '0', 10),
    });
  } else if (act === 'rot') {
    fcPost('npcRotate', { d: parseInt(b.dataset.d, 10) });
  } else if (act === 'tome') {
    fcPost('npcToMe', {});
  } else if (act === 'ground') {
    fcPost('npcGround', {});
  }
});

document.getElementById('npcEdOk').addEventListener('click', () => fcPost('npcConfirm', {}));
document.getElementById('npcEdCancel').addEventListener('click', () => fcPost('npcCancel', {}));

function renderNpcNav() {
  const nav = document.getElementById('npcNav');
  if (!nav || !npcData) return;

  let h =
    '<div class="ck-fc-brand"><p class="ck-fc-brand-n">직업 NPC</p><span style="font-size:9px;color:#b58a00">LABOR+DELIVERY V2</span></div>' +
    '<p class="ck-fc-sec">관리</p>' +
    '<button class="ck-fc-navbtn' + (npcView === 'new' ? ' active' : '') + '" data-nv="new">새 NPC 배치</button>' +

    '<p class="ck-fc-sec">직업 설정</p>' +
    '<button class="ck-fc-navbtn' + (npcView === 'hail' ? ' active' : '') + '" data-nv="hail">택시</button>' +
    '<button class="ck-fc-navbtn' + (npcView === 'truck' ? ' active' : '') + '" data-nv="truck">트럭커</button>' +
    '<button class="ck-fc-navbtn' + (npcView === 'labor' ? ' active' : '') + '" data-nv="labor">건설 인부</button>' +
    '<button class="ck-fc-navbtn' + (npcView === 'delivery' ? ' active' : '') + '" data-nv="delivery">배달기사</button>' +
    '<button class="ck-fc-navbtn' + (npcView === 'mechanic' ? ' active' : '') + '" data-nv="mechanic">정비공</button>' +
    '<button class="ck-fc-navbtn' + (npcView === 'fishing' ? ' active' : '') + '" data-nv="fishing">낚시</button>' +
    '<button class="ck-fc-navbtn' + (npcView === 'mining' ? ' active' : '') + '" data-nv="mining">광질</button>' +
    '<p class="ck-fc-sec">배치됨 ' + (npcData.rows || []).length + '</p>';

  (npcData.rows || []).forEach((r) => {
    h += '<button class="ck-fc-navbtn' + (npcView === r.id ? ' active' : '') + '" data-nv="' + r.id + '">' +
      escapeHtml(r.label) + '<span class="ck-fc-navtag">' + escapeHtml(r.model) + '</span></button>';
  });

  nav.innerHTML = h;
  nav.querySelectorAll('.ck-fc-navbtn').forEach((b) => b.addEventListener('click', () => {
    const v = b.dataset.nv;
    npcView = (v === 'new' || v === 'hail' || v === 'truck' || v === 'labor' || v === 'delivery' || v === 'mechanic' || v === 'fishing' || v === 'mining') ? v : parseInt(v, 10);
    npcDraft = null;

    if (npcView === 'hail') { fcPost('hailList', {}); fcPost('taxiPayGet', {}); }
    if (npcView === 'truck') {
      npcTruck = null;
      const rows = ((npcData && npcData.rows) || []).filter((r) => r.job_key === 'trucker');
      truckNpc = rows[0] ? Number(rows[0].id) : null;
      if (truckNpc) fcPost('truckList', { npcId: truckNpc });
      fcPost('truckPayGet', {});
    }
    if (npcView === 'labor') {
      npcLabor = null;
      const rows = ((npcData && npcData.rows) || []).filter((r) => r.job_key === 'labor');
      laborNpc = rows[0] ? Number(rows[0].id) : null;
      if (laborNpc) fcPost('laborList', { npcId: laborNpc });
    }
    if (npcView === 'delivery') {
      window.__npcDelivery = null;
      const rows = ((npcData && npcData.rows) || []).filter((r) => r.job_key === 'delivery');
      window.__dnpc = rows[0] ? Number(rows[0].id) : null;
      if (window.__dnpc) fcPost('deliveryList', { npcId: window.__dnpc });
    }
    if (npcView === 'mechanic') {
      npcMechanic = null;
      const rows = ((npcData && npcData.rows) || []).filter((r) => r.job_key === 'mechanic');
      mechanicNpc = rows[0] ? Number(rows[0].id) : null;
      if (mechanicNpc) fcPost('mechanicList', { npcId: mechanicNpc });
    }
    if (npcView === 'fishing') { npcFishing = null; fishingNpc = null; }
    if (npcView === 'mining') { npcMining = null; miningNpc = null; const rows=((npcData&&npcData.rows)||[]).filter(r=>r.job_key==='mining'); miningNpc=rows[0]?Number(rows[0].id):null; if(miningNpc) fcPost('miningAdminList',{npcId:miningNpc}); }

    renderNpcMain();
  }));
}

let npcHails = null;

function renderNpcHails() {
  const main = document.getElementById('npcMain');
  const title = document.getElementById('npcTitle');
  const sub = document.getElementById('npcSub');
  if (!main) return;

  title.textContent = '택시 설정';
  sub.textContent = '택시 요금과 NPC 콜의 탑승·하차 위치를 한 곳에서 관리합니다';

  const tp = npcTaxiPay || {};
  const payCard =
    '<div class="ck-fc-card">' +
      '<p class="ck-fc-card-h">택시 요금 설정</p>' +
      '<div class="ck-fc-body-p">' +
        '<div class="ck-fc-fields">' +
          '<label>기본요금<input id="taxBase" type="number" min="0" value="' + Number(tp.base_fare ?? 5500) + '"></label>' +
          '<label>기본 포함거리(m)<input id="taxFree" type="number" min="0" value="' + Number(tp.free_dist ?? 1000) + '"></label>' +
          '<label>추가 거리단위(m)<input id="taxStep" type="number" min="1" value="' + Number(tp.step_dist ?? 500) + '"></label>' +
          '<label>거리단위 요금<input id="taxStepFare" type="number" min="0" value="' + Number(tp.step_fare ?? 200) + '"></label>' +
          '<label>할증료<input id="taxInter" type="number" min="0" value="' + Number(tp.intercity_fee ?? 2000) + '"></label>' +
          '<label>최대요금<input id="taxMax" type="number" min="0" value="' + Number(tp.max_fare ?? 200000) + '"></label>' +
        '</div>' +
        '<div class="ck-fc-btns"><button id="taxPaySave" class="ck-fc-btn primary">택시 요금 저장</button></div>' +
        '<p style="font-size:11px;color:#999;margin:8px 0 0">미터기 계산에 바로 반영됩니다. 저장 후 기사 재접속은 필요하지 않습니다.</p>' +
      '</div>' +
    '</div>';

  if (!npcHails) {
    main.innerHTML = payCard + '<div class="ck-skin-empty">NPC 콜 설정을 불러오는 중입니다</div>';
    const save=document.getElementById('taxPaySave');
    if(save) save.onclick=()=>fcPost('taxiPaySave',{baseFare:Number(document.getElementById('taxBase').value),freeDist:Number(document.getElementById('taxFree').value),stepDist:Number(document.getElementById('taxStep').value),stepFare:Number(document.getElementById('taxStepFare').value),intercityFee:Number(document.getElementById('taxInter').value),maxFare:Number(document.getElementById('taxMax').value)});
    return;
  }

  const rows = npcHails.rows || [];
  const list = rows.length ? rows.map((r) => {
    const done = r.hasPickup && r.hasDrop;
    return '<div class="ck-call">' +
      '<div class="ck-call-top">' +
        '<span class="ck-hail-state' + (done ? ' ok' : '') + '">' + (done ? '사용 가능' : '미완성') + '</span>' +
        '<input type="text" class="ck-hail-name" data-id="' + r.id + '" value="' + escapeHtml(r.name) + '" maxlength="60">' +
        '<button class="ck-fc-abtn ck-call-save" data-id="' + r.id + '">이름 저장</button>' +
        '<button class="ck-fc-xbtn ck-call-del" data-id="' + r.id + '">삭제</button>' +
      '</div>' +
      '<div class="ck-call-row"><span class="ck-call-k' + (r.hasPickup ? ' ok' : '') + '">탑승 위치</span>' +
        '<span class="ck-call-v">' + (r.hasPickup ? (r.px.toFixed(0)+', '+r.py.toFixed(0)+', '+r.pz.toFixed(0)) : '미설정') + '</span>' +
        '<button class="ck-fc-abtn ck-call-set" data-id="' + r.id + '" data-k="pickup">현재 위치 저장</button>' +
        '<button class="ck-fc-abtn ck-call-go" data-x="' + (r.px||0) + '" data-y="' + (r.py||0) + '" data-z="' + (r.pz||0) + '"' + (r.hasPickup?'':' disabled') + '>이동</button></div>' +
      '<div class="ck-call-row"><span class="ck-call-k' + (r.hasDrop ? ' ok' : '') + '">하차 위치</span>' +
        '<span class="ck-call-v">' + (r.hasDrop ? (r.dx.toFixed(0)+', '+r.dy.toFixed(0)+', '+r.dz.toFixed(0)) : '미설정') + '</span>' +
        '<button class="ck-fc-abtn ck-call-set" data-id="' + r.id + '" data-k="drop">현재 위치 저장</button>' +
        '<button class="ck-fc-abtn ck-call-go" data-x="' + (r.dx||0) + '" data-y="' + (r.dy||0) + '" data-z="' + (r.dz||0) + '"' + (r.hasDrop?'':' disabled') + '>이동</button></div>' +
    '</div>';
  }).join('') : '<div class="ck-skin-empty">등록된 NPC 콜이 없습니다</div>';

  main.innerHTML = payCard +
    '<div class="ck-fc-card"><p class="ck-fc-card-h">새 NPC 콜</p><div class="ck-fc-body-p">' +
      '<div class="ck-fc-fields"><label>손님 이름<input type="text" id="callName" maxlength="60" placeholder="김민준"></label></div>' +
      '<div class="ck-fc-btns"><button id="callAdd" class="ck-fc-btn primary">NPC 콜 만들기</button></div>' +
    '</div></div>' +
    '<div class="ck-fc-card"><p class="ck-fc-card-h">NPC 콜 목록 · 사용 가능 ' + (npcHails.ready||0) + ' / 전체 ' + rows.length + '</p>' +
      '<div class="ck-fc-body-p"><div class="ck-call-list">' + list + '</div></div></div>';

  document.getElementById('taxPaySave').onclick=()=>fcPost('taxiPaySave',{baseFare:Number(document.getElementById('taxBase').value),freeDist:Number(document.getElementById('taxFree').value),stepDist:Number(document.getElementById('taxStep').value),stepFare:Number(document.getElementById('taxStepFare').value),intercityFee:Number(document.getElementById('taxInter').value),maxFare:Number(document.getElementById('taxMax').value)});
  document.getElementById('callAdd').onclick=()=>{const n=document.getElementById('callName');const name=n?n.value.trim():'';if(!name){showToast('손님 이름을 입력하세요',true);return}fcPost('callAdd',{name})};
  main.querySelectorAll('.ck-call-save').forEach(b=>b.onclick=()=>{const id=parseInt(b.dataset.id,10),inp=main.querySelector('.ck-hail-name[data-id="'+id+'"]'),name=inp?inp.value.trim():'';if(!name)return showToast('이름을 입력하세요',true);fcPost('callRename',{id,name})});
  main.querySelectorAll('.ck-call-set').forEach(b=>b.onclick=()=>fcPost('callSetCoord',{id:parseInt(b.dataset.id,10),kind:b.dataset.k}));
  main.querySelectorAll('.ck-call-del').forEach(b=>b.onclick=()=>fcPost('callDelete',{id:parseInt(b.dataset.id,10)}));
  main.querySelectorAll('.ck-call-go').forEach(b=>b.onclick=()=>{if(b.disabled)return;fcPost('hailGoto',{x:parseFloat(b.dataset.x),y:parseFloat(b.dataset.y),z:parseFloat(b.dataset.z)});closeNpcConsole();closePanel()});
}

let npcTaxiPay = null;
let npcTruckPay = null;
let npcTruck = null;
let truckKind = 'spawn';
let truckNpc = null;
const TRUCK_KINDS = { spawn: '출발지', stock: '물류창고', dest: '배송지' };

function truckerNpcs() {
  return ((npcData && npcData.rows) || []).filter((r) => r.job_key === 'trucker');
}
function wireTruckPicker(main) {
  main.querySelectorAll('.ck-rtab[data-npc]').forEach((b) => b.addEventListener('click', () => {
    truckNpc = parseInt(b.dataset.npc, 10);
    fcPost('truckList', { npcId: truckNpc });
    renderNpcTruck();
  }));
}

function renderNpcTruck() {
  const main = document.getElementById('npcMain');
  const title = document.getElementById('npcTitle');
  const sub = document.getElementById('npcSub');
  if (!main) return;

  title.textContent = '트럭커 좌표';
  sub.textContent = '배차관리인을 고르고, 그 NPC의 출발지·물류창고·배송지를 등록합니다';

  const npcs = truckerNpcs();
  if (!truckNpc && npcs[0]) {
    truckNpc = Number(npcs[0].id);
    fcPost('truckList', { npcId: truckNpc });
  }
  const picker = npcs.length
    ? npcs.map((r) => '<button class="ck-rtab' + (truckNpc === r.id ? ' active' : '') + '" data-npc="' + r.id + '">' + escapeHtml(r.label) + '</button>').join('')
    : '<span class="ck-skin-empty" style="padding:10px 0;display:block">NPC 관리에서 직업 "트럭 배차관리인" NPC를 먼저 배치하세요</span>';
  const pickerHtml = '<p class="ck-fc-sec" style="margin:0 0 8px">배차관리인 선택</p><div class="ck-rtabs" style="margin-bottom:16px">' + picker + '</div>';
  const truckPayCard = () => { const p=npcTruckPay||{}; return '<div class="ck-fc-card"><p class="ck-fc-card-h">트럭 급여 설정</p><div class="ck-fc-body-p"><div class="ck-fc-fields">'+
    '<label>화물 단가 최소<input id="trkMin" type="number" min="0" value="'+Number(p.cargo_min??315)+'"></label>'+
    '<label>화물 단가 최대<input id="trkMaxC" type="number" min="0" value="'+Number(p.cargo_max??450)+'"></label>'+
    '<label>KM당 추가급여<input id="trkKm" type="number" min="0" value="'+Number(p.per_km??500)+'"></label>'+
    '<label>1회 최대급여<input id="trkCap" type="number" min="0" value="'+Number(p.max_pay??300000)+'"></label></div>'+
    '<div class="ck-fc-btns"><button id="trkPaySave" class="ck-fc-btn primary">트럭 급여 저장</button></div></div></div>'; };
  const wireTruckPay = () => { const b=document.getElementById('trkPaySave'); if(b)b.onclick=()=>fcPost('truckPaySave',{cargoMin:Number(document.getElementById('trkMin').value),cargoMax:Number(document.getElementById('trkMaxC').value),perKm:Number(document.getElementById('trkKm').value),maxPay:Number(document.getElementById('trkCap').value)}); };

  if (!truckNpc) { main.innerHTML = pickerHtml + truckPayCard() + '<div class="ck-skin-empty">위에서 배차관리인을 고르세요</div>'; wireTruckPay(); wireTruckPicker(main); return; }
  if (!npcTruck || npcTruck.npcId !== truckNpc) { main.innerHTML = pickerHtml + truckPayCard() + '<div class="ck-skin-empty">설정을 불러오는 중입니다</div>'; wireTruckPay(); wireTruckPicker(main); return; }

  const rows = npcTruck[truckKind] || [];
  const isStock = truckKind === 'stock';
  const isDest = truckKind === 'dest';

  const tabs = Object.keys(TRUCK_KINDS).map((k) =>
    '<button class="ck-rtab' + (truckKind === k ? ' active' : '') + '" data-tk="' + k + '">' +
    TRUCK_KINDS[k] + ' ' + ((npcTruck[k] || []).length) + '</button>').join('');

  const list = rows.length
    ? rows.map((r) =>
      '<div class="ck-call">' +
        '<div class="ck-call-top">' +
          '<span class="ck-hail-state' + (r.has ? ' ok' : '') + '">' + (r.has ? '좌표 있음' : '좌표 없음') + '</span>' +
          '<input type="text" class="ck-hail-name" data-id="' + r.id + '" value="' + escapeHtml(r.label) + '" maxlength="60">' +
          '<button class="ck-fc-abtn tk-rename" data-id="' + r.id + '">이름 저장</button>' +
          '<button class="ck-fc-xbtn tk-del" data-id="' + r.id + '">제거</button>' +
        '</div>' +
        '<div class="ck-call-row">' +
          '<span class="ck-call-k' + (r.has ? ' ok' : '') + '">좌표</span>' +
          '<span class="ck-call-v">' + (r.has ? (r.x.toFixed(0) + ', ' + r.y.toFixed(0) + ', ' + r.z.toFixed(0)) : '아직 안 찍음') + '</span>' +
          '<button class="ck-fc-abtn tk-set" data-id="' + r.id + '">좌표 다시 따기</button>' +
          '<button class="ck-fc-abtn tk-go" data-x="' + (r.x || 0) + '" data-y="' + (r.y || 0) + '" data-z="' + (r.z || 0) + '"' + (r.has ? '' : ' disabled') + '>이동하기</button>' +
        '</div>' +
        (isStock
          ? '<div class="ck-call-row">' +
              '<span class="ck-call-k ok">하루 한도</span>' +
              '<input type="number" class="tk-limit" data-id="' + r.id + '" value="' + (r.limit || 1000) + '" min="1" style="width:120px;padding:6px 10px;border-radius:8px;border:1px solid #e0e0e0">' +
              '<button class="ck-fc-abtn tk-limit-save" data-id="' + r.id + '">한도 저장</button>' +
            '</div>'
          : '') +
        (isDest
          ? '<div class="ck-call-row">' +
              '<span class="ck-call-k' + (r.hasImg ? ' ok' : '') + '">장면</span>' +
              '<span class="ck-call-v">' + (r.hasImg ? '촬영됨' : '없음') + '</span>' +
              '<button class="ck-fc-abtn tk-shot" data-id="' + r.id + '">장면 촬영 (자유캠 · 좌클릭)</button>' +
            '</div>' +
            '<div class="ck-call-row">' +
              '<span class="ck-call-k ok">보수</span>' +
              '<span class="ck-call-v" style="color:#7a6500">자동 (박스 315~450 × 적재량 + 거리 500/km)</span>' +
            '</div>'
          : '') +
      '</div>').join('')
    : '<div class="ck-skin-empty">등록된 ' + TRUCK_KINDS[truckKind] + '가 없습니다</div>';

  main.innerHTML = pickerHtml + truckPayCard() +
    '<div class="ck-rtabs" style="margin-bottom:14px">' + tabs + '</div>' +
    '<div class="ck-fc-card">' +
      '<p class="ck-fc-card-h">새 ' + TRUCK_KINDS[truckKind] + ' (지금 서 있는 자리로 등록)</p>' +
      '<div class="ck-fc-body-p"><div class="ck-fc-fields">' +
        '<label>이름<input type="text" id="tkName" maxlength="60" placeholder="' + (isStock ? '항구창고' : (truckKind === 'spawn' ? '남부출발지' : '샌디쇼어')) + '"></label>' +
        (isStock ? '<label>하루 한도<input type="number" id="tkLimit" value="1000" min="1"></label>' : '') +
      '</div><div class="ck-fc-btns">' +
        '<button id="tkAdd" class="ck-fc-btn primary">생성 (현재 위치)</button>' +
      '</div></div>' +
    '</div>' +
    '<div class="ck-fc-card">' +
      '<p class="ck-fc-card-h">등록된 ' + TRUCK_KINDS[truckKind] + ' (' + rows.length + ')</p>' +
      '<div class="ck-fc-body-p"><div class="ck-call-list">' + list + '</div></div>' +
    '</div>';

  wireTruckPay(); wireTruckPicker(main);
  main.querySelectorAll('.ck-rtab[data-tk]').forEach((b) => b.addEventListener('click', () => { truckKind = b.dataset.tk; renderNpcTruck(); }));

  document.getElementById('tkAdd').addEventListener('click', () => {
    const n = document.getElementById('tkName');
    const name = n ? n.value.trim() : '';
    if (!name) { showToast('이름을 입력하세요', true); return; }
    const lim = isStock ? (parseInt((document.getElementById('tkLimit') || {}).value, 10) || 1000) : null;
    fcPost('truckAdd', { kind: truckKind, label: name, limit: lim, npcId: truckNpc });
  });

  main.querySelectorAll('.tk-rename').forEach((b) => b.addEventListener('click', () => {
    const id = parseInt(b.dataset.id, 10);
    const inp = main.querySelector('.ck-hail-name[data-id="' + id + '"]');
    const name = inp ? inp.value.trim() : '';
    if (!name) { showToast('이름을 입력하세요', true); return; }
    fcPost('truckRename', { kind: truckKind, id: id, name: name, npcId: truckNpc });
  }));

  main.querySelectorAll('.tk-set').forEach((b) => b.addEventListener('click', () =>
    fcPost('truckSetCoord', { kind: truckKind, id: parseInt(b.dataset.id, 10), npcId: truckNpc })));

  main.querySelectorAll('.tk-del').forEach((b) => b.addEventListener('click', () =>
    fcPost('truckDelete', { kind: truckKind, id: parseInt(b.dataset.id, 10), npcId: truckNpc })));

  main.querySelectorAll('.tk-limit-save').forEach((b) => b.addEventListener('click', () => {
    const id = parseInt(b.dataset.id, 10);
    const inp = main.querySelector('.tk-limit[data-id="' + id + '"]');
    const lim = inp ? (parseInt(inp.value, 10) || 1000) : 1000;
    fcPost('truckSetLimit', { id: id, limit: lim, npcId: truckNpc });
  }));

  main.querySelectorAll('.tk-shot').forEach((b) => b.addEventListener('click', () => {
    fcPost('truckDestShot', { id: parseInt(b.dataset.id, 10), npcId: truckNpc });
  }));

  main.querySelectorAll('.tk-go').forEach((b) => b.addEventListener('click', () => {
    if (b.disabled) return;
    fcPost('hailGoto', { x: parseFloat(b.dataset.x), y: parseFloat(b.dataset.y), z: parseFloat(b.dataset.z) });
    closeNpcConsole();
    closePanel();
  }));
}



let npcLabor = null;
let laborNpc = null;

function laborNpcs() {
  return ((npcData && npcData.rows) || []).filter((r) => r.job_key === 'labor');
}

function wireLaborPicker(main) {
  main.querySelectorAll('.ck-rtab[data-labornpc]').forEach((b) => b.addEventListener('click', () => {
    laborNpc = parseInt(b.dataset.labornpc, 10);
    npcLabor = null;
    fcPost('laborList', { npcId: laborNpc });
    renderNpcLabor();
  }));
}

function renderNpcLabor() {
  const main = document.getElementById('npcMain');
  const title = document.getElementById('npcTitle');
  const sub = document.getElementById('npcSub');
  if (!main) return;

  title.textContent = '건설 인부 작업 설정';
  sub.textContent = '현장 반장 NPC마다 상자 더미 위치 · 운반 목적지 · 상자 수 · 보수를 설정합니다';

  const npcs = laborNpcs();
  const picker = npcs.length
    ? npcs.map((r) => '<button class="ck-rtab' + (laborNpc === r.id ? ' active' : '') +
      '" data-labornpc="' + r.id + '">' + escapeHtml(r.label) + '</button>').join('')
    : '<span class="ck-skin-empty" style="padding:10px 0;display:block">NPC 관리에서 직업 "건설 현장 반장" NPC를 먼저 배치하세요</span>';

  const pickerHtml =
    '<p class="ck-fc-sec" style="margin:0 0 8px">현장 반장 선택</p>' +
    '<div class="ck-rtabs" style="margin-bottom:16px">' + picker + '</div>';

  if (!laborNpc) {
    main.innerHTML = pickerHtml + '<div class="ck-skin-empty">위에서 현장 반장을 고르세요</div>';
    wireLaborPicker(main);
    return;
  }

  if (!npcLabor || Number(npcLabor.npcId) !== laborNpc) {
    main.innerHTML = pickerHtml + '<div class="ck-skin-empty">작업 설정을 불러오는 중입니다</div>';
    wireLaborPicker(main);
    fcPost('laborList', { npcId: laborNpc });
    return;
  }

  const rows = npcLabor.rows || [];
  const list = rows.length ? rows.map((r) => {
    const ready = r.hasSource && r.hasDest;
    const sx = r.hasSource ? (Number(r.source_x).toFixed(0)+', '+Number(r.source_y).toFixed(0)+', '+Number(r.source_z).toFixed(0)) : '아직 안 찍음';
    const dx = r.hasDest ? (Number(r.dest_x).toFixed(0)+', '+Number(r.dest_y).toFixed(0)+', '+Number(r.dest_z).toFixed(0)) : '아직 안 찍음';

    return '<div class="ck-call ck-labor-card">' +
      '<div class="ck-call-top">' +
        '<span class="ck-hail-state' + (ready ? ' ok' : '') + '">' + (ready ? '사용 가능' : '미완성') + '</span>' +
        '<input type="text" class="ck-hail-name labor-name" data-id="' + r.id + '" value="' + escapeHtml(r.label) + '" maxlength="80">' +
        '<button class="ck-fc-abtn labor-save" data-id="' + r.id + '">저장</button>' +
        '<button class="ck-fc-xbtn labor-del" data-id="' + r.id + '">삭제</button>' +
      '</div>' +

      '<div class="ck-call-row">' +
        '<span class="ck-call-k ok">상자 수</span>' +
        '<input type="number" class="labor-count" data-id="' + r.id + '" min="1" max="30" value="' + (r.box_count || 5) + '" style="width:100px;padding:7px 10px;border:1px solid #ddd;border-radius:8px">' +
        '<span class="ck-call-k ok" style="margin-left:8px">총 보수</span>' +
        '<input type="number" class="labor-reward" data-id="' + r.id + '" min="0" value="' + (r.reward || 25000) + '" style="width:140px;padding:7px 10px;border:1px solid #ddd;border-radius:8px">' +
      '</div>' +

      '<div class="ck-call-row">' +
        '<span class="ck-call-k' + (r.hasSource ? ' ok' : '') + '">상자 더미</span>' +
        '<span class="ck-call-v">' + sx + '</span>' +
        '<button class="ck-fc-abtn labor-set" data-id="' + r.id + '" data-kind="source">현재 위치로 저장</button>' +
        '<button class="ck-fc-abtn labor-go" data-x="' + (r.source_x || 0) + '" data-y="' + (r.source_y || 0) + '" data-z="' + (r.source_z || 0) + '"' + (r.hasSource ? '' : ' disabled') + '>이동</button>' +
      '</div>' +

      '<div class="ck-call-row">' +
        '<span class="ck-call-k' + (r.hasDest ? ' ok' : '') + '">운반 목적지</span>' +
        '<span class="ck-call-v">' + dx + '</span>' +
        '<button class="ck-fc-abtn labor-set" data-id="' + r.id + '" data-kind="dest">현재 위치로 저장</button>' +
        '<button class="ck-fc-abtn labor-go" data-x="' + (r.dest_x || 0) + '" data-y="' + (r.dest_y || 0) + '" data-z="' + (r.dest_z || 0) + '"' + (r.hasDest ? '' : ' disabled') + '>이동</button>' +
      '</div>' +
    '</div>';
  }).join('') : '<div class="ck-skin-empty">등록된 건설 작업이 없습니다</div>';

  main.innerHTML = pickerHtml +
    '<div class="ck-fc-card">' +
      '<p class="ck-fc-card-h">새 운반 작업</p>' +
      '<div class="ck-fc-body-p">' +
        '<div class="ck-fc-fields">' +
          '<label>작업 이름<input id="laborNewName" type="text" maxlength="80" placeholder="철근 창고 상자 운반"></label>' +
          '<label>옮길 상자 수<input id="laborNewCount" type="number" min="1" max="30" value="5"></label>' +
          '<label>작업 완료 보수<input id="laborNewReward" type="number" min="0" value="25000"></label>' +
        '</div>' +
        '<div style="font-size:11px;color:#999;margin:10px 0">생성 버튼을 누르면 현재 서 있는 위치가 <b>상자 더미 위치</b>로 저장됩니다. 이후 목적지로 이동해 아래 카드에서 목적지를 저장하세요.</div>' +
        '<div class="ck-fc-btns"><button id="laborAdd" class="ck-fc-btn primary">작업 생성 (현재 위치 = 상자 더미)</button></div>' +
      '</div>' +
    '</div>' +

    '<div class="ck-fc-card">' +
      '<p class="ck-fc-card-h">등록된 운반 작업 (' + rows.length + ')</p>' +
      '<div class="ck-fc-body-p"><div class="ck-call-list">' + list + '</div></div>' +
    '</div>';

  wireLaborPicker(main);

  document.getElementById('laborAdd').addEventListener('click', () => {
    const name = (document.getElementById('laborNewName').value || '').trim();
    if (!name) { showToast('작업 이름을 입력하세요', true); return; }
    fcPost('laborAdd', {
      npcId: laborNpc,
      label: name,
      count: parseInt(document.getElementById('laborNewCount').value,10) || 5,
      reward: parseInt(document.getElementById('laborNewReward').value,10) || 0
    });
  });

  main.querySelectorAll('.labor-save').forEach((b) => b.addEventListener('click', () => {
    const id = parseInt(b.dataset.id,10);
    const name = (main.querySelector('.labor-name[data-id="'+id+'"]').value || '').trim();
    fcPost('laborUpdate', {
      npcId: laborNpc, id: id, label: name,
      count: parseInt(main.querySelector('.labor-count[data-id="'+id+'"]').value,10) || 5,
      reward: parseInt(main.querySelector('.labor-reward[data-id="'+id+'"]').value,10) || 0
    });
  }));

  main.querySelectorAll('.labor-set').forEach((b) => b.addEventListener('click', () => {
    fcPost('laborSetCoord', { npcId:laborNpc, id:parseInt(b.dataset.id,10), kind:b.dataset.kind });
  }));

  main.querySelectorAll('.labor-del').forEach((b) => b.addEventListener('click', () => {
    fcPost('laborDelete', { npcId:laborNpc, id:parseInt(b.dataset.id,10) });
  }));

  main.querySelectorAll('.labor-go').forEach((b) => b.addEventListener('click', () => {
    if (b.disabled) return;
    fcPost('hailGoto', { x:parseFloat(b.dataset.x), y:parseFloat(b.dataset.y), z:parseFloat(b.dataset.z) });
    closeNpcConsole();
    closePanel();
  }));
}

let npcMechanic = null;
let mechanicNpc = null;

function mechanicNpcs() {
  return ((npcData && npcData.rows) || []).filter((r) => r.job_key === 'mechanic');
}

function wireMechanicPicker(main) {
  main.querySelectorAll('.ck-rtab[data-mechanicnpc]').forEach((b) => b.addEventListener('click', () => {
    mechanicNpc = parseInt(b.dataset.mechanicnpc, 10);
    npcMechanic = null;
    fcPost('mechanicList', { npcId: mechanicNpc });
    renderNpcMechanic();
  }));
}

function renderNpcMechanic() {
  const main=document.getElementById('npcMain'),title=document.getElementById('npcTitle'),sub=document.getElementById('npcSub');if(!main)return;
  title.textContent='정비공 작업 설정';sub.textContent='NPC 현장정비와 실제 플레이어 정비 요금을 분리해 관리합니다';
  const npcs=mechanicNpcs();
  if(!mechanicNpc&&npcs[0])mechanicNpc=Number(npcs[0].id);
  const picker=npcs.length?npcs.map(r=>'<button class="ck-rtab'+(Number(mechanicNpc)===Number(r.id)?' active':'')+'" data-mechanicnpc="'+r.id+'">'+escapeHtml(r.label)+'</button>').join(''):'<span class="ck-skin-empty">정비소 반장 NPC를 먼저 배치하세요</span>';
  const head='<p class="ck-fc-sec">정비소 반장 선택</p><div class="ck-rtabs" style="margin-bottom:16px">'+picker+'</div>';
  if(!mechanicNpc){main.innerHTML=head;wireMechanicPicker(main);return}
  const d=npcMechanic;if(!d||Number(d.npcId)!==Number(mechanicNpc)){main.innerHTML=head+'<div class="ck-skin-empty">불러오는 중</div>';wireMechanicPicker(main);fcPost('mechanicList',{npcId:mechanicNpc});return}
  const pc=d.pricing||{},rows=d.rows||[];
  const cards=rows.length?rows.map(r=>{
    const cp=r.hasCustomer?(Number(r.customer_x).toFixed(0)+', '+Number(r.customer_y).toFixed(0)+', '+Number(r.customer_z).toFixed(0)):'미설정';
    const vp=r.hasVehicle?(Number(r.vehicle_x).toFixed(0)+', '+Number(r.vehicle_y).toFixed(0)+', '+Number(r.vehicle_z).toFixed(0)+' · H '+Number(r.vehicle_h||0).toFixed(0)):'미설정';
    return '<div class="ck-call ck-labor-card"><div class="ck-call-top"><span class="ck-hail-state '+(r.hasCustomer&&r.hasVehicle?'ok':'')+'">'+(r.hasCustomer&&r.hasVehicle?'사용 가능':'미완성')+'</span>'+
      '<input class="ck-hail-name mech-name" data-id="'+r.id+'" value="'+escapeHtml(r.label)+'"><button class="ck-fc-abtn mech-save" data-id="'+r.id+'">저장</button><button class="ck-fc-xbtn mech-del" data-id="'+r.id+'">삭제</button></div>'+
      '<div class="ck-call-row"><span class="ck-call-k ok">고객 NPC 모델</span><input class="mech-ped" data-id="'+r.id+'" value="'+escapeHtml(r.ped_model||'a_m_m_business_01')+'" style="width:180px;padding:7px;border:1px solid #ddd;border-radius:8px"><span class="ck-call-k ok">차량 모델</span><input class="mech-model" data-id="'+r.id+'" value="'+escapeHtml(r.vehicle_model||'blista')+'" style="width:140px;padding:7px;border:1px solid #ddd;border-radius:8px"></div>'+
      '<div class="ck-call-row"><span class="ck-call-k ok">NPC 작업 보수</span><input class="mech-reward" data-id="'+r.id+'" type="number" value="'+(r.reward||70000)+'" style="width:130px;padding:7px;border:1px solid #ddd;border-radius:8px"><span class="ck-call-k">정비시간</span><input class="mech-secs" data-id="'+r.id+'" type="number" value="'+(r.repair_seconds||12)+'" style="width:80px;padding:7px;border:1px solid #ddd;border-radius:8px"><span class="ck-call-k">엔진/차체</span><input class="mech-engine" data-id="'+r.id+'" type="number" value="'+(r.engine_health||280)+'" style="width:80px;padding:7px;border:1px solid #ddd;border-radius:8px"><input class="mech-body" data-id="'+r.id+'" type="number" value="'+(r.body_health||650)+'" style="width:80px;padding:7px;border:1px solid #ddd;border-radius:8px"></div>'+
      '<div class="ck-call-row"><span class="ck-call-k '+(r.hasCustomer?'ok':'')+'">고객 NPC 위치</span><span class="ck-call-v">'+cp+'</span><button class="ck-fc-abtn mech-point" data-kind="customer" data-id="'+r.id+'">현재 위치 저장</button><button class="ck-fc-abtn mech-go" data-x="'+(r.customer_x||0)+'" data-y="'+(r.customer_y||0)+'" data-z="'+(r.customer_z||0)+'" '+(r.hasCustomer?'':'disabled')+'>이동</button></div>'+
      '<div class="ck-call-row"><span class="ck-call-k '+(r.hasVehicle?'ok':'')+'">고장 차량 위치</span><span class="ck-call-v">'+vp+'</span><button class="ck-fc-abtn mech-point" data-kind="vehicle" data-id="'+r.id+'">현재 위치/방향 저장</button><button class="ck-fc-abtn mech-go" data-x="'+(r.vehicle_x||0)+'" data-y="'+(r.vehicle_y||0)+'" data-z="'+(r.vehicle_z||0)+'" '+(r.hasVehicle?'':'disabled')+'>이동</button></div></div>'
  }).join(''):'<div class="ck-skin-empty">등록된 NPC 현장정비가 없습니다</div>';
  main.innerHTML=head+
    '<div class="ck-fc-card"><p class="ck-fc-card-h">실제 플레이어 정비 요금</p><div class="ck-fc-body-p"><div class="ck-fc-fields">'+
    '<label>출장 기본요금<input id="mpBase" type="number" value="'+(pc.base_fare||10000)+'"></label><label>기본 포함거리(m)<input id="mpFree" type="number" value="'+(pc.free_dist||1000)+'"></label><label>추가 거리단위(m)<input id="mpStep" type="number" value="'+(pc.step_dist||500)+'"></label><label>거리단위 요금<input id="mpStepFare" type="number" value="'+(pc.step_fare||3000)+'"></label><label>정비 기본료<input id="mpRepair" type="number" value="'+(pc.repair_fee||30000)+'"></label><label>최대 요금<input id="mpMax" type="number" value="'+(pc.max_fare||250000)+'"></label></div><div class="ck-fc-btns"><button id="mpSave" class="ck-fc-btn primary">플레이어 정비 요금 저장</button></div><p style="font-size:11px;color:#999">공식: 출장 기본요금 + 거리 단계요금 + 정비 기본료. 고객 은행에서 실제 차감됩니다.</p></div></div>'+
    '<div class="ck-fc-card"><p class="ck-fc-card-h">새 NPC 현장정비</p><div class="ck-fc-body-p"><div class="ck-fc-fields"><label>작업명<input id="mnName" placeholder="고속도로 차량 고장"></label><label>고객 NPC 모델<input id="mnPed" value="a_m_m_business_01"></label><label>차량 모델<input id="mnModel" value="blista"></label><label>NPC 작업 보수<input id="mnReward" type="number" value="70000"></label><label>정비시간(초)<input id="mnSecs" type="number" value="12"></label></div><div class="ck-fc-btns"><button id="mnAdd" class="ck-fc-btn primary">NPC 정비 작업 생성</button></div><p style="font-size:11px;color:#999">생성 후 아래에서 고객 NPC 위치와 고장 차량 위치를 각각 저장하세요.</p></div></div>'+
    '<div class="ck-fc-card"><p class="ck-fc-card-h">NPC 현장정비 목록 ('+rows.length+')</p><div class="ck-fc-body-p"><div class="ck-call-list">'+cards+'</div></div></div>';
  wireMechanicPicker(main);
  document.getElementById('mpSave').onclick=()=>fcPost('mechanicPricingSave',{npcId:mechanicNpc,baseFare:Number(document.getElementById('mpBase').value),freeDist:Number(document.getElementById('mpFree').value),stepDist:Number(document.getElementById('mpStep').value),stepFare:Number(document.getElementById('mpStepFare').value),repairFee:Number(document.getElementById('mpRepair').value),maxFare:Number(document.getElementById('mpMax').value)});
  document.getElementById('mnAdd').onclick=()=>fcPost('mechanicAdd',{npcId:mechanicNpc,label:document.getElementById('mnName').value||'현장 정비',pedModel:document.getElementById('mnPed').value||'a_m_m_business_01',model:document.getElementById('mnModel').value||'blista',reward:Number(document.getElementById('mnReward').value)||70000,seconds:Number(document.getElementById('mnSecs').value)||12});
  main.querySelectorAll('.mech-save').forEach(b=>b.onclick=()=>{let id=Number(b.dataset.id);fcPost('mechanicUpdate',{npcId:mechanicNpc,id,label:main.querySelector('.mech-name[data-id="'+id+'"]').value,pedModel:main.querySelector('.mech-ped[data-id="'+id+'"]').value,model:main.querySelector('.mech-model[data-id="'+id+'"]').value,reward:Number(main.querySelector('.mech-reward[data-id="'+id+'"]').value),seconds:Number(main.querySelector('.mech-secs[data-id="'+id+'"]').value),engineHealth:Number(main.querySelector('.mech-engine[data-id="'+id+'"]').value),bodyHealth:Number(main.querySelector('.mech-body[data-id="'+id+'"]').value)})});
  main.querySelectorAll('.mech-del').forEach(b=>b.onclick=()=>fcPost('mechanicDelete',{npcId:mechanicNpc,id:Number(b.dataset.id)}));
  main.querySelectorAll('.mech-point').forEach(b=>b.onclick=()=>fcPost('mechanicSetPoint',{npcId:mechanicNpc,id:Number(b.dataset.id),kind:b.dataset.kind}));
  main.querySelectorAll('.mech-go').forEach(b=>b.onclick=()=>{if(b.disabled)return;fcPost('hailGoto',{x:Number(b.dataset.x),y:Number(b.dataset.y),z:Number(b.dataset.z)});closeNpcConsole();closePanel()});
}

function fishingNpcs() {
  return ((npcData && npcData.rows) || []).filter((r) => r.job_key === 'fishing');
}

function wireFishingPicker(main) {
  main.querySelectorAll('.ck-rtab[data-fishnpc]').forEach((b) => b.addEventListener('click', () => {
    fishingNpc = parseInt(b.dataset.fishnpc, 10);
    npcFishing = null;
    fcPost('fishAdminList', { npcId: fishingNpc });
    renderNpcFishing();
  }));
}

function renderNpcFishing() {
  const main = document.getElementById('npcMain');
  const title = document.getElementById('npcTitle');
  const sub = document.getElementById('npcSub');
  if (!main) return;

  title.textContent = '낚시 관리인 설정';
  sub.textContent = 'NPC마다 판매하는 낚시용품과 매입하는 물고기·KG당 가격을 설정합니다';

  const npcs = fishingNpcs();
  const picker = npcs.length
    ? npcs.map((r) => '<button class="ck-rtab' + (fishingNpc === r.id ? ' active' : '') + '" data-fishnpc="' + r.id + '">' + escapeHtml(r.label) + '</button>').join('')
    : '<span class="ck-skin-empty" style="padding:10px 0;display:block">NPC 관리에서 직업 "낚시 관리인" NPC를 먼저 배치하세요</span>';
  const pickerHtml = '<p class="ck-fc-sec" style="margin:0 0 8px">낚시 관리인 선택</p><div class="ck-rtabs" style="margin-bottom:16px">' + picker + '</div>';

  if (!fishingNpc) { main.innerHTML = pickerHtml + '<div class="ck-skin-empty">위에서 낚시 관리인을 고르세요</div>'; wireFishingPicker(main); return; }
  if (!npcFishing || npcFishing.npcId !== fishingNpc) { main.innerHTML = pickerHtml + '<div class="ck-skin-empty">설정을 불러오는 중입니다</div>'; wireFishingPicker(main); return; }

  const shopRows = (npcFishing.shop || []).map((s) =>
    '<div class="ck-fc-shoprow on">' +
      '<span class="ck-fc-lname">' + escapeHtml(s.label) + '<span class="ck-arm-group">' + escapeHtml(s.item || '') + '</span></span>' +
      '<select class="fish-shop-on" data-kind="' + s.kind + '" style="width:90px;padding:7px;border:1px solid #ddd;border-radius:8px">' +
        '<option value="1"' + (s.enabled ? ' selected' : '') + '>판매 ON</option>' +
        '<option value="0"' + (!s.enabled ? ' selected' : '') + '>판매 OFF</option></select>' +
      '<input type="number" class="ck-fc-pinput fish-shop-price" data-kind="' + s.kind + '" min="0" value="' + (s.price || 0) + '" placeholder="가격">' +
      '<input type="number" class="ck-fc-pinput fish-shop-qty" data-kind="' + s.kind + '" min="1" value="' + (s.qty || 1) + '" placeholder="수량" style="width:90px">' +
      '<button class="ck-fc-abtn fish-shop-save" data-kind="' + s.kind + '">저장</button>' +
    '</div>').join('');

  const fishRows = (npcFishing.fish || []).map((f) =>
    '<div class="ck-fc-shoprow' + (f.enabled ? ' on' : '') + '">' +
      '<span class="ck-fc-lname">' + escapeHtml(f.label) + '<span class="ck-arm-group">' + escapeHtml(f.gradeLabel || f.grade) + ' · ' + f.min + '~' + f.max + 'kg</span></span>' +
      '<select class="fish-buy-on" data-key="' + f.key + '" style="width:95px;padding:7px;border:1px solid #ddd;border-radius:8px">' +
        '<option value="1"' + (f.enabled ? ' selected' : '') + '>매입 ON</option>' +
        '<option value="0"' + (!f.enabled ? ' selected' : '') + '>매입 OFF</option></select>' +
      '<input type="number" class="ck-fc-pinput fish-buy-price" data-key="' + f.key + '" min="0" value="' + (f.ppk || 0) + '" placeholder="원/kg">' +
      '<button class="ck-fc-abtn fish-buy-save" data-key="' + f.key + '">저장</button>' +
    '</div>').join('');

  main.innerHTML = pickerHtml +
    '<div class="ck-fc-card"><p class="ck-fc-card-h">낚시용품 판매</p>' +
      '<div class="ck-fc-body-p"><div class="ck-fc-lineup">' + shopRows + '</div></div></div>' +
    '<div class="ck-fc-card"><p class="ck-fc-card-h">물고기 매입 설정 (' + (npcFishing.fish || []).length + '종)</p>' +
      '<div class="ck-fc-body-p">' +
        '<input type="text" id="fishBuySearch" class="ck-fc-lsearch" placeholder="물고기 검색" autocomplete="off">' +
        '<div class="ck-fc-lineup" id="fishBuyList">' + fishRows + '</div>' +
      '</div></div>';

  wireFishingPicker(main);

  main.querySelectorAll('.fish-shop-save').forEach((b) => b.addEventListener('click', () => {
    const k = b.dataset.kind;
    const on = main.querySelector('.fish-shop-on[data-kind="' + k + '"]');
    const p = main.querySelector('.fish-shop-price[data-kind="' + k + '"]');
    const q = main.querySelector('.fish-shop-qty[data-kind="' + k + '"]');
    fcPost('fishShopSave', { npcId: fishingNpc, kind: k, enabled: on && on.value === '1', price: parseInt(p && p.value, 10) || 0, qty: parseInt(q && q.value, 10) || 1 });
  }));

  main.querySelectorAll('.fish-buy-save').forEach((b) => b.addEventListener('click', () => {
    const k = b.dataset.key;
    const on = main.querySelector('.fish-buy-on[data-key="' + k + '"]');
    const p = main.querySelector('.fish-buy-price[data-key="' + k + '"]');
    fcPost('fishBuySave', { npcId: fishingNpc, key: k, enabled: on && on.value === '1', ppk: parseInt(p && p.value, 10) || 0 });
  }));

  const search = document.getElementById('fishBuySearch');
  if (search) search.addEventListener('input', () => {
    const q = search.value.trim().toLowerCase();
    main.querySelectorAll('#fishBuyList .ck-fc-shoprow').forEach((r) => {
      r.style.display = (!q || r.textContent.toLowerCase().indexOf(q) !== -1) ? '' : 'none';
    });
  });
}


function miningNpcs() {
  return ((npcData && npcData.rows) || []).filter((r) => r.job_key === 'mining');
}
function wireMiningPicker(main) {
  main.querySelectorAll('.ck-rtab[data-miningnpc]').forEach((b)=>b.addEventListener('click',()=>{
    miningNpc=parseInt(b.dataset.miningnpc,10); npcMining=null; fcPost('miningAdminList',{npcId:miningNpc}); renderNpcMining();
  }));
}
function renderNpcMining() {
  const main=document.getElementById('npcMain'),title=document.getElementById('npcTitle'),sub=document.getElementById('npcSub'); if(!main)return;
  title.textContent='광물 관리인 설정';
  sub.textContent='NPC마다 곡괭이 판매와 광물 매입 ON/OFF·기준가를 설정합니다. 실제 매입가는 광물 순도에 따라 자동 보정됩니다.';
  const npcs=miningNpcs();
  const picker=npcs.length?npcs.map(r=>'<button class="ck-rtab'+(miningNpc===r.id?' active':'')+'" data-miningnpc="'+r.id+'">'+escapeHtml(r.label)+'</button>').join(''):'<span class="ck-skin-empty" style="padding:10px 0;display:block">NPC 관리에서 직업 "광물 관리인" NPC를 먼저 배치하세요</span>';
  const pickerHtml='<p class="ck-fc-sec" style="margin:0 0 8px">광물 관리인 선택</p><div class="ck-rtabs" style="margin-bottom:16px">'+picker+'</div>';
  if(!miningNpc){main.innerHTML=pickerHtml+'<div class="ck-skin-empty">위에서 광물 관리인을 고르세요</div>';wireMiningPicker(main);return;}
  if(!npcMining||Number(npcMining.npcId)!==Number(miningNpc)){main.innerHTML=pickerHtml+'<div class="ck-skin-empty">설정을 불러오는 중입니다</div>';wireMiningPicker(main);fcPost('miningAdminList',{npcId:miningNpc});return;}
  const shopRows=(npcMining.shop||[]).map(s=>'<div class="ck-fc-shoprow on"><span class="ck-fc-lname">'+escapeHtml(s.label)+'<span class="ck-arm-group">'+escapeHtml(s.item||'')+'</span></span><select class="mining-shop-on" data-kind="'+s.kind+'" style="width:90px;padding:7px;border:1px solid #ddd;border-radius:8px"><option value="1"'+(s.enabled?' selected':'')+'>판매 ON</option><option value="0"'+(!s.enabled?' selected':'')+'>판매 OFF</option></select><input type="number" class="ck-fc-pinput mining-shop-price" data-kind="'+s.kind+'" min="0" value="'+(s.price||0)+'" placeholder="가격"><input type="number" class="ck-fc-pinput mining-shop-qty" data-kind="'+s.kind+'" min="1" value="'+(s.qty||1)+'" style="width:90px"><button class="ck-fc-abtn mining-shop-save" data-kind="'+s.kind+'">저장</button></div>').join('');
  const mineralRows=(npcMining.minerals||[]).map(m=>'<div class="ck-fc-shoprow'+(m.enabled?' on':'')+'"><span class="ck-fc-lname">'+escapeHtml(m.label)+'<span class="ck-arm-group">'+escapeHtml(m.rarityLabel||m.rarity||'')+'</span></span><select class="mining-buy-on" data-key="'+m.key+'" style="width:95px;padding:7px;border:1px solid #ddd;border-radius:8px"><option value="1"'+(m.enabled?' selected':'')+'>매입 ON</option><option value="0"'+(!m.enabled?' selected':'')+'>매입 OFF</option></select><input type="number" class="ck-fc-pinput mining-buy-price" data-key="'+m.key+'" min="0" value="'+(m.basePrice||0)+'" placeholder="기준가"><button class="ck-fc-abtn mining-buy-save" data-key="'+m.key+'">저장</button></div>').join('');
  main.innerHTML=pickerHtml+'<div class="ck-couple-admin-note"><b>순도 가격 보정</b><span>현재 최소 x'+Number(npcMining.purityMinMultiplier||0.5).toFixed(2)+' ~ 최대 x'+Number(npcMining.purityMaxMultiplier||2).toFixed(2)+' 배율입니다. 이 값은 시스템 관리 → 광산에서 수정합니다.</span></div><div class="ck-fc-card"><p class="ck-fc-card-h">곡괭이 3단계 판매</p><div class="ck-fc-body-p"><div class="ck-fc-lineup">'+shopRows+'</div></div></div><div class="ck-fc-card"><p class="ck-fc-card-h">광물 매입 설정 ('+(npcMining.minerals||[]).length+'종)</p><div class="ck-fc-body-p"><input type="text" id="miningBuySearch" class="ck-fc-lsearch" placeholder="광물 검색" autocomplete="off"><div class="ck-fc-lineup" id="miningBuyList">'+mineralRows+'</div></div></div>';
  wireMiningPicker(main);
  main.querySelectorAll('.mining-shop-save').forEach(b=>b.addEventListener('click',()=>{const k=b.dataset.kind;fcPost('miningShopSave',{npcId:miningNpc,kind:k,enabled:main.querySelector('.mining-shop-on[data-kind="'+k+'"]').value==='1',price:parseInt(main.querySelector('.mining-shop-price[data-kind="'+k+'"]').value,10)||0,qty:parseInt(main.querySelector('.mining-shop-qty[data-kind="'+k+'"]').value,10)||1});}));
  main.querySelectorAll('.mining-buy-save').forEach(b=>b.addEventListener('click',()=>{const k=b.dataset.key;fcPost('miningMineralSave',{npcId:miningNpc,key:k,enabled:main.querySelector('.mining-buy-on[data-key="'+k+'"]').value==='1',basePrice:parseInt(main.querySelector('.mining-buy-price[data-key="'+k+'"]').value,10)||0});}));
  const search=document.getElementById('miningBuySearch');if(search)search.addEventListener('input',()=>{const q=search.value.trim().toLowerCase();main.querySelectorAll('#miningBuyList .ck-fc-shoprow').forEach(r=>r.style.display=(!q||r.textContent.toLowerCase().includes(q))?'':'none');});
}

function renderNpcHailsOld() {
  const main = document.getElementById('npcMain');
  const title = document.getElementById('npcTitle');
  const sub = document.getElementById('npcSub');
  if (!main) return;

  title.textContent = '택시 좌표';
  sub.textContent = '손님이 나타날 자리(승차지)와 내릴 자리(하차지). 서 있는 그 자리로 잡힌다';

  if (!npcHails) {
    main.innerHTML = '<div class="ck-skin-empty">불러오는 중</div>';
    return;
  }

  const isDrop = hailKind === 'dropoff';
  const rows = (isDrop ? npcHails.dropoff : npcHails.pickup) || [];
  const fromDb = isDrop ? npcHails.dropoffFromDb : npcHails.pickupFromDb;
  const cfgN = isDrop ? npcHails.configDropoff : npcHails.configPickup;

  const tabs =
    '<div class="ck-veh-chips" style="margin-bottom:12px">' +
      '<button class="ck-chip' + (!isDrop ? ' active' : '') + '" data-hk="pickup">' +
        '승차지 ' + ((npcHails.pickup || []).length) + '</button>' +
      '<button class="ck-chip' + (isDrop ? ' active' : '') + '" data-hk="dropoff">' +
        '하차지 ' + ((npcHails.dropoff || []).length) + '</button>' +
    '</div>';

  const list = rows.length
    ? rows.map((r) =>
        '<div class="ck-fc-shoprow on">' +
          '<input type="text" class="ck-hail-name" data-id="' + r.id + '" ' +
            'value="' + escapeHtml(r.label) + '" maxlength="60">' +
          '<span class="ck-arm-group">' +
            r.x.toFixed(0) + ', ' + r.y.toFixed(0) + ', ' + r.z.toFixed(0) +
          '</span>' +
          '<button class="ck-fc-abtn ck-hail-save" data-id="' + r.id + '">이름 저장</button>' +
          '<button class="ck-fc-abtn ck-hail-move" data-id="' + r.id + '">여기로 옮기기</button>' +
          '<button class="ck-fc-abtn ck-hail-go" data-x="' + r.x + '" data-y="' + r.y +
            '" data-z="' + r.z + '">이동</button>' +
          '<button class="ck-fc-xbtn ck-hail-del" data-id="' + r.id + '">삭제</button>' +
        '</div>').join('')
    : '<div class="ck-skin-empty">찍은 좌표가 없습니다</div>';

  main.innerHTML =
    tabs +
    '<div class="ck-fc-card">' +
      '<p class="ck-fc-card-h">' +
        (fromDb
          ? ('DB ' + rows.length + '곳을 쓰는 중')
          : ('DB가 비어 있어 Config ' + (cfgN || 0) + '곳으로 굴러가는 중')) +
      '</p>' +
      '<div class="ck-fc-body-p">' +
        '<div class="ck-fc-fields">' +
          '<label>이름<input type="text" id="hailLabel" maxlength="60" ' +
            'placeholder="' + (isDrop ? '필박스 병원 앞' : '레전 스퀘어 동편') + '"></label>' +
        '</div>' +
        '<div class="ck-fc-btns">' +
          '<button id="hailAdd" class="ck-fc-btn primary">지금 서 있는 자리를 ' +
            (isDrop ? '하차지' : '승차지') + '로 추가</button>' +
        '</div>' +
      '</div>' +
    '</div>' +
    '<div class="ck-fc-card">' +
      '<p class="ck-fc-card-h">등록된 ' + (isDrop ? '하차지' : '승차지') + '</p>' +
      '<div class="ck-fc-body-p"><div class="ck-fc-lineup">' + list + '</div></div>' +
    '</div>' +
    '<div class="ck-fc-footer">' +
      '<button id="hailImport" class="ck-fc-btn">Config 좌표 가져오기 (승차 20 / 하차 20)</button>' +
    '</div>';

  main.querySelectorAll('[data-hk]').forEach((b) => b.addEventListener('click', () => {
    hailKind = b.dataset.hk;
    renderNpcHails();
  }));

  document.getElementById('hailAdd').addEventListener('click', () => {
    const l = document.getElementById('hailLabel');
    const label = l ? l.value.trim() : '';
    if (!label) { showToast('이름을 입력하세요', true); return; }
    fcPost('hailAdd', { label: label, kind: hailKind });
  });

  document.getElementById('hailImport').addEventListener('click', () => fcPost('hailImport', {}));

  main.querySelectorAll('.ck-hail-save').forEach((b) => b.addEventListener('click', () => {
    const id = parseInt(b.dataset.id, 10);
    const inp = main.querySelector('.ck-hail-name[data-id="' + id + '"]');
    const label = inp ? inp.value.trim() : '';
    if (!label) { showToast('이름을 입력하세요', true); return; }
    fcPost('hailRename', { id: id, label: label });
  }));

  main.querySelectorAll('.ck-hail-move').forEach((b) => b.addEventListener('click', () =>
    fcPost('hailMove', { id: parseInt(b.dataset.id, 10) })));

  main.querySelectorAll('.ck-hail-del').forEach((b) => b.addEventListener('click', () =>
    fcPost('hailDelete', { id: parseInt(b.dataset.id, 10) })));

  main.querySelectorAll('.ck-hail-go').forEach((b) => b.addEventListener('click', () => {
    fcPost('hailGoto', {
      x: parseFloat(b.dataset.x), y: parseFloat(b.dataset.y), z: parseFloat(b.dataset.z),
    });
    closeNpcConsole();
    closePanel();
  }));
}

function renderNpcMain() {
  const main = document.getElementById('npcMain');
  if (!main || !npcData) return;
  renderNpcNav();

  if (npcView === 'hail') { renderNpcHails(); return; }
  if (npcView === 'truck') { renderNpcTruck(); return; }
  if (npcView === 'labor') { renderNpcLabor(); return; }
  if (npcView === 'delivery') { renderNpcDelivery(); return; }
  if (npcView === 'mechanic') { renderNpcMechanic(); return; }
  if (npcView === 'fishing') { renderNpcFishing(); return; }
  if (npcView === 'mining') { renderNpcMining(); return; }

  const title = document.getElementById('npcTitle');
  const sub = document.getElementById('npcSub');

  if (npcView === 'list') {
    title.textContent = 'NPC 관리';
    sub.textContent = '';
    const rows = (npcData.rows || []).length
      ? (npcData.rows || []).map((r) =>
          '<div class="ck-fc-shoprow on">' +
            '<span class="ck-fc-lname">' + escapeHtml(r.label) +
              '<span class="ck-arm-group">' + escapeHtml(r.model) +
                (r.job_key ? ' — ' + escapeHtml(npcJobLabel(r.job_key)) : '') + '</span></span>' +
            '<button class="ck-fc-abtn ck-npc-edit" data-id="' + r.id + '">편집</button>' +
            '<button class="ck-fc-abtn ck-npc-go" data-x="' + r.x + '" data-y="' + r.y +
              '" data-z="' + r.z + '">순간이동</button>' +
            '<button class="ck-fc-xbtn ck-npc-del" data-id="' + r.id + '">제거</button>' +
          '</div>').join('')
      : '<div class="ck-skin-empty">배치된 NPC가 없습니다</div>';

    main.innerHTML =
      '<div class="ck-fc-card">' +
        '<p class="ck-fc-card-h">상호작용 테스트 시민</p>' +
        '<div class="ck-fc-body-p"><p style="font-size:11px;color:#8a96a8;margin:0 0 10px">CAPSLOCK 거래·고백 UI를 혼자 테스트하는 임시 NPC입니다.</p><div class="ck-fc-btns"><button id="interactionTestNpcSpawn" class="ck-fc-btn primary">테스트 시민 소환</button><button id="interactionTestNpcDelete" class="ck-fc-btn">테스트 시민 삭제</button></div></div>' +
      '</div>' +
      '<div class="ck-fc-card">' +
        '<p class="ck-fc-card-h">배치된 NPC</p>' +
        '<div class="ck-fc-body-p"><div class="ck-fc-lineup">' + rows + '</div></div>' +
      '</div>';

    document.getElementById('interactionTestNpcSpawn')?.addEventListener('click', () => fcPost('interactionTestNpcSpawn', {}));
    document.getElementById('interactionTestNpcDelete')?.addEventListener('click', () => fcPost('interactionTestNpcDelete', {}));

    main.querySelectorAll('.ck-npc-edit').forEach((b) => b.addEventListener('click', () => {
      npcView = parseInt(b.dataset.id, 10);
      npcDraft = null;
      renderNpcMain();
    }));

    main.querySelectorAll('.ck-npc-go').forEach((b) => b.addEventListener('click', () => {
      fcPost('npcGoto', { x: parseFloat(b.dataset.x), y: parseFloat(b.dataset.y), z: parseFloat(b.dataset.z) });
      closeNpcConsole();
      closePanel();
    }));
    main.querySelectorAll('.ck-npc-del').forEach((b) => b.addEventListener('click', () =>
      fcPost('npcDelete', { id: parseInt(b.dataset.id, 10) })));
    return;
  }

  if (!npcDraft) {
    if (npcView === 'new') {
      npcDraft = npcNewDraft();
    } else {
      const r = (npcData.rows || []).find((x) => x.id === npcView);
      if (!r) { npcView = 'list'; renderNpcMain(); return; }
      let comps = [];
      try { comps = r.components ? JSON.parse(r.components) : []; } catch (err) { comps = []; }
      npcDraft = {
        id: r.id, label: r.label, model: r.model, scenario: r.scenario || '',
        components: comps, x: r.x, y: r.y, z: r.z, heading: r.heading,
        job_key: r.job_key || '',
      };
    }
  }

  const placed = npcDraft.x != null;
  title.textContent = (npcView === 'new') ? '새 NPC 배치' : npcDraft.label;
  sub.textContent = placed
    ? ('좌표 ' + npcDraft.x.toFixed(1) + ', ' + npcDraft.y.toFixed(1) + ', ' + npcDraft.z.toFixed(1) +
       '  방향 ' + Math.round(npcDraft.heading) + '°')
    : '';

  const summary = placed
    ? '<div class="ck-npc-sum">' +
        '<div><span>모델</span><b>' + escapeHtml(npcDraft.model) + '</b></div>' +
        '<div><span>자세</span><b>' + escapeHtml(npcScenarioLabel(npcDraft.scenario)) + '</b></div>' +
        '<div><span>의상</span><b>' + ((npcDraft.components || []).length
            ? ((npcDraft.components || []).length + '부위 변경') : '기본') + '</b></div>' +
        '<div><span>방향</span><b>' + Math.round(npcDraft.heading) + '°</b></div>' +
        '<div><span>직업</span><b>' + escapeHtml(npcJobLabel(npcDraft.job_key)) + '</b></div>' +
      '</div>'
    : '';

  main.innerHTML =
    '<div class="ck-fc-card">' +
      '<p class="ck-fc-card-h">기본</p>' +
      '<div class="ck-fc-body-p">' +
        '<div class="ck-fc-fields">' +
          '<label>NPC 이름<input type="text" id="npcLabel" value="' + escapeHtml(npcDraft.label) +
            '" maxlength="60" placeholder="시청 민원 담당"></label>' +
          '<label>직업<select id="npcJob">' + npcJobOptions(npcDraft.job_key) + '</select></label>' +
        '</div>' +
        summary +
        '<div class="ck-fc-btns">' +
          '<button id="npcPlace" class="ck-fc-btn primary">' +
            (placed ? '편집 모드로 다시 잡기' : '편집 모드 시작') + '</button>' +
        '</div>' +
      '</div>' +
    '</div>' +
    '<div class="ck-fc-footer">' +
      (npcView === 'new' ? '' :
        '<button id="npcDel" class="ck-fc-delbtn">NPC 제거</button>') +
      '<button id="npcSave" class="ck-fc-btn primary"' + (placed ? '' : ' disabled') + '>' +
        (placed ? '저장' : '먼저 편집 모드에서 배치하세요') + '</button>' +
    '</div>';

  const place = document.getElementById('npcPlace');
  place.addEventListener('click', () => {
    npcCollect();
    if (!npcDraft.label) { showToast('NPC 이름을 입력하세요', true); return; }

    document.getElementById('npcConsole').classList.add('hidden');
    document.getElementById('npcEditBar').classList.remove('hidden');
    overlay.classList.add('npc-edit');

    fcPost('npcEditStart', {
      id: npcDraft.id,
      label: npcDraft.label,
      model: npcDraft.model,
      scenario: npcDraft.scenario,
      components: npcDraft.components,
      heading: npcDraft.heading,

      x: npcDraft.x, y: npcDraft.y, z: npcDraft.z,
    });
  });

  const save = document.getElementById('npcSave');
  if (save && placed) save.addEventListener('click', () => {
    npcCollect();
    fcPost('npcSave', npcDraft);
    npcDraft = null;
    npcView = 'list';
  });

  const del = document.getElementById('npcDel');
  if (del) del.addEventListener('click', () => {
    fcPost('npcDelete', { id: npcDraft.id });
    npcDraft = null;
    npcView = 'list';
  });
}

document.getElementById('npcClose').addEventListener('click', () => {
  closeNpcConsole();
  npcView = 'list';
  npcDraft = null;
});

function setRightPane(pane) {

  if (pane === 'npcs') { openNpcConsole(); return; }

  if (pane === 'factions') { openFactionConsole(); return; }

  document.querySelectorAll('#rightTabs .ck-rtab').forEach((t) =>
    t.classList.toggle('active', t.dataset.pane === pane));
  const pDs = document.getElementById('paneDash');
  if (pDs) pDs.classList.toggle('hidden', pane !== 'dash');
  document.getElementById('paneMPlayers').classList.toggle('hidden', pane !== 'players');
  document.getElementById('paneZones').classList.toggle('hidden', pane !== 'zones');
  document.getElementById('paneBeacons').classList.toggle('hidden', pane !== 'beacons');

  const pVs = document.getElementById('paneVehSpawn');
  const pVe = document.getElementById('paneVehExhibit');
  if (pVs) pVs.classList.toggle('hidden', pane !== 'vehspawn');
  if (pVe) pVe.classList.toggle('hidden', pane !== 'vehexhibit');
  const pFa = document.getElementById('paneFactions');
  if (pFa) pFa.classList.toggle('hidden', pane !== 'factions');
  const pLg = document.getElementById('paneLogs');
  if (pLg) pLg.classList.toggle('hidden', pane !== 'logs');
  const pSy = document.getElementById('paneSystems');
  if (pSy) pSy.classList.toggle('hidden', pane !== 'systems');
  if (pane !== 'systems' && typeof closeSystemWindows === 'function') closeSystemWindows();
  const pNw = document.getElementById('paneNews');
  if (pNw) pNw.classList.toggle('hidden', pane !== 'news');
  if (pane === 'news') {
    fetch('https://cookie_admin/requestNews', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
    }).catch(() => {});
  }
  if (pane !== 'vehspawn') exitPreviewUi();
  if (pane === 'zones' || pane === 'beacons') {
    fetch('https://cookie_admin/requestZoneList', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
    }).catch(() => {});
    if (pane === 'beacons') { requestConvenienceAdmin(); requestJobShopAdmin(); }
  } else if (pane === 'vehspawn') {
    renderVehTargetOptions();
    renderVehList();
  } else if (pane === 'vehexhibit') {
    renderExhibitTabs();
    renderExhibitCurrentList();
    fetch('https://cookie_admin/requestExhibitList', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
    }).catch(() => {});
  } else if (pane === 'factions') {
    fetch('https://cookie_admin/requestFactionList', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
    }).catch(() => {});
  } else if (pane === 'logs') {
    renderLogsShell();
    requestLogs(logKind);
  }
}

let logKind = 'faction_budget';

const LOG_TABS = [
  { key: 'faction_budget', label: '팩션 예산 로그' },
  { key: 'chat_mod', label: '채팅 관리 기록' },
  { key: 'trade', label: '플레이어 거래 로그' },
  { key: 'transfer', label: '플레이어 이체 로그' },
  { key: 'suggestion', label: '건의함' },
];

let logRows = [];
let logSearch = '';

function requestLogs(kind) {
  fetch('https://cookie_admin/requestLogs', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ kind: kind }),
  }).catch(() => {});
}

function renderLogsShell() {
  const el = document.getElementById('paneLogs');
  if (!el) return;
  const tabs = LOG_TABS.map((t) =>
    '<button class="ck-logtab' + (t.key === logKind ? ' active' : '') + (t.soon ? ' soon' : '') + '" ' +
    'data-lk="' + t.key + '"' + (t.soon ? ' disabled' : '') + '>' + escapeHtml(t.label) +
    (t.soon ? '<span class="ck-log-soon">준비 중</span>' : '') + '</button>').join('');

  el.innerHTML =
    '<div class="ck-logtabs">' + tabs + '</div>' +
    '<div class="ck-logtools">' +
      '<input id="logSearch" type="text" maxlength="60" placeholder="고번·닉네임·전화번호·메모·아이템 검색" value="' + escapeHtml(logSearch) + '">' +
      '<button id="logRefresh" type="button">새로고침</button>' +
    '</div>' +
    '<div id="logBody"><div class="ck-skin-empty">불러오는 중…</div></div>';

  el.querySelectorAll('.ck-logtab[data-lk]:not(.soon)').forEach((b) =>
    b.addEventListener('click', () => {
      logKind = b.dataset.lk;
      logSearch = '';
      renderLogsShell();
      requestLogs(logKind);
    }));

  const search = document.getElementById('logSearch');
  if (search) {
    search.addEventListener('input', () => {
      logSearch = search.value || '';
      renderLogs(logKind, logRows);
    });
  }
  const refresh = document.getElementById('logRefresh');
  if (refresh) refresh.addEventListener('click', () => requestLogs(logKind));
}

const CHATMOD_LABEL = {
  notice: '공지',
  warn: '경고 발급',
  warn_revoke: '경고 회수',
  mute: '입막음',
  unmute: '입막음 해제',
  kick: '킥',
  ban: '밴',
};

function renderChatModLogs(rows, body) {
  body.innerHTML =
    '<table class="ck-logtable"><thead><tr>' +
      '<th>시간</th><th>구분</th><th>관리자</th><th>대상</th><th>사유</th><th class="r">기간</th>' +
    '</tr></thead><tbody>' +
    rows.map((r) => {
      const danger = (r.action === 'warn' || r.action === 'mute');
      const target = r.target_gobun
        ? (escapeHtml(r.target_nick || '-') + ' [' + r.target_gobun + ']')
        : '전체';
      return '<tr>' +
        '<td>' + fmtDate(r.created_at) + '</td>' +
        '<td class="' + (danger ? 'ck-neg' : '') + '">' +
          escapeHtml(CHATMOD_LABEL[r.action] || r.action || '-') + '</td>' +
        '<td>' + escapeHtml(r.admin_name || '-') + '</td>' +
        '<td>' + target + '</td>' +
        '<td>' + escapeHtml(r.reason || '-') + '</td>' +
        '<td class="r">' + (r.minutes ? (r.minutes + '분') : '-') + '</td>' +
      '</tr>';
    }).join('') +
    '</tbody></table>';
}

function logPerson(name, gobun, phone, faction) {
  let out = escapeHtml(name || '-');
  if (gobun) out += ' [' + escapeHtml(gobun) + ']';
  if (phone) out += '<br><span class="ck-log-sub">' + escapeHtml(phone) + '</span>';
  if (faction) out += '<br><span class="ck-log-sub">' + escapeHtml(faction) + '</span>';
  return out;
}

function tradeOfferSummary(raw) {
  let arr = raw;
  if (typeof arr === 'string') {
    try { arr = JSON.parse(arr); } catch (_) { arr = []; }
  }
  if (!Array.isArray(arr) || !arr.length) return '없음';

  return arr.map((r) => {
    if (!r || typeof r !== 'object') return '-';
    if (r.type === 'money') {
      const kind = r.moneyType === 'cash' ? '현금' : '계좌';
      return kind + ' ' + fmtWon(r.amount || 0);
    }
    if (r.type === 'item') {
      const label = r.label || r.name || '아이템';
      return escapeHtml(label) + (r.label ? '' : (' x' + (r.count || 1)));
    }
    if (r.type === 'vehicle') return '차량 · ' + escapeHtml(r.label || r.assetUid || '-');
    if (r.type === 'title') return '칭호 · ' + escapeHtml(r.label || '-');
    if (r.type === 'asset') return escapeHtml(r.label || r.assetType || '자산');
    return escapeHtml(r.label || r.name || r.type || '-');
  }).join('<br>');
}

function rowSearchText(kind, r) {
  if (!r) return '';
  if (kind === 'trade') {
    return [
      r.trade_id, r.a_gobun, r.a_name, r.a_faction, r.a_offer,
      r.b_gobun, r.b_name, r.b_faction, r.b_offer, r.status
    ].join(' ').toLowerCase();
  }
  if (kind === 'transfer') {
    return [
      r.sender_gobun, r.sender_name, r.sender_phone,
      r.receiver_gobun, r.receiver_name, r.receiver_phone,
      r.amount, r.memo, r.transfer_mode
    ].join(' ').toLowerCase();
  }
  if (kind === 'suggestion') {
    return [r.gobun,r.nickname,r.category,r.title,r.body,r.status].join(' ').toLowerCase();
  }
  return JSON.stringify(r).toLowerCase();
}

function renderTradeLogs(rows, body) {
  body.innerHTML =
    '<table class="ck-logtable"><thead><tr>' +
      '<th>시간</th><th>거래자 A</th><th>A 제공</th><th>거래자 B</th><th>B 제공</th><th>상태</th>' +
    '</tr></thead><tbody>' +
    rows.map((r) => '<tr>' +
      '<td>' + fmtDate(r.created_at) + '</td>' +
      '<td>' + logPerson(r.a_name, r.a_gobun, null, r.a_faction) + '</td>' +
      '<td class="ck-log-offer">' + tradeOfferSummary(r.a_offer) + '</td>' +
      '<td>' + logPerson(r.b_name, r.b_gobun, null, r.b_faction) + '</td>' +
      '<td class="ck-log-offer">' + tradeOfferSummary(r.b_offer) + '</td>' +
      '<td>' + escapeHtml(r.status || '-') + '</td>' +
    '</tr>').join('') +
    '</tbody></table>';
}

function renderTransferLogs(rows, body) {
  body.innerHTML =
    '<table class="ck-logtable"><thead><tr>' +
      '<th>시간</th><th>보낸 사람</th><th>받는 사람</th><th>메모</th><th>방식</th><th class="r">금액</th>' +
    '</tr></thead><tbody>' +
    rows.map((r) => '<tr>' +
      '<td>' + fmtDate(r.created_at) + '</td>' +
      '<td>' + logPerson(r.sender_name, r.sender_gobun, r.sender_phone) + '</td>' +
      '<td>' + logPerson(r.receiver_name, r.receiver_gobun, r.receiver_phone) + '</td>' +
      '<td>' + escapeHtml(r.memo || '-') + '</td>' +
      '<td>' + escapeHtml(r.transfer_mode || 'phone') + '</td>' +
      '<td class="r ck-neg">' + fmtWon(r.amount || 0) + '</td>' +
    '</tr>').join('') +
    '</tbody></table>';
}


function renderSuggestionLogs(rows, body) {
  const CAT={general:'일반 건의',bug:'버그 제보',other:'기타'};
  body.innerHTML='<div class="ck-suggestion-list">'+rows.map(r=>`
    <article class="ck-suggestion-card">
      <div class="ck-suggestion-top"><span>${fmtDate(r.created_at)}</span><b>${escapeHtml(CAT[r.category]||r.category||'건의')}</b><em>${escapeHtml(r.nickname||'-')} ${r.gobun?'['+escapeHtml(r.gobun)+']':''}</em></div>
      <h4>${escapeHtml(r.title||'-')}</h4>
      <p>${escapeHtml(r.body||'').replace(/\n/g,'<br>')}</p>
    </article>`).join('')+'</div>';
}

function renderLogs(kind, rows) {
  logRows = Array.isArray(rows) ? rows : [];
  const body = document.getElementById('logBody');
  if (!body) return;

  let visibleRows = logRows;
  const q = String(logSearch || '').trim().toLowerCase();
  if (q) visibleRows = logRows.filter((r) => rowSearchText(kind, r).includes(q));

  if (!visibleRows.length) {
    body.innerHTML = '<div class="ck-skin-empty">' + (q ? '검색 결과가 없습니다' : '기록이 없습니다') + '</div>';
    return;
  }

  if (kind === 'chat_mod') { renderChatModLogs(visibleRows, body); return; }
  if (kind === 'trade') { renderTradeLogs(visibleRows, body); return; }
  if (kind === 'transfer') { renderTransferLogs(visibleRows, body); return; }
  if (kind === 'suggestion') { renderSuggestionLogs(visibleRows, body); return; }

  body.innerHTML =
    '<table class="ck-logtable"><thead><tr>' +
      '<th>시간</th><th>팩션</th><th>구분</th><th>실행자</th><th>사유</th><th class="r">변동</th><th class="r">잔액</th>' +
    '</tr></thead><tbody>' +
    visibleRows.map((r) => {
      const pos = Number(r.delta) >= 0;
      return '<tr>' +
        '<td>' + fmtDate(r.created_at) + '</td>' +
        '<td>' + escapeHtml(r.faction || '-') + '</td>' +
        '<td>' + escapeHtml(LOG_CAT[r.category] || r.category || '-') + '</td>' +
        '<td>' + escapeHtml(r.actor || '-') + '</td>' +
        '<td>' + escapeHtml((r.reason || '-').replace(/^\[관리자\]\s*/, '')) + '</td>' +
        '<td class="r ' + (pos ? 'ck-pos' : 'ck-neg') + '">' +
          (pos ? '+' : '−') + fmtWon(Math.abs(Number(r.delta) || 0)) + '</td>' +
        '<td class="r">' + fmtWon(r.balance_after) + '</td>' +
      '</tr>';
    }).join('') +
    '</tbody></table>';
}

const LOG_CAT = {
  deposit: '입금', withdraw: '출금', purchase: '차량 구매',
  fine_income: '벌금 수입', admin_add: '관리자 추가', admin_take: '관리자 회수',
};
document.querySelectorAll('#rightTabs .ck-rtab').forEach((t) => {
  t.addEventListener('click', () => setRightPane(t.dataset.pane));
});

const fcCloseBtn = document.getElementById('fcClose');
if (fcCloseBtn) fcCloseBtn.addEventListener('click', closeFactionConsole);

const fbOkBtn = document.getElementById('fbOk');
const fbCancelBtn = document.getElementById('fbCancel');
if (fbOkBtn) fbOkBtn.addEventListener('click', submitBudgetDialog);
if (fbCancelBtn) fbCancelBtn.addEventListener('click', closeBudgetDialog);

document.querySelectorAll('.ck-toss-chip').forEach((c) => {
  c.addEventListener('click', () => {
    const inp = document.getElementById('fbAmt');
    const add = parseInt(c.dataset.add, 10) || 0;
    if (add === 0) { inp.value = ''; return; }
    inp.value = String((parseInt(inp.value, 10) || 0) + add);
  });
});

const fbAmtInput = document.getElementById('fbAmt');
if (fbAmtInput) {
  fbAmtInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') submitBudgetDialog();
  });
}

const baOkBtn = document.getElementById('baOk');
const baCancelBtn = document.getElementById('baCancel');
if (baOkBtn) baOkBtn.addEventListener('click', submitBudgetAdjust);
if (baCancelBtn) baCancelBtn.addEventListener('click', closeBudgetAdjust);

const facPrevCloseBtn = document.getElementById('facPrevClose');
if (facPrevCloseBtn) facPrevCloseBtn.addEventListener('click', exitPreviewUi);

const fmemCloseBtn = document.getElementById('fmemClose');
if (fmemCloseBtn) fmemCloseBtn.addEventListener('click', closeMembersDialog);

let aliasTarget = null;

function openAliasModal(serverId, playerName, currentAlias) {
  aliasTarget = serverId;
  document.getElementById('aaSub').textContent = '대상의 관리자 별명을 변경합니다';
  document.getElementById('aaTarget').textContent =
    '[' + serverId + '] ' + (playerName || '-') + (currentAlias ? (' (현재 ' + currentAlias + ')') : '');
  document.getElementById('aaName').value = currentAlias || '';
  document.getElementById('aaModal').classList.remove('hidden');
  document.getElementById('aaName').focus();
}

function closeAliasModal() {
  document.getElementById('aaModal').classList.add('hidden');
  aliasTarget = null;
}

const aaOkBtn = document.getElementById('aaOk');
const aaCancelBtn = document.getElementById('aaCancel');
if (aaCancelBtn) aaCancelBtn.addEventListener('click', closeAliasModal);
if (aaOkBtn) {
  aaOkBtn.addEventListener('click', () => {
    if (aliasTarget == null) return;
    const nm = document.getElementById('aaName').value.trim();
    if (nm.length < 2) { showToast('별명은 2자 이상이어야 합니다', true); return; }
    fetch('https://cookie_admin/setAdminAlias', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ targetServerId: aliasTarget, name: nm }),
    }).catch(() => {});
    closeAliasModal();
  });
}

const vehShotBtn = document.getElementById('vehShotBtn');
if (vehShotBtn) {
  vehShotBtn.addEventListener('click', () => {
    if (!currentPreviewModel) { showToast('미리보기 중인 차량이 없습니다', true); return; }
    showToast('썸네일 저장 중…', false);
    fetch('https://cookie_admin/captureVehImage', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: currentPreviewModel }),
    }).catch(() => {});
  });
}

const vrOkBtn = document.getElementById('vrOk');
const vrCancelBtn = document.getElementById('vrCancel');
const vrPriceInput = document.getElementById('vrPrice');
const vrDelBtn = document.getElementById('vrDel');
if (vrOkBtn) vrOkBtn.addEventListener('click', submitVehRegister);
if (vrCancelBtn) vrCancelBtn.addEventListener('click', closeVehRegisterDialog);
if (vrDelBtn) {

  vrDelBtn.addEventListener('click', () => {
    if (!vrModel) return;
    const exist = garageShop[vrModel.model];
    if (!exist) return;
    fetch('https://cookie_admin/factionShopDelete', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: exist.id }),
    }).catch(() => {});
    closeVehRegisterDialog();
  });
}
if (vrPriceInput) {
  vrPriceInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') submitVehRegister();
  });
}

const mfCloseBtn = document.getElementById('mfClose');
if (mfCloseBtn) mfCloseBtn.addEventListener('click', closeMyFaction);

const fmOkBtn = document.getElementById('fmOk');
if (fmOkBtn) {
  fmOkBtn.addEventListener('click', () => {
    if (!fmCid) return;
    fcPost('facMemberSave', {
      citizenid: fmCid,
      grade: parseInt(document.getElementById('fmGrade').value, 10),
      department: document.getElementById('fmDep').value,
    });
    closeMemberDialog();
  });
}
const fmKickBtn = document.getElementById('fmKick');
if (fmKickBtn) {
  fmKickBtn.addEventListener('click', () => {
    if (!fmCid) return;
    fcPost('facMemberKick', { citizenid: fmCid });
    closeMemberDialog();
  });
}
const fmCancelBtn = document.getElementById('fmCancel');
if (fmCancelBtn) fmCancelBtn.addEventListener('click', closeMemberDialog);

const frOkBtn = document.getElementById('frOk');
if (frOkBtn) {
  frOkBtn.addEventListener('click', () => {
    const grade = parseInt(document.getElementById('frGrade').value, 10);
    const name = document.getElementById('frName').value.trim();
    if (isNaN(grade) || grade < 0) { showToast('계급 번호를 입력하세요', true); return; }
    if (name.length < 1) { showToast('계급명을 입력하세요', true); return; }
    fcPost('facRankSave', {
      grade: grade,
      oldGrade: frEditing ? frEditing.grade : null,
      name: name,
      salary: parseInt(document.getElementById('frSalary').value, 10) || 0,
      isOfficer: document.getElementById('frOfficer').checked,
      isLeader: document.getElementById('frLeader').checked,
    });
    closeRankDialog();
  });
}
const frDelBtn = document.getElementById('frDel');
if (frDelBtn) {
  frDelBtn.addEventListener('click', () => {
    if (!frEditing) return;
    fcPost('facRankDelete', { grade: frEditing.grade });
    closeRankDialog();
  });
}
const frCancelBtn = document.getElementById('frCancel');
if (frCancelBtn) frCancelBtn.addEventListener('click', closeRankDialog);

let activeTab = 0;
let activeTarget = null;
let targetVehicleAction = null;
let targetVehicleTarget = null;

function openTargetModal(player) {
  activeTarget = player;
  activeTab = 0;

  const rn = (player.realname || '').trim();
  document.getElementById('modalName').textContent = player.onboarded
    ? player.nickname
    : (rn || player.name || ('#' + player.serverId)) + ' (미온보딩)';
  const dl = player.driverLicense || null;
  document.getElementById('modalSub').textContent =
    '[' + player.serverId + '] ' + (player.citizenid || '-') +
    (dl ? (' · 면허 ' + (dl.licenseNo || '-') + ' · ' + (dl.suspended ? '정지' : '정상')) : ' · 면허 -');
  renderTabs();
  hideLevelChange();
  document.getElementById('targetModal').classList.remove('hidden');
}

const LVCHG_CATEGORY = 'onboarding';

function levelLabel(lv) {
  return lv === 0 ? '관리자 아님' : 'LV' + lv;
}

function hideLevelChange() {
  document.getElementById('lvChange').classList.add('hidden');
}

function openLevelChange() {
  if (!activeTarget || myEffectiveLevel < 5) return;
  const cur = activeTarget.adminLevel || 0;
  document.getElementById('lvChangeCur').textContent = '현재: ' + levelLabel(cur);
  document.getElementById('lvChangeSelect').value = String(cur);
  document.getElementById('lvChangeApply').disabled = true;
  document.getElementById('lvChange').classList.remove('hidden');
}

document.getElementById('lvChangeSelect').addEventListener('change', (e) => {
  const cur = (activeTarget && activeTarget.adminLevel) || 0;
  document.getElementById('lvChangeApply').disabled = (Number(e.target.value) === cur);
});

document.getElementById('lvChangeApply').addEventListener('click', () => {
  if (!activeTarget) return;
  const level = Number(document.getElementById('lvChangeSelect').value);
  fetch('https://cookie_admin/changeAdminLevel', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },

    body: JSON.stringify({ targetServerId: activeTarget.serverId, level: level }),
  }).catch(() => {});

  closeTargetModal();
});

function closeTargetModal() {
  document.getElementById('targetModal').classList.add('hidden');
  activeTarget = null;
}

const CHATMOD_MIN_LEVEL = 2;

let cmAction = null;
let cmMinutes = 10;
let cmBanMinutes = 10080;

const CM_TITLE = {
  warn: '경고 발급',
  warn_revoke: '경고 회수',
  mute: '입막음',
  unmute: '입막음 해제',
  faction_warn: '팩션 경고 부여',
  faction_remove: '팩션직 제거',
  jail: '관리자 구금',
  license_suspend: '운전면허 정지',
  license_restore: '운전면허 정지 해제',
};

const CM_GROUP = {
  warn: [
    { key: 'warn', label: '경고 발급' },
    { key: 'warn_revoke', label: '경고 회수' },
  ],
  mute: [
    { key: 'mute', label: '입막음' },
    { key: 'unmute', label: '입막음 해제' },
  ],
  kick: [
    { key: 'kick', label: '킥' },
  ],
  ban: [
    { key: 'ban', label: '밴' },
  ],
  jail: [
    { key: 'jail', label: '관리자 구금' },
  ],
  license_suspend: [
    { key: 'license_suspend', label: '운전면허 정지' },
  ],
  license_restore: [
    { key: 'license_restore', label: '운전면허 정지 해제' },
  ],
  faction_warn: [
    { key: 'faction_warn', label: '팩션 경고 부여' },
  ],
  faction_remove: [
    { key: 'faction_remove', label: '팩션직 제거' },
  ],
};

function cmApplyAction(action) {
  cmAction = action;
  document.getElementById('reasonTitle').textContent = CM_TITLE[action] || '조치';

  document.getElementById('reasonMinRow').classList.toggle(
    'hidden',
    action !== 'mute' && action !== 'jail' && action !== 'license_suspend'
  );
  document.getElementById('reasonBanRow').classList.toggle('hidden', action !== 'ban');
  document.querySelectorAll('#reasonSeg .ck-seg-btn').forEach((b) =>
    b.classList.toggle('active', b.dataset.act === action));
}

function openReasonModal(group) {
  if (!activeTarget) return;
  cmMinutes = 10;
  cmBanMinutes = 10080;

  const seg = document.getElementById('reasonSeg');
  seg.innerHTML = '';
  (CM_GROUP[group] || []).forEach((g) => {
    const b = document.createElement('button');
    b.className = 'ck-seg-btn';
    b.dataset.act = g.key;
    b.textContent = g.label;
    b.addEventListener('click', () => cmApplyAction(g.key));
    seg.appendChild(b);
  });

  document.getElementById('reasonSub').textContent =
    (activeTarget.nickname || activeTarget.name || '-') + ' [' + activeTarget.serverId + ']';

  const t = document.getElementById('reasonText');
  t.value = '';
  document.getElementById('reasonSubmit').disabled = true;

  document.querySelectorAll('#reasonMins .ck-min-btn').forEach((b) =>
    b.classList.toggle('active', Number(b.dataset.min) === 10));
  document.querySelectorAll('#reasonBanMins .ck-min-btn').forEach((b) =>
    b.classList.toggle('active', Number(b.dataset.min) === 10080));

  cmApplyAction(group);

  document.getElementById('reasonModal').classList.remove('hidden');
  setTimeout(() => t.focus(), 50);
}

function closeReasonModal() {
  document.getElementById('reasonModal').classList.add('hidden');
  cmAction = null;
}

document.getElementById('reasonClose').addEventListener('click', closeReasonModal);

document.getElementById('reasonText').addEventListener('input', (e) => {
  document.getElementById('reasonSubmit').disabled = e.target.value.trim().length < 2;
});

document.querySelectorAll('#reasonMins .ck-min-btn').forEach((b) => {
  b.addEventListener('click', () => {
    cmMinutes = Number(b.dataset.min) || 10;
    document.querySelectorAll('#reasonMins .ck-min-btn').forEach((x) =>
      x.classList.toggle('active', x === b));
  });
});

document.querySelectorAll('#reasonBanMins .ck-min-btn').forEach((b) => {
  b.addEventListener('click', () => {
    cmBanMinutes = Number(b.dataset.min);
    if (!Number.isFinite(cmBanMinutes)) cmBanMinutes = 10080;
    document.querySelectorAll('#reasonBanMins .ck-min-btn').forEach((x) =>
      x.classList.toggle('active', x === b));
  });
});

document.getElementById('reasonSubmit').addEventListener('click', () => {
  if (!activeTarget || !cmAction) return;
  const reason = document.getElementById('reasonText').value.trim();
  if (reason.length < 2) return;

  const body = { targetServerId: activeTarget.serverId, reason: reason };
  let url;

  if (cmAction === 'warn' || cmAction === 'warn_revoke') {
    url = 'chatWarn';
    body.revoke = (cmAction === 'warn_revoke');
  } else if (cmAction === 'mute' || cmAction === 'unmute') {
    url = 'chatMute';
    body.unmute = (cmAction === 'unmute');
    body.minutes = cmMinutes;
  } else if (cmAction === 'kick' || cmAction === 'ban') {
    url = 'punishPlayer';
    body.action = cmAction;
    if (cmAction === 'ban') body.minutes = cmBanMinutes;
  } else if (cmAction === 'jail') {
    url = 'adminJail';
    body.minutes = cmMinutes;
  } else if (cmAction === 'license_suspend' || cmAction === 'license_restore') {
    url = 'driverLicenseAction';
    body.action = cmAction === 'license_suspend' ? 'suspend' : 'restore';
    if (cmAction === 'license_suspend') body.minutes = cmMinutes;
  } else if (cmAction === 'faction_warn' || cmAction === 'faction_remove') {
    url = 'factionPlayerAction';
    body.action = (cmAction === 'faction_warn') ? 'warn' : 'remove';
  } else {
    return;
  }

  fetch('https://cookie_admin/' + url, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  }).catch(() => {});

  closeReasonModal();
  closeTargetModal();
});

let newsKind = 'update';
let newsData = [];

function newsPost(url, body) {
  fetch('https://cookie_admin/' + url, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body || {}),
  }).catch(() => {});
}

function setNewsKind(k) {
  newsKind = k;
  document.querySelectorAll('#newsKind .ck-seg-btn').forEach((b) =>
    b.classList.toggle('active', b.dataset.nk === k));
  document.getElementById('newsFormUpdate').classList.toggle('hidden', k !== 'update');
  document.getElementById('newsFormBanner').classList.toggle('hidden', k !== 'banner');
  renderNewsList();
}

document.querySelectorAll('#newsKind .ck-seg-btn').forEach((b) => {
  b.addEventListener('click', () => setNewsKind(b.dataset.nk));
});

function newsImgSrc(v) {
  if (!v) return '';
  if (/^data:/i.test(v)) return v;
  if (/^https?:\/\//i.test(v)) return v;
  return 'nui://cookie_esc/nui/' + v.replace(/^\/+/, '');
}

const nfImage = document.getElementById('nfImage');
if (nfImage) {
  nfImage.addEventListener('input', () => {
    const p = document.getElementById('nfPreview');
    const v = nfImage.value.trim();
    if (!v) { p.classList.add('hidden'); return; }
    p.onerror = () => p.classList.add('hidden');
    p.onload = () => p.classList.remove('hidden');
    p.src = newsImgSrc(v);
  });
}

const NEWS_IMG_MAX_W = 800;
const NEWS_IMG_QUALITY = 0.82;

function shrinkImage(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error('파일을 읽지 못했습니다'));
    reader.onload = () => {
      const img = new Image();
      img.onerror = () => reject(new Error('이미지 형식이 아닙니다'));
      img.onload = () => {
        const scale = Math.min(1, NEWS_IMG_MAX_W / img.width);
        const w = Math.round(img.width * scale);
        const h = Math.round(img.height * scale);

        const cv = document.createElement('canvas');
        cv.width = w; cv.height = h;
        cv.getContext('2d').drawImage(img, 0, 0, w, h);

        const type = /png$/i.test(file.type) ? 'image/png' : 'image/jpeg';
        resolve(cv.toDataURL(type, NEWS_IMG_QUALITY));
      };
      img.src = reader.result;
    };
    reader.readAsDataURL(file);
  });
}

const nfPick = document.getElementById('nfPick');
const nfFile = document.getElementById('nfFile');

if (nfPick && nfFile) {
  nfPick.addEventListener('click', () => nfFile.click());

  nfFile.addEventListener('change', () => {
    const f = nfFile.files && nfFile.files[0];
    if (!f) return;

    shrinkImage(f).then((dataUri) => {
      const p = document.getElementById('nfPreview');
      p.src = dataUri;
      p.classList.remove('hidden');

      nfImage.value = '';
      nfImage.dataset.upload = dataUri;

      const kb = Math.round(dataUri.length * 0.75 / 1024);
      showToast('이미지를 불러왔습니다 (약 ' + kb + 'KB)', false);
    }).catch((e) => {
      showToast(e.message || '이미지를 불러오지 못했습니다', true);
    });

    nfFile.value = '';
  });
}

let newsEditId = 0;

function newsSetEditMode(n) {
  newsEditId = n ? Number(n.id) : 0;

  const addBtn = document.getElementById('newsAdd');
  const cancelBtn = document.getElementById('newsCancel');

  if (!n) {
    addBtn.textContent = '등록';
    cancelBtn.classList.add('hidden');
    document.getElementById('nfTitle').value = '';
    document.getElementById('nfBody').value = '';
    document.getElementById('nfBadge').value = '패치노트';
    nfImage.value = '';
    delete nfImage.dataset.upload;
    document.getElementById('nfPreview').classList.add('hidden');
    return;
  }

  addBtn.textContent = '수정';
  cancelBtn.classList.remove('hidden');

  if (n.kind === 'banner') {
    setNewsKind('banner');
    const p = document.getElementById('nfPreview');

    if (/^data:/i.test(n.image || '')) {

      nfImage.value = '';
      nfImage.dataset.upload = n.image;
      p.src = n.image;
      p.classList.remove('hidden');
    } else {
      delete nfImage.dataset.upload;
      nfImage.value = n.image || '';
      nfImage.dispatchEvent(new Event('input'));
    }
  } else {
    setNewsKind('update');
    document.getElementById('nfBadge').value = n.badge || '패치노트';
    document.getElementById('nfTitle').value = n.title || '';
    document.getElementById('nfBody').value = n.body || '';
  }
}

document.getElementById('newsCancel').addEventListener('click', () => newsSetEditMode(null));

document.getElementById('newsAdd').addEventListener('click', () => {
  if (newsKind === 'banner') {

    const image = (nfImage.dataset.upload || '').trim() || nfImage.value.trim();
    if (!image) {
      showToast('이미지를 선택하거나 주소를 입력하세요', true);
      return;
    }
    if (newsEditId) newsPost('newsEdit', { id: newsEditId, image: image });
    else newsPost('newsAdd', { kind: 'banner', image: image });
    newsSetEditMode(null);
    return;
  }

  const title = document.getElementById('nfTitle').value.trim();
  if (!title) return;

  const body = {
    badge: document.getElementById('nfBadge').value.trim() || '패치노트',
    title: title,
    body: document.getElementById('nfBody').value,
  };

  if (newsEditId) {
    body.id = newsEditId;
    newsPost('newsEdit', body);
  } else {
    body.kind = 'update';
    newsPost('newsAdd', body);
  }
  newsSetEditMode(null);
});

function renderNewsList() {
  const box = document.getElementById('newsList');
  if (!box) return;
  box.innerHTML = '';

  const rows = newsData.filter((n) => n.kind === newsKind);
  if (!rows.length) {
    box.innerHTML = '<div class="ck-skin-empty">등록된 항목이 없습니다</div>';
    return;
  }

  rows.forEach((n) => {
    const row = document.createElement('div');
    row.className = 'ck-news-item' + (Number(n.active) ? '' : ' off');

    let main = '';
    if (n.kind === 'banner') {
      main = '<img class="ck-news-thumb" src="' + newsImgSrc(n.image) + '" alt="">' +
             '<span class="ck-news-main"><span class="ck-news-title">이미지</span>' +
             '<span class="ck-news-body">' + escapeHtml(n.image || '') + '</span></span>';
    } else {
      main = '<span class="ck-news-badge-chip">' + escapeHtml(n.badge || '패치노트') + '</span>' +
             '<span class="ck-news-main"><span class="ck-news-title">' + escapeHtml(n.title || '') + '</span>' +
             '<span class="ck-news-body">' + escapeHtml(n.body || '') + '</span></span>';
    }

    row.innerHTML = main +
      '<span class="ck-news-acts">' +
        '<button class="ck-news-btn" data-edit="' + n.id + '">수정</button>' +
        '<button class="ck-news-btn" data-toggle="' + n.id + '">' +
          (Number(n.active) ? '숨기기' : '노출') + '</button>' +
        '<button class="ck-news-btn del" data-del="' + n.id + '">삭제</button>' +
      '</span>';

    box.appendChild(row);
  });

  box.querySelectorAll('[data-edit]').forEach((b) =>
    b.addEventListener('click', () => {
      const n = newsData.find((x) => Number(x.id) === Number(b.dataset.edit));
      if (n) newsSetEditMode(n);
    }));
  box.querySelectorAll('[data-toggle]').forEach((b) =>
    b.addEventListener('click', () => newsPost('newsToggle', { id: Number(b.dataset.toggle) })));
  box.querySelectorAll('[data-del]').forEach((b) =>
    b.addEventListener('click', () => newsPost('newsDelete', { id: Number(b.dataset.del) })));
}

const noticeText = document.getElementById('noticeText');
const noticeSend = document.getElementById('noticeSend');
let noticeKind = 'text';
let noticeSecs = 10;

const noticeSecCustom = document.getElementById('noticeSecCustom');

function openNoticeModal() {
  noticeKind = 'text';
  noticeSecs = 10;
  noticeText.value = '';
  if (noticeSecCustom) noticeSecCustom.value = '';
  document.getElementById('noticeLen').textContent = '0';
  noticeSend.disabled = true;

  document.querySelectorAll('#noticeKind .ck-seg-btn').forEach((b) =>
    b.classList.toggle('active', b.dataset.kind === 'text'));
  document.querySelectorAll('#noticeSecs .ck-min-btn').forEach((b) =>
    b.classList.toggle('active', Number(b.dataset.sec) === 10));
  document.getElementById('noticeSecRow').classList.add('hidden');

  document.getElementById('noticeModal').classList.remove('hidden');
  setTimeout(() => noticeText.focus(), 50);
}

if (noticeSecCustom) {
  noticeSecCustom.addEventListener('input', () => {
    const only = noticeSecCustom.value.replace(/[^0-9]/g, '');
    if (only !== noticeSecCustom.value) noticeSecCustom.value = only;

    const n = Number(only);
    if (n > 0) {
      noticeSecs = Math.min(300, n);
      document.querySelectorAll('#noticeSecs .ck-min-btn').forEach((x) =>
        x.classList.remove('active'));
    }
  });
}

function closeNoticeModal() {
  document.getElementById('noticeModal').classList.add('hidden');
}

const noticeBtn = document.getElementById('noticeBtn');
if (noticeBtn) noticeBtn.addEventListener('click', openNoticeModal);

const rebootBtn = document.getElementById('rebootBtn');
if (rebootBtn) rebootBtn.addEventListener('click', () => {
  if (myEffectiveLevel < 5 || rebootRemain > 0 || rebootExecuting) return;
  rebootBtn.disabled = true;
  rebootBtn.textContent = '리붓 요청 중...';
  fetch('https://cookie_admin/startReboot', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({})
  }).catch(() => {});
  setTimeout(() => {
    if (rebootRemain <= 0 && !rebootExecuting) {
      rebootBtn.disabled = false;
      rebootBtn.textContent = '서버 리붓 (60초)';
    }
  }, 2500);
});

function applyRebootCountdown(seconds) {
  const sec = Math.max(0, Math.floor(Number(seconds) || 0));
  const btn = document.getElementById('rebootBtn');
  const publicTimer = document.getElementById('rebootPublicTimer');
  const publicCount = document.getElementById('rebootPublicCount');
  const publicText = document.getElementById('rebootPublicText');

  const mm = String(Math.floor(sec / 60)).padStart(2, '0');
  const ss = String(sec % 60).padStart(2, '0');

  if (publicTimer) {
    publicTimer.classList.remove('hidden');
    publicTimer.classList.toggle('is-zero', sec <= 0);
  }
  if (publicCount) publicCount.textContent = mm + ':' + ss;
  if (publicText) {
    publicText.textContent = sec > 0
      ? '리붓까지 ' + sec + '초 · 안전 모드 활성화'
      : '카운트 종료 · 리붓 진행 중';
  }

  if (sec > 0) {
    rebootRemain = sec;
    rebootExecuting = false;
    if (btn) {
      btn.disabled = true;
      btn.textContent = '리붓까지 ' + sec + '초';
    }
    return;
  }

  rebootRemain = 0;
  rebootExecuting = true;
  if (btn) {
    btn.disabled = true;
    btn.textContent = '리붓 실행 중...';
  }
}
document.getElementById('noticeClose').addEventListener('click', closeNoticeModal);

document.querySelectorAll('#noticeKind .ck-seg-btn').forEach((b) => {
  b.addEventListener('click', () => {
    noticeKind = b.dataset.kind;
    document.querySelectorAll('#noticeKind .ck-seg-btn').forEach((x) =>
      x.classList.toggle('active', x === b));
    document.getElementById('noticeSecRow').classList.toggle('hidden', noticeKind !== 'count');
  });
});

document.querySelectorAll('#noticeSecs .ck-min-btn').forEach((b) => {
  b.addEventListener('click', () => {
    noticeSecs = Number(b.dataset.sec) || 10;
    document.querySelectorAll('#noticeSecs .ck-min-btn').forEach((x) =>
      x.classList.toggle('active', x === b));
  });
});

if (noticeText) {
  noticeText.addEventListener('input', () => {
    document.getElementById('noticeLen').textContent = String(noticeText.value.length);
    noticeSend.disabled = noticeText.value.trim().length < 2;
  });
}

if (noticeSend) {
  noticeSend.addEventListener('click', () => {
    const text = noticeText.value.trim();
    if (text.length < 2) return;
    fetch('https://cookie_admin/sendNotice', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        text: text,
        seconds: (noticeKind === 'count') ? noticeSecs : 0,
      }),
    }).catch(() => {});
    closeNoticeModal();
  });
}

function postTargetVehicleAction(action, targetServerId, model) {
  fetch('https://cookie_admin/targetVehicleAction', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      action: action,
      targetServerId: targetServerId,
      model: model || null,
    }),
  }).catch(() => {});
}

function closeTargetVehicleModal() {
  const modal = document.getElementById('targetVehicleModal');
  if (modal) modal.classList.add('hidden');
  targetVehicleAction = null;
  targetVehicleTarget = null;
  const q = document.getElementById('targetVehSearch');
  if (q) q.value = '';
}

function renderTargetVehicleList() {
  const list = document.getElementById('targetVehList');
  if (!list || !targetVehicleAction || !targetVehicleTarget) return;

  const qEl = document.getElementById('targetVehSearch');
  const q = ((qEl && qEl.value) || '').trim().toLowerCase();
  let rows = (vehicleCatalog || []).filter((v) => {
    if ((targetVehicleAction === 'give' || targetVehicleAction === 'mailgive') && !v.garageType) return false;
    if (!q) return true;
    return String(v.name || '').toLowerCase().includes(q)
      || String(v.model || '').toLowerCase().includes(q)
      || String(v.brand || '').toLowerCase().includes(q)
      || String(v.garageLabel || '').toLowerCase().includes(q);
  });

  rows.sort((a, b) => String(a.name || a.model).localeCompare(String(b.name || b.model), 'ko'));
  rows = rows.slice(0, 300);
  list.innerHTML = '';

  if (!rows.length) {
    list.innerHTML = '<div class="ck-veh-empty">선택 가능한 차량이 없습니다</div>';
    return;
  }

  rows.forEach((v) => {
    const row = document.createElement('div');
    row.className = 'ck-veh-row';

    const info = document.createElement('div');
    info.className = 'ck-veh-info';
    const name = document.createElement('div');
    name.className = 'ck-veh-name';
    name.textContent = ((targetVehicleAction === 'give' || targetVehicleAction === 'mailgive') && v.garageLabel) ? v.garageLabel : (v.name || v.model);

    if (v.garageType) {
      const badge = document.createElement('span');
      badge.className = 'ck-targetveh-type ' + v.garageType;
      badge.textContent = v.garageType === 'limited' ? '한정 차량' : '일반 차량';
      name.appendChild(badge);
    }

    const code = document.createElement('div');
    code.className = 'ck-targetveh-code';
    code.textContent = String(v.model || '') + (v.brand ? ' · ' + v.brand : '');
    info.appendChild(name);
    info.appendChild(code);

    const btn = document.createElement('button');
    btn.className = 'ck-veh-spawn';
    btn.textContent = targetVehicleAction === 'mailgive' ? '선택' : (targetVehicleAction === 'give' ? '지급' : '스폰');
    btn.addEventListener('click', () => {
      if (targetVehicleAction === 'mailgive') {
        const chosenTarget = targetVehicleTarget;
        closeTargetVehicleModal();
        openGrantMailModal('vehicle', {
          target: chosenTarget,
          model: v.model,
          label: v.garageLabel || v.name || v.model,
          garageType: v.garageType || null,
        });
        return;
      }
      postTargetVehicleAction(targetVehicleAction, targetVehicleTarget.serverId, v.model);
      closeTargetVehicleModal();
    });

    row.appendChild(info);
    row.appendChild(btn);
    list.appendChild(row);
  });
}

function openTargetVehicleModal(action) {
  if (!activeTarget) return;
  targetVehicleAction = action;
  targetVehicleTarget = {
    serverId: activeTarget.serverId,
    name: activeTarget.nickname || activeTarget.name || activeTarget.realname || ('#' + activeTarget.serverId),
  };

  const title = document.getElementById('targetVehTitle');
  const target = document.getElementById('targetVehTarget');
  const hint = document.getElementById('targetVehHint');
  if (title) title.textContent = (action === 'give' || action === 'mailgive') ? '차량 지급' : '차량 스폰';
  if (target) target.textContent = targetVehicleTarget.name + ' [' + targetVehicleTarget.serverId + ']';
  if (hint) hint.textContent = (action === 'give' || action === 'mailgive')
    ? (action === 'mailgive'
      ? '일반/한정 차량만 표시됩니다. 차량을 선택한 뒤 사유를 적어 대상 우편함으로 발송합니다.'
      : '일반/한정 차량 목록에 등록된 차량만 표시됩니다.')
    : '차고에는 저장되지 않는 임시 차량입니다. 대상 명의로 스폰되고 차량 키가 즉시 지급됩니다.';

  const q = document.getElementById('targetVehSearch');
  if (q) q.value = '';
  renderTargetVehicleList();

  closeTargetModal();
  const modal = document.getElementById('targetVehicleModal');
  if (modal) modal.classList.remove('hidden');
  if (q) setTimeout(() => q.focus(), 30);
}

const targetVehClose = document.getElementById('targetVehClose');
if (targetVehClose) targetVehClose.addEventListener('click', closeTargetVehicleModal);
const targetVehSearch = document.getElementById('targetVehSearch');
if (targetVehSearch) targetVehSearch.addEventListener('input', renderTargetVehicleList);

function renderTabs() {
  const tabBar = document.getElementById('modalTabs');
  tabBar.innerHTML = '';
  currentFeatures.forEach((cat, i) => {
    const tab = document.createElement('span');
    tab.className = 'ck-tab' + (i === activeTab ? ' active' : '');
    tab.textContent = cat.label;
    tab.addEventListener('click', () => { activeTab = i; renderTabs(); renderFeatures(); });
    tabBar.appendChild(tab);
  });
  renderFeatures();
}

function renderFeatures() {
  const grid = document.getElementById('modalFeatures');
  grid.innerHTML = '';

  hideLevelChange();
  const cat = currentFeatures[activeTab];
  if (!cat) return;

  const DANGER_KEYS = ['jail', 'kick', 'ban'];
  const ADMIN_KEYS = ['admin_alias'];
  const PLAYER_KEYS = ['send_onboarding'];

  const isDutyTab = (cat.key === LVCHG_CATEGORY);
  const isPlayerTab = (cat.key === 'player');

  const safe = cat.features.filter((f) =>
    f.key !== 'cure_wound' &&
    !DANGER_KEYS.includes(f.key) &&
    !ADMIN_KEYS.includes(f.key) &&
    !PLAYER_KEYS.includes(f.key));

  if (isPlayerTab) {
    currentFeatures.forEach((c) => {
      c.features.forEach((f) => {
        if (PLAYER_KEYS.includes(f.key) && !safe.some((s) => s.key === f.key)) {
          safe.push(f);
        }
      });
    });
  }

  const danger = isDutyTab
    ? currentFeatures.reduce((acc, c) =>
        acc.concat(c.features.filter((f) => DANGER_KEYS.includes(f.key))), [])
    : [];

  const adminFeats = isDutyTab
    ? currentFeatures.reduce((acc, c) =>
        acc.concat(c.features.filter((f) => ADMIN_KEYS.includes(f.key))), [])
    : [];

  const mkBtn = (f) => {
    const btn = document.createElement('div');

    let cls = 'ck-feat';
    if (DANGER_KEYS.includes(f.key) || f.key === 'faction_remove' || f.key === 'confiscate_item') cls += ' danger';
    if (f.key === 'send_onboarding' || f.key === 'faction_warn') cls += ' warn';
    btn.className = cls;
    btn.textContent = f.label;
    btn.addEventListener('click', () => {
      if (f.key === 'give_money') {
        openGrantMailModal('money');
        return;
      }
      if (f.key === 'give_item') {
        openGrantMailModal('item');
        return;
      }
      if (f.key === 'confiscate_item') {
        openConfiscateModal();
        return;
      }
      if (f.key === 'send_onboarding') {
        openOnboardingModal(activeTarget.serverId, activeTarget.name);
        return;
      }
      if (f.key === 'admin_alias') {
        openAliasModal(activeTarget.serverId, activeTarget.name, activeTarget.adminName);
        return;
      }
      if (f.key && f.key.indexOf('wcat:') === 0) {
        openWeaponModal(f.key.slice(5));
        return;
      }
      if (f.key === 'veh_spawn') {
        openTargetVehicleModal('spawn');
        return;
      }
      if (f.key === 'veh_give') {
        openTargetVehicleModal('mailgive');
        return;
      }
      if (f.key === 'veh_del') {
        postTargetVehicleAction('delete', activeTarget.serverId, null);
        return;
      }
      if (f.key === 'veh_fix') {
        postTargetVehicleAction('repair', activeTarget.serverId, null);
        return;
      }
      if (
        f.key === 'kick' || f.key === 'ban' || f.key === 'jail' ||
        f.key === 'license_suspend' || f.key === 'license_restore'
      ) {
        openReasonModal(f.key);
        return;
      }
      if (f.key === 'faction_warn' || f.key === 'faction_remove') {
        openReasonModal(f.key);
        return;
      }
      fetch('https://cookie_admin/runFeature', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          featureKey: f.key,
          targetServerId: activeTarget.serverId,
        }),
      }).catch(() => {});
    });
    return btn;
  };

  if (safe.length) {
    const safeGrid = document.createElement('div');
    safeGrid.className = 'ck-featgrid';
    safe.forEach((f) => safeGrid.appendChild(mkBtn(f)));
    grid.appendChild(safeGrid);
  }

  if (isDutyTab && (adminFeats.length || myEffectiveLevel >= 5)) {
    const cap = document.createElement('p');
    cap.className = 'ck-label ck-sec-cap';
    cap.textContent = '관리자 관리';
    grid.appendChild(cap);

    const aGrid = document.createElement('div');
    aGrid.className = 'ck-featgrid';
    adminFeats.forEach((f) => aGrid.appendChild(mkBtn(f)));

    if (myEffectiveLevel >= 5) {
      const lv = document.createElement('div');
      lv.className = 'ck-feat';
      lv.textContent = '관리자 레벨 변경';
      lv.addEventListener('click', openLevelChange);
      aGrid.appendChild(lv);

      const gr = document.createElement('div');
      gr.className = 'ck-feat';
      gr.textContent = '관리자 권한부여';
      gr.addEventListener('click', () => {
        const g = document.getElementById('grantBtn');
        if (g) g.click();
      });
      aGrid.appendChild(gr);
    }

    grid.appendChild(aGrid);
  }

  const showChatMod = isDutyTab && myEffectiveLevel >= CHATMOD_MIN_LEVEL;

  if (danger.length || showChatMod) {
    const cap = document.createElement('p');
    cap.className = 'ck-label ck-danger-cap';
    cap.textContent = '주의가 필요한 조치';
    grid.appendChild(cap);

    const dGrid = document.createElement('div');
    dGrid.className = 'ck-featgrid';

    if (showChatMod) {
      [['warn', '경고'], ['mute', '입막음']].forEach(([group, label]) => {
        const b = document.createElement('div');
        b.className = 'ck-feat danger';
        b.textContent = label;
        b.addEventListener('click', () => openReasonModal(group));
        dGrid.appendChild(b);
      });
    }
    danger.forEach((f) => dGrid.appendChild(mkBtn(f)));

    grid.appendChild(dGrid);
  }
}

document.getElementById('modalClose').addEventListener('click', closeTargetModal);

let onboardingTarget = null;
function openOnboardingModal(serverId, name) {
  onboardingTarget = serverId;
  document.getElementById('obTargetName').textContent = name;
  document.getElementById('onboardingModal').classList.remove('hidden');
}
function closeOnboardingModal() {
  document.getElementById('onboardingModal').classList.add('hidden');
  onboardingTarget = null;
}
document.getElementById('obCancel').addEventListener('click', closeOnboardingModal);
document.getElementById('obConfirm').addEventListener('click', () => {
  if (onboardingTarget == null) return;
  fetch('https://cookie_admin/runFeature', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ featureKey: 'send_onboarding', targetServerId: onboardingTarget }),
  }).catch(() => {});
  closeOnboardingModal();
});


function gmPost(name, payload) {
  return fetch('https://cookie_admin/' + name, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload || {}),
  }).catch(() => null);
}

function renderGrantItemOptions() {
  const sel = document.getElementById('gmItemSelect');
  if (!sel) return;
  const q = String((document.getElementById('gmItemSearch') || {}).value || '').trim().toLowerCase();
  const rows = (grantItemCatalog || []).filter((it) => {
    if (!q) return true;
    return String(it.label || '').toLowerCase().includes(q) || String(it.name || '').toLowerCase().includes(q);
  }).slice(0, 500);
  sel.innerHTML = '';
  if (!rows.length) {
    const opt = document.createElement('option');
    opt.disabled = true;
    opt.textContent = grantItemCatalog.length ? '검색 결과가 없습니다' : '아이템 목록을 불러오는 중...';
    sel.appendChild(opt);
    return;
  }
  rows.forEach((it) => {
    const opt = document.createElement('option');
    opt.value = it.name;
    opt.textContent = (it.label || it.name) + '  [' + it.name + ']';
    sel.appendChild(opt);
  });
  if (sel.options.length) sel.selectedIndex = 0;
}

function closeGrantMailModal() {
  const m = document.getElementById('grantMailModal');
  if (m) m.classList.add('hidden');
  grantMailDraft = null;
  grantMailBusy = false;
  const send = document.getElementById('gmSend');
  if (send) { send.disabled = false; send.textContent = '우편 발송'; }
}

function openGrantMailModal(type, vehicleData) {
  let target = null;
  if (vehicleData && vehicleData.target) {
    target = vehicleData.target;
  } else if (activeTarget) {
    target = {
      serverId: activeTarget.serverId,
      name: activeTarget.nickname || activeTarget.name || activeTarget.realname || ('#' + activeTarget.serverId),
    };
  }
  if (!target) { showToast('지급 대상을 찾을 수 없습니다', true); return; }

  grantMailDraft = { type: type, target: target };
  if (type === 'vehicle' && vehicleData) {
    grantMailDraft.vehicleModel = vehicleData.model;
    grantMailDraft.vehicleLabel = vehicleData.label;
    grantMailDraft.vehicleType = vehicleData.garageType;
  }

  const titleMap = { money: '돈 지급 · 우편 발송', item: '아이템 지급 · 우편 발송', vehicle: '차량 지급 · 우편 발송' };
  document.getElementById('gmTitle').textContent = titleMap[type] || '지급 우편 보내기';
  document.getElementById('gmTarget').textContent = target.name + ' [' + target.serverId + ']';
  document.getElementById('gmMoneyFields').classList.toggle('hidden', type !== 'money');
  document.getElementById('gmItemFields').classList.toggle('hidden', type !== 'item');
  document.getElementById('gmVehicleFields').classList.toggle('hidden', type !== 'vehicle');
  document.getElementById('gmReason').value = '';
  document.getElementById('gmAmount').value = '';
  document.getElementById('gmQuantity').value = '1';
  document.getElementById('gmItemSearch').value = '';
  document.querySelectorAll('.ck-gm-account').forEach((b) => b.classList.toggle('active', b.dataset.account === 'cash'));
  if (type === 'vehicle') {
    document.getElementById('gmVehicleLabel').textContent = (grantMailDraft.vehicleLabel || grantMailDraft.vehicleModel || '-') +
      (grantMailDraft.vehicleType ? (' · ' + (grantMailDraft.vehicleType === 'limited' ? '한정 차량' : '일반 차량')) : '');
  }
  if (type === 'item') {
    renderGrantItemOptions();
    gmPost('requestGrantItems', {});
  }

  if (activeTarget) closeTargetModal();
  document.getElementById('grantMailModal').classList.remove('hidden');
  setTimeout(() => document.getElementById('gmReason').focus(), 20);
}

function sendGrantMail() {
  if (!grantMailDraft || grantMailBusy) return;
  const reason = document.getElementById('gmReason').value.trim();
  const payload = {
    type: grantMailDraft.type,
    targetServerId: grantMailDraft.target.serverId,
    reason: reason,
  };
  if (grantMailDraft.type === 'money') {
    const accountBtn = document.querySelector('.ck-gm-account.active');
    const amount = parseInt(document.getElementById('gmAmount').value, 10);
    if (!amount || amount < 1) { showToast('지급 금액을 입력해주세요', true); return; }
    payload.account = accountBtn ? accountBtn.dataset.account : 'cash';
    payload.amount = amount;
  } else if (grantMailDraft.type === 'item') {
    const sel = document.getElementById('gmItemSelect');
    const qty = parseInt(document.getElementById('gmQuantity').value, 10);
    if (!sel || !sel.value) { showToast('지급할 아이템을 선택해주세요', true); return; }
    if (!qty || qty < 1 || qty > 9999) { showToast('수량은 1~9999개로 입력해주세요', true); return; }
    payload.itemName = sel.value;
    payload.quantity = qty;
  } else if (grantMailDraft.type === 'vehicle') {
    if (!grantMailDraft.vehicleModel) { showToast('차량을 선택해주세요', true); return; }
    payload.vehicleModel = grantMailDraft.vehicleModel;
  }

  grantMailBusy = true;
  const b = document.getElementById('gmSend');
  b.disabled = true; b.textContent = '발송 중...';
  gmPost('sendGrantMail', payload);
  setTimeout(() => {
    if (!grantMailBusy) return;
    grantMailBusy = false;
    b.disabled = false; b.textContent = '우편 발송';
  }, 8000);
}

function mailTypeLabel(row) {
  if (row.mail_type === 'money') return row.account === 'bank' ? '계좌 지급' : '현금 지급';
  if (row.mail_type === 'item') return '아이템 지급';
  if (row.mail_type === 'vehicle') return '차량 지급';
  return '관리자 지급';
}

function renderMailbox() {
  const list = document.getElementById('mailboxList');
  const summary = document.getElementById('mailboxSummary');
  if (!list || !summary) return;
  const pending = (mailboxRows || []).filter((r) => r.status === 'pending').length;
  summary.innerHTML = '<b>미수령 ' + fmtNum(pending) + '건</b><span> · 최근 우편 ' + fmtNum((mailboxRows || []).length) + '건</span>';
  list.innerHTML = '';
  if (!mailboxRows || !mailboxRows.length) {
    list.innerHTML = '<div class="ck-mailbox-empty">도착한 우편이 없습니다.</div>';
    return;
  }
  mailboxRows.forEach((r) => {
    const pendingNow = r.status === 'pending';
    const card = document.createElement('div');
    card.className = 'ck-mail-card' + (pendingNow ? ' pending' : ' claimed');
    const sender = '관리자 ' + escapeHtml(r.sender_name || '관리자') + '님이 보냄';
    card.innerHTML =
      '<div class="ck-mail-card-top"><div><span class="ck-mail-kind">' + escapeHtml(mailTypeLabel(r)) + '</span>' +
      '<b class="ck-mail-reward">' + escapeHtml(r.reward_label || '-') + '</b></div>' +
      '<span class="ck-mail-status">' + (pendingNow ? '수령 대기' : '수령 완료') + '</span></div>' +
      '<div class="ck-mail-sender">' + sender + ' · ' + escapeHtml(fmtDate(r.created_at)) + '</div>' +
      '<div class="ck-mail-reason"><span>사유</span><p>' + escapeHtml(r.reason || '사유 없음') + '</p></div>' +
      (pendingNow ? '<button class="ck-mail-claim" data-mail-id="' + Number(r.id) + '">수령하기</button>' :
        '<div class="ck-mail-claimed-row"><div class="ck-mail-claimed-at">수령: ' + escapeHtml(fmtDate(r.claimed_at)) + '</div>' +
        '<button class="ck-mail-delete" data-mail-delete-id="' + Number(r.id) + '">삭제</button></div>');
    list.appendChild(card);
  });
  list.querySelectorAll('[data-mail-id]').forEach((b) => {
    b.addEventListener('click', () => {
      if (b.disabled) return;
      b.disabled = true; b.textContent = '처리 중...';
      gmPost('claimMailbox', { id: Number(b.dataset.mailId) });
      setTimeout(() => { if (document.body.contains(b)) { b.disabled = false; b.textContent = '수령하기'; } }, 8000);
    });
  });
  list.querySelectorAll('[data-mail-delete-id]').forEach((b) => {
    b.addEventListener('click', () => {
      if (b.disabled) return;
      if (!window.confirm('이미 수령한 이 우편을 삭제할까요?')) return;
      b.disabled = true; b.textContent = '삭제 중...';
      gmPost('deleteMailbox', { id: Number(b.dataset.mailDeleteId) });
      setTimeout(() => { if (document.body.contains(b)) { b.disabled = false; b.textContent = '삭제'; } }, 8000);
    });
  });
}

function openMailboxModal() {
  mailboxRows = [];
  document.getElementById('mailboxSummary').textContent = '우편을 불러오는 중...';
  document.getElementById('mailboxList').innerHTML = '<div class="ck-mailbox-empty">불러오는 중...</div>';
  document.getElementById('mailboxModal').classList.remove('hidden');
  gmPost('requestMailbox', {});
}

function closeMailboxModal() {
  document.getElementById('mailboxModal').classList.add('hidden');
}

(function wireGrantMailboxUi() {
  const gmClose = document.getElementById('gmClose'); if (gmClose) gmClose.addEventListener('click', closeGrantMailModal);
  const gmCancel = document.getElementById('gmCancel'); if (gmCancel) gmCancel.addEventListener('click', closeGrantMailModal);
  const gmSend = document.getElementById('gmSend'); if (gmSend) gmSend.addEventListener('click', sendGrantMail);
  const search = document.getElementById('gmItemSearch'); if (search) search.addEventListener('input', renderGrantItemOptions);
  document.querySelectorAll('.ck-gm-account').forEach((b) => b.addEventListener('click', () => {
    document.querySelectorAll('.ck-gm-account').forEach((x) => x.classList.toggle('active', x === b));
  }));
  const mc = document.getElementById('mailboxClose'); if (mc) mc.addEventListener('click', closeMailboxModal);
  const mr = document.getElementById('mailboxReload'); if (mr) mr.addEventListener('click', () => gmPost('requestMailbox', {}));
})();

let currentMoneyTarget = null;
let currentAccount = 'cash';

function openMoneyModal(targetServerId, targetName) {
  document.getElementById('mmTargetName').textContent = targetName;
  document.getElementById('mmAmount').value = '';
  currentMoneyTarget = targetServerId;
  currentAccount = 'cash';
  document.querySelectorAll('.ck-mm-tab').forEach(t => t.classList.toggle('active', t.dataset.account === 'cash'));
  document.getElementById('moneyModal').classList.remove('hidden');
}

document.querySelectorAll('.ck-mm-tab').forEach(tab => {
  tab.addEventListener('click', () => {
    currentAccount = tab.dataset.account;
    document.querySelectorAll('.ck-mm-tab').forEach(t => t.classList.toggle('active', t === tab));
  });
});

document.getElementById('mmConfirm').addEventListener('click', () => {
  const amount = parseInt(document.getElementById('mmAmount').value, 10);
  if (!amount || amount < 1) return;
  fetch('https://cookie_admin/giveMoney', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ targetServerId: currentMoneyTarget, account: currentAccount, amount: amount }),
  }).catch(() => {});
  document.getElementById('moneyModal').classList.add('hidden');
});

document.getElementById('mmCancel').addEventListener('click', () => {
  document.getElementById('moneyModal').classList.add('hidden');
});

const AMMO_LABELS = {
  'ammo-9': '9mm', 'ammo-45': '.45', 'ammo-50': '.50 AE', 'ammo-22': '.22', 'ammo-44': '.44', 'ammo-38': '.38',
  'ammo-flare': '플레어', 'ammo-rifle': '라이플탄', 'ammo-rifle2': '라이플탄(고급)', 'ammo-shotgun': '산탄',
  'ammo-sniper': '저격탄', 'ammo-heavysniper': '대물저격탄', 'ammo-rocket': '로켓', 'ammo-grenade': '40mm 유탄',
  'ammo-mg': 'MG탄', 'ammo-emp': 'EMP',
};
function ammoLabel(a) { if (!a) return null; return AMMO_LABELS[a] || String(a).replace('ammo-', ''); }

function openWeaponModal(catKey) {
  const cat = weaponCatalog.find((c) => c.key === catKey);

  if (!cat || !activeTarget) return;
  wpActiveCat = cat;
  wpSelected = null;
  document.getElementById('wpTitle').textContent = '무기 관리 · ' + cat.label;
  document.getElementById('wpTargetName').textContent = activeTarget.name;
  document.getElementById('wpGive').classList.add('hidden');
  const list = document.getElementById('wpList');
  list.innerHTML = '';
  (cat.items || []).forEach((w) => {
    const b = document.createElement('div');
    b.className = 'ck-wp-item';
    const nm = document.createElement('div'); nm.className = 'ck-wp-item-name'; nm.textContent = w.label;
    b.appendChild(nm);
    const al = ammoLabel(w.ammo);
    if (al) {
      const s = document.createElement('div'); s.className = 'ck-wp-item-ammo'; s.textContent = '탄약 ' + al;
      b.appendChild(s);
    }
    b.addEventListener('click', () => selectWeapon(cat, w, b));
    list.appendChild(b);
  });

  const ammos = [];
  (cat.items || []).forEach((w) => { const al = ammoLabel(w.ammo); if (al && ammos.indexOf(al) === -1) ammos.push(al); });
  const catAmmoEl = document.getElementById('wpCatAmmo');
  if (catAmmoEl) {
    catAmmoEl.textContent = ammos.length ? ('이 분류 탄약 종류: ' + ammos.join(' · '))
      : (cat.type === 'throwable' ? '투척 무기 — 개수로 지급' : (cat.type === 'melee' ? '근접 무기 — 탄약 없음' : '탄약 없음'));
  }
  document.getElementById('weaponModal').classList.remove('hidden');
}

function selectWeapon(cat, w, el) {
  wpSelected = w;
  document.querySelectorAll('#wpList .ck-wp-item.active').forEach((x) => x.classList.remove('active'));
  if (el) el.classList.add('active');
  document.getElementById('wpSelName').textContent = w.label;
  const wrap = document.getElementById('wpAmountWrap');
  const label = document.getElementById('wpAmountLabel');
  const input = document.getElementById('wpAmount');
  const selAmmo = document.getElementById('wpSelAmmo');
  const btnWpn = document.getElementById('wpGiveWpn');
  const btnAmmo = document.getElementById('wpGiveAmmo');
  input.value = '';
  const al = ammoLabel(w.ammo);
  if (al) { selAmmo.textContent = '탄약: ' + al; selAmmo.classList.remove('hidden'); }
  else { selAmmo.classList.add('hidden'); }

  if (cat.type === 'gun' && w.ammo) {
    wrap.classList.remove('hidden'); label.textContent = '탄약 수 (1~9999)';
    btnWpn.classList.remove('hidden'); btnAmmo.classList.remove('hidden');
  } else if (cat.type === 'throwable') {
    wrap.classList.remove('hidden'); label.textContent = '개수 (1~9999)';
    btnWpn.classList.remove('hidden'); btnAmmo.classList.add('hidden');
  } else {
    wrap.classList.add('hidden');
    btnWpn.classList.remove('hidden'); btnAmmo.classList.add('hidden');
  }
  document.getElementById('wpGive').classList.remove('hidden');
}

function closeWeaponModal() {
  document.getElementById('weaponModal').classList.add('hidden');
  wpActiveCat = null; wpSelected = null;
}

document.getElementById('wpClose').addEventListener('click', closeWeaponModal);
document.getElementById('wpCancel').addEventListener('click', () => {
  document.getElementById('wpGive').classList.add('hidden');
  wpSelected = null;
  document.querySelectorAll('#wpList .ck-wp-item.active').forEach((x) => x.classList.remove('active'));
});

function giveWeaponAction(mode) {
  if (!wpSelected || !wpActiveCat || !activeTarget) return;
  const cat = wpActiveCat, w = wpSelected;
  let amount = 0;
  if (mode === 'ammo') {
    if (!(cat.type === 'gun' && w.ammo)) { showToast('이 무기는 별도 탄약이 없습니다', true); return; }
    amount = parseInt(document.getElementById('wpAmount').value, 10);
    if (!amount || amount < 1 || amount > 9999) { showToast('탄약 수(1~9999)를 입력하세요', true); return; }
  } else if (cat.type === 'throwable') {
    amount = parseInt(document.getElementById('wpAmount').value, 10);
    if (!amount || amount < 1 || amount > 9999) { showToast('개수(1~9999)를 입력하세요', true); return; }
  }
  fetch('https://cookie_admin/giveWeapon', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ targetServerId: activeTarget.serverId, weapon: w.name, amount: amount, mode: mode }),
  }).catch(() => {});
  closeWeaponModal();
}
document.getElementById('wpGiveWpn').addEventListener('click', () => giveWeaponAction('weapon'));
document.getElementById('wpGiveAmmo').addEventListener('click', () => giveWeaponAction('ammo'));

function applyState(state) {
  currentState = state;
  if (document.getElementById('vehList')) renderVehList();
  const btn = document.getElementById('dutyToggle');
  if (!btn) return;
  if (state === 'duty') {
    btn.textContent = '관리 종료';
    btn.classList.add('on');
  } else {
    btn.textContent = '관리 시작';
    btn.classList.remove('on');
  }
}

document.getElementById('dutyToggle').addEventListener('click', () => {
  const isDuty = document.getElementById('dutyToggle').classList.contains('on');
  fetch('https://cookie_admin/' + (isDuty ? 'endDuty' : 'startDuty'), { method: 'POST', body: '{}' }).catch(() => {});
});

let pwInput = '';
let pwMode = 'set';
let pwCtx = null;

function updatePwDisplay() {
  const disp = document.getElementById('pwDisplay');
  let html = '';
  for (let i = 0; i < 6; i++) {
    html += i < pwInput.length
      ? '<span class="dot">●</span>'
      : '<span class="empty">_</span>';
  }
  disp.innerHTML = html;
}

function openPwModal(mode, ctx) {
  pwMode = mode || 'set';
  pwCtx = ctx || null;
  pwInput = '';
  updatePwDisplay();
  document.getElementById('pwTitle').textContent =
    pwMode === 'verify' ? '권한부여 인증' : '관리자 비밀번호';
  document.getElementById('pwSub').textContent =
    pwMode === 'verify' ? '본인 비밀번호 6자리를 입력하세요' : '6자리 숫자를 입력하세요';
  document.getElementById('pwModal').classList.remove('hidden');
}

function closePwModal() {
  document.getElementById('pwModal').classList.add('hidden');
  pwInput = '';
  pwCtx = null;
}

function submitPw() {
  if (!/^\d{6}$/.test(pwInput)) return;
  if (pwMode === 'verify') {

    const ctx = pwCtx || {};
    fetch('https://cookie_admin/grantAdmin', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ targetLicense: ctx.targetLicense, alias: ctx.alias || '', pw: pwInput, level: ctx.level || 1, team: ctx.team || null }),
    }).catch(() => {});
    closePwModal();
    closeGrantModal();
    return;
  }
  fetch('https://cookie_admin/setAdminPw', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ newPw: pwInput, oldPw: '' }),
  }).catch(() => {});
  closePwModal();
}

document.getElementById('pwBtn').addEventListener('click', () => openPwModal('set'));

document.querySelectorAll('.ck-pw-key[data-k]').forEach((key) => {
  key.addEventListener('click', () => {
    if (pwInput.length >= 6) return;
    pwInput += key.dataset.k;
    updatePwDisplay();
    if (pwInput.length === 6) submitPw();
  });
});

document.getElementById('pwBack').addEventListener('click', () => {
  pwInput = pwInput.slice(0, -1);
  updatePwDisplay();
});

document.getElementById('pwClear').addEventListener('click', () => {
  pwInput = '';
  updatePwDisplay();
});

document.getElementById('pwCancel').addEventListener('click', closePwModal);

let pwResetTarget = null;

function closePwResetModal() {
  document.getElementById('pwResetModal').classList.add('hidden');
  document.getElementById('pwResetConfirm').classList.add('hidden');
  document.getElementById('pwResetFoot').classList.remove('hidden');
  pwResetTarget = null;
}

function openPwResetModal() {
  pwResetTarget = null;
  document.getElementById('pwResetConfirm').classList.add('hidden');
  document.getElementById('pwResetFoot').classList.remove('hidden');
  const list = document.getElementById('pwResetList');
  list.innerHTML = '';
  currentPlayers.forEach((p) => {
    const row = document.createElement('div');
    row.className = 'ck-reset-row';
    row.innerHTML =
      '<span class="id">[' + p.serverId + ']</span>' +
      '<span>' + escapeHtml(p.name) + '</span>';
    row.addEventListener('click', () => {

      pwResetTarget = p.serverId;
      document.getElementById('pwResetName').textContent = p.name;
      document.getElementById('pwResetConfirm').classList.remove('hidden');
      document.getElementById('pwResetFoot').classList.add('hidden');
    });
    list.appendChild(row);
  });
  document.getElementById('pwResetModal').classList.remove('hidden');
}

document.getElementById('pwResetBtn').addEventListener('click', openPwResetModal);
document.getElementById('pwResetClose').addEventListener('click', closePwResetModal);
document.getElementById('pwResetNo').addEventListener('click', () => {
  document.getElementById('pwResetConfirm').classList.add('hidden');
  document.getElementById('pwResetFoot').classList.remove('hidden');
  pwResetTarget = null;
});
document.getElementById('pwResetYes').addEventListener('click', () => {
  if (pwResetTarget == null) return;
  fetch('https://cookie_admin/resetAdminPw', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ targetServerId: pwResetTarget }),
  }).catch(() => {});
  closePwResetModal();
});

const LICENSE_RE = /^license2?:[0-9a-fA-F]+$/;
let grantMethod = 'online';
let grantTargetLicense = null;
let grantTargetLabel = '';

function setGrantSelection(license, label) {
  grantTargetLicense = license;
  grantTargetLabel = label || license || '';
  document.getElementById('grantSelected').textContent = grantTargetLicense ? grantTargetLabel : '없음';
}

function clearGrantSelection() {
  grantTargetLicense = null;
  grantTargetLabel = '';
  document.getElementById('grantSelected').textContent = '없음';
  document.querySelectorAll('#grantList .ck-reset-row.active').forEach((r) => r.classList.remove('active'));
}

function hideGrantConfirm() {
  document.getElementById('grantConfirm').classList.add('hidden');
  document.getElementById('grantFoot').classList.remove('hidden');
}

function setGrantMethod(method) {
  grantMethod = method;
  document.querySelectorAll('.ck-grant-tab').forEach((t) => t.classList.toggle('active', t.dataset.method === method));
  document.getElementById('grantOnline').classList.toggle('hidden', method !== 'online');
  document.getElementById('grantManual').classList.toggle('hidden', method !== 'manual');

  document.getElementById('grantLicenseInput').value = '';
  clearGrantSelection();
  hideGrantConfirm();
}

function setGrantLevel(lv) {
  grantLevel = lv;
  document.querySelectorAll('#grantLevels .ck-lv-seg').forEach((b) =>
    b.classList.toggle('active', parseInt(b.dataset.level, 10) === lv));
  document.getElementById('grantLvName').textContent = LEVEL_NAME[lv] || ('LV' + lv);
  renderGrantTeams(lv);
}

function renderGrantTeams(lv) {
  const wrap = document.getElementById('grantTeamWrap');
  const box = document.getElementById('grantTeams');
  if (!wrap || !box) return;
  const show = (lv === 2 || lv === 3) && adminTeamsData.length > 0;
  if (!show) {
    grantTeam = null;
    wrap.classList.add('hidden');
    box.innerHTML = '';
    return;
  }
  wrap.classList.remove('hidden');
  box.innerHTML = '';
  adminTeamsData.forEach((t) => {
    const b = document.createElement('button');
    b.className = 'ck-lv-seg' + (t.key === grantTeam ? ' active' : '');
    b.textContent = t.label;
    b.dataset.team = t.key;
    b.addEventListener('click', () => {
      grantTeam = (grantTeam === t.key) ? null : t.key;
      box.querySelectorAll('.ck-lv-seg').forEach((x) =>
        x.classList.toggle('active', x.dataset.team === grantTeam));
    });
    box.appendChild(b);
  });
}

document.querySelectorAll('#grantLevels .ck-lv-seg').forEach((seg) => {
  seg.addEventListener('click', () => setGrantLevel(parseInt(seg.dataset.level, 10)));
});

function openGrantModal() {

  if (myEffectiveLevel < 5) {
    if (myLevel >= 5 && !myHasPw) {
      showToast('비밀번호 설정 후 LV5 권한이 발효됩니다', true);
      openPwModal('set');
    }
    return;
  }
  document.getElementById('grantAlias').value = '';
  document.getElementById('grantLicenseInput').value = '';
  document.getElementById('grantList').innerHTML = '<div class="ck-skin-empty">불러오는 중...</div>';
  setGrantLevel(1);
  clearGrantSelection();
  hideGrantConfirm();
  setGrantMethod('online');
  document.getElementById('grantModal').classList.remove('hidden');

  fetch('https://cookie_admin/requestGrantList', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' }).catch(() => {});
}

function closeGrantModal() {
  document.getElementById('grantModal').classList.add('hidden');
  clearGrantSelection();
  hideGrantConfirm();
}

function renderGrantList(players) {
  const list = document.getElementById('grantList');
  list.innerHTML = '';
  if (!players.length) {
    list.innerHTML = '<div class="ck-skin-empty">접속 중인 유저가 없습니다</div>';
    return;
  }
  players.forEach((p) => {
    const row = document.createElement('div');
    row.className = 'ck-reset-row';
    const gobun = (p.gobun != null) ? ('고번 ' + p.gobun) : '미가입';
    row.innerHTML =
      '<span class="id">' + escapeHtml(gobun) + '</span>' +
      '<span>' + escapeHtml(p.nickname || '-') + '</span>';
    row.addEventListener('click', () => {
      if (!p.license) { showToast('license를 확인할 수 없는 대상입니다', true); return; }
      document.querySelectorAll('#grantList .ck-reset-row.active').forEach((r) => r.classList.remove('active'));
      row.classList.add('active');

      document.getElementById('grantLicenseInput').value = '';
      setGrantSelection(p.license, gobun + ' · ' + (p.nickname || '-'));
      hideGrantConfirm();
    });
    list.appendChild(row);
  });
}

document.getElementById('grantLicenseInput').addEventListener('input', (e) => {
  const v = e.target.value.trim();
  document.querySelectorAll('#grantList .ck-reset-row.active').forEach((r) => r.classList.remove('active'));
  hideGrantConfirm();
  if (v) setGrantSelection(v, v);
  else clearGrantSelection();
});

document.querySelectorAll('.ck-grant-tab').forEach((tab) => {
  tab.addEventListener('click', () => setGrantMethod(tab.dataset.method));
});

document.getElementById('grantBtn').addEventListener('click', openGrantModal);
document.getElementById('grantClose').addEventListener('click', closeGrantModal);

document.getElementById('grantSubmit').addEventListener('click', () => {
  if (!grantTargetLicense) { showToast('대상을 선택하거나 license를 입력하세요', true); return; }
  if (!LICENSE_RE.test(grantTargetLicense)) { showToast('license 형식이 올바르지 않습니다', true); return; }
  document.getElementById('grantConfirmName').textContent = grantTargetLabel || grantTargetLicense;
  document.getElementById('grantConfirm').classList.remove('hidden');
  document.getElementById('grantFoot').classList.add('hidden');
});

document.getElementById('grantNo').addEventListener('click', hideGrantConfirm);

document.getElementById('grantYes').addEventListener('click', () => {
  if (!grantTargetLicense) return;
  const alias = document.getElementById('grantAlias').value.trim();
  openPwModal('verify', { targetLicense: grantTargetLicense, alias: alias, level: grantLevel, team: grantTeam });
});


const PERSONAL_STORAGE_META = {
  skin: {
    title: '스킨 보관함',
    desc: '보유한 한정 스킨과 현재 장착 중인 스킨을 확인합니다.',
    icon: '👤',
    empty: '보관 중인 한정 스킨이 없습니다'
  },
  vehicle: {
    title: '차량 보관함',
    desc: '포장 차량과 현재 보유 차량을 상태별로 한눈에 확인합니다.',
    icon: '🚗',
    empty: '보유한 차량이 없습니다'
  },
  cosmetic: {
    title: '치장 보관함',
    desc: '보유 중인 치장 아이템과 한정 치장을 확인합니다.',
    icon: '✨',
    empty: '보유한 치장이 없습니다'
  },
  chair: {
    title: '의자 보관함',
    desc: '설치 가능한 의자·가구 아이템을 확인합니다.',
    icon: '🪑',
    empty: '보유한 의자·가구가 없습니다'
  }
};

function personalStorageImage(item, tab) {
  const image = item && item.image ? String(item.image) : '';
  if (image) return '<img src="' + escapeHtml(image) + '" alt="">';
  const icon = (PERSONAL_STORAGE_META[tab] || {}).icon || '◻';
  return '<div class="ck-asset-placeholder">' + icon + '</div>';
}

function personalStorageMetaRows(item) {
  const m = item && item.meta ? item.meta : {};
  const rows = [];
  if (m.model) rows.push(['모델', m.model]);
  if (m.plate) rows.push(['번호판', m.plate]);
  if (m.assetUid && m.assetUid !== '-') rows.push(['고유 ID', m.assetUid]);
  if (m.garage) rows.push(['차고', m.garage]);
  if (m.upgrade) rows.push(['강화', m.upgrade]);
  if (m.color) rows.push(['색상', m.color]);
  if (m.key) rows.push(['코드', m.key]);
  return rows.slice(0, 4).map(r =>
    '<span><b>' + escapeHtml(r[0]) + '</b>' + escapeHtml(String(r[1])) + '</span>'
  ).join('');
}


function personalSkinCards() {
  const rows = [];
  (personalStorageData.skin || []).forEach(s => rows.push({
    ...s,
    state: s.state || '보관 중',
    description: s.description || '보유 중인 한정 스킨입니다.',
    actionable: true,
    ownedId: s.id || ''
  }));
  return rows;
}

function renderEquippedSkinHero() {
  const equipped = personalStorageData.equippedSkin;
  if (!equipped || personalStorageTab !== 'skin') return '';
  const image = personalStorageImage(equipped, 'skin');
  return '<div class="ck-equipped-hero">'+
    '<div class="ck-equipped-hero-image">'+image+'</div>'+
    '<div class="ck-equipped-hero-body">'+
      '<div class="ck-equipped-hero-kicker">현재 장착 중</div>'+
      '<div class="ck-equipped-hero-title">'+escapeHtml(equipped.label || equipped.key || '한정 스킨')+'</div>'+
      '<div class="ck-equipped-hero-desc">스킨 포장키트를 사용하면 원래 스킨으로 돌아가고 다시 보관함으로 복귀합니다.</div>'+
      '<div class="ck-equipped-hero-badges"><span>장착 중</span><span>'+escapeHtml(String(equipped.rarity || '한정'))+'</span></div>'+
    '</div>'+
  '</div>';
}

function personalStorageRows(tab) {
  if (tab === 'skin') return personalSkinCards();
  return Array.isArray(personalStorageData[tab]) ? personalStorageData[tab] : [];
}

function renderPersonalStorageModal() {
  const modal = document.getElementById('personalStorageModal');
  const grid = document.getElementById('personalStorageGrid');
  const title = document.getElementById('personalStorageTitle');
  const desc = document.getElementById('personalStorageDesc');
  const count = document.getElementById('personalStorageCount');
  if (!modal || !grid || !title || !desc || !count) return;

  const meta = PERSONAL_STORAGE_META[personalStorageTab] || PERSONAL_STORAGE_META.skin;
  const rows = personalStorageRows(personalStorageTab);

  title.textContent = meta.title;
  desc.textContent = meta.desc;
  count.textContent = (rows.length + (personalStorageTab === 'skin' && personalStorageData.equippedSkin ? 1 : 0)) + '개';

  modal.querySelectorAll('[data-personal-tab]').forEach(b =>
    b.classList.toggle('active', b.dataset.personalTab === personalStorageTab)
  );

  const hero = renderEquippedSkinHero();

  if (!rows.length) {
    grid.innerHTML = hero +
      '<div class="ck-asset-empty">' +
        '<div class="ck-asset-empty-icon">' + meta.icon + '</div>' +
        '<b>' + escapeHtml(meta.empty) + '</b>' +
        '<span>획득한 항목은 이곳에서 바로 확인할 수 있습니다.</span>' +
      '</div>';
    return;
  }

  grid.innerHTML = hero + rows.map(item => {
    const rarity = item.rarity || '보유';
    const state = item.state || '보유 중';
    const sourceClass = item.packed ? ' packed' : '';
    const sourceText = item.packed ? '포장' : (item.source === 'garage' ? '차량' : '보유');
    const model = item.model != null ? item.model : (item.meta && item.meta.model);
    const dataModel = personalStorageTab === 'skin' && item.actionable ? ' data-personal-model="' + escapeHtml(item.ownedId || item.id || '') + '"' : '';
    const vehicleAction = personalStorageTab === 'vehicle' && item.packed ? ' data-packed-vehicle="' + escapeHtml(String(item.id || '')) + '"' : '';
    const cosmeticAction = personalStorageTab === 'cosmetic' ? ' data-cosmetic-owned="' + escapeHtml(String(item.id || '')) + '"' : '';
    const furnitureAction = personalStorageTab === 'chair' && item.packed ? ' data-furniture-owned="' + escapeHtml(String(item.id || '')) + '"' : '';

    return '<button class="ck-asset-card' + sourceClass + '"' + dataModel + vehicleAction + cosmeticAction + furnitureAction + '>' +
      '<div class="ck-asset-image">' +
        personalStorageImage(item, personalStorageTab) +
        '<span class="ck-asset-source">' + escapeHtml(sourceText) + '</span>' +
      '</div>' +
      '<div class="ck-asset-body">' +
        '<div class="ck-asset-badges"><span>' + escapeHtml(String(rarity)) + '</span><span>' + escapeHtml(String(state)) + '</span></div>' +
        '<div class="ck-asset-name">' + escapeHtml(item.label || item.key || '알 수 없음') + '</div>' +
        '<div class="ck-asset-desc">' + escapeHtml(item.description || '보유 중인 항목입니다.') + '</div>' +
        '<div class="ck-asset-meta">' + personalStorageMetaRows(item) + '</div>' +
        (personalStorageTab === 'skin' && item.actionable ? '<div class="ck-asset-action">클릭하여 적용</div>' : '') +
        (personalStorageTab === 'vehicle' && item.packed ? '<div class="ck-asset-action">클릭하여 포장 해제 · 개인 차고 등록</div>' : '') +
        (personalStorageTab === 'cosmetic' ? '<div class="ck-asset-action">' + (String(item.state||'').includes('장착') ? '클릭하여 해제' : '클릭하여 장착') + '</div>' : '') +
        (personalStorageTab === 'chair' && item.packed ? '<div class="ck-asset-action">클릭하여 월드에 설치</div>' : '') +
        (personalStorageTab === 'chair' && !item.packed ? '<div class="ck-asset-action muted">설치됨 · 가까이에서 G로 회수</div>' : '') +
      '</div>' +
    '</button>';
  }).join('');

  if (personalStorageTab === 'vehicle') {
    grid.querySelectorAll('[data-packed-vehicle]').forEach(card => {
      card.onclick = () => {
        const ownedId = card.dataset.packedVehicle || '';
        if (!ownedId) return;
        fetch('https://cookie_admin/unpackLimitedVehicle', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({ownedId}) }).catch(()=>{});
      };
    });
  }

  if (personalStorageTab === 'skin') {
    grid.querySelectorAll('[data-personal-model]').forEach(card => {
      card.onclick = () => {
        const ownedId = card.dataset.personalModel || '';
        if (!ownedId) return;
        fetch('https://cookie_admin/applySkin', {
          method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({ ownedId })
        }).catch(() => {});
      };
    });
  }

  if (personalStorageTab === 'cosmetic') {
    grid.querySelectorAll('[data-cosmetic-owned]').forEach(card => {
      card.onclick = () => {
        const ownedId = String(card.dataset.cosmeticOwned || '');
        if (!ownedId) return;
        fetch('https://cookie_admin/toggleCosmetic', {
          method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({ownedId})
        }).catch(()=>{});
      };
    });
  }

  if (personalStorageTab === 'chair') {
    grid.querySelectorAll('[data-furniture-owned]').forEach(card => {
      card.onclick = () => {
        const ownedId = String(card.dataset.furnitureOwned || '');
        if (!ownedId) return;
        fetch('https://cookie_admin/placeFurniture', {
          method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({ownedId})
        }).catch(()=>{});
      };
    });
  }
}

function openPersonalStorageModal(tab) {
  personalStorageTab = PERSONAL_STORAGE_META[tab] ? tab : 'skin';
  const modal = document.getElementById('personalStorageModal');
  if (!modal) return;
  modal.classList.remove('hidden');
  renderPersonalStorageModal();

  fetch('https://cookie_admin/requestPersonalStorage', {
    method:'POST', headers:{'Content-Type':'application/json'}, body:'{}'
  }).catch(() => {});
}

function renderSkinList() {
  const grid = document.getElementById('skinGrid');
  const items = skinData[currentSkinTab] || [];
  let html =
    '<div class="ck-skin-card" data-model="">' +
      '<div class="ck-skin-card-img"><div class="ck-skin-card-default">↺</div></div>' +
      '<div class="ck-skin-card-body">' +
        '<div class="ck-skin-card-label">기본</div>' +
        '<div class="ck-skin-card-action gray">원래 모습</div>' +
      '</div>' +
    '</div>';

  if (items.length === 0) {
    const msg = currentSkinTab === 'private' ? '보유한 전용 스킨이 없습니다'
      : (currentSkinTab === 'rp' ? '적용 가능한 RP 스킨이 없습니다' : '등록된 스킨이 없습니다');
    html += '<div class="ck-skin-empty">' + msg + '</div>';
  } else {
    items.forEach((s) => {
      const img = s.image
        ? '<img src="' + escapeHtml(s.image) + '" alt="">'
        : '<div class="ck-skin-card-default">?</div>';
      html +=
        '<div class="ck-skin-card" data-model="' + escapeHtml(s.model_name) + '">' +
          '<div class="ck-skin-card-img">' + img + '</div>' +
          '<div class="ck-skin-card-body">' +
            '<div class="ck-skin-card-label">' + escapeHtml(s.label) + '</div>' +
            '<div class="ck-skin-card-action">적용하기</div>' +
          '</div>' +
        '</div>';
    });
  }

  grid.innerHTML = html;
  grid.querySelectorAll('.ck-skin-card').forEach((card) => {
    card.addEventListener('click', () => {
      const model = card.dataset.model;
      if (model === '') {
        fetch('https://cookie_admin/restoreSkin', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' }).catch(() => {});
      } else {
        fetch('https://cookie_admin/applySkin', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ model: model }) }).catch(() => {});
      }
      document.getElementById('skinModal').classList.add('hidden');
    });
  });
}

function openSkinModal(ctx) {
  const tabsEl = document.getElementById('skinTabs');
  const titleEl = document.getElementById('skinTitle');
  const descEl = document.getElementById('skinDesc');

  const tabs = (ctx === 'duty')
    ? [{ key: 'admin', label: '관업 스킨' }, { key: 'private', label: '내 전용' }]
    : [{ key: 'rp', label: 'RP 스킨' }];

  titleEl.textContent = (ctx === 'duty') ? '관업 스킨' : '내 스킨';
  descEl.textContent = (ctx === 'duty') ? '관리 중에만 적용됩니다' : '';

  tabsEl.innerHTML = (tabs.length > 1)
    ? tabs.map((t, i) =>
        '<button class="ck-skin-tab' + (i === 0 ? ' active' : '') + '" data-tab="' + t.key + '">' +
          escapeHtml(t.label) + '</button>').join('')
    : '';

  tabsEl.querySelectorAll('.ck-skin-tab').forEach((tab) => {
    tab.addEventListener('click', () => {
      currentSkinTab = tab.dataset.tab;
      tabsEl.querySelectorAll('.ck-skin-tab').forEach((t) => t.classList.toggle('active', t === tab));
      renderSkinList();
    });
  });

  currentSkinTab = tabs[0].key;
  renderSkinList();
  document.getElementById('skinModal').classList.remove('hidden');
}

document.getElementById('skinBtn').addEventListener('click', () => {
  if (currentState !== 'duty') {
    showToast('관리 시작 후 사용 가능합니다', true);
    return;
  }
  openSkinModal('duty');
});

document.getElementById('skinClose').addEventListener('click', () => {
  document.getElementById('skinModal').classList.add('hidden');
});

document.getElementById('skinPrev').addEventListener('click', () => {

});
document.getElementById('skinNext').addEventListener('click', () => {

});

document.addEventListener('keydown', (e) => {

  if ((e.key === 'Escape' || e.key === 'F3') && !document.getElementById('zonePreviewBar').classList.contains('hidden')) {
    e.preventDefault();
    e.stopPropagation();
    fetch('https://cookie_admin/closeZonePreview', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
    }).catch(() => {});
    return;
  }
  if (e.key === 'Escape' && !document.getElementById('zoneNewModal').classList.contains('hidden')) {
    e.preventDefault();
    e.stopPropagation();
    closeZoneNewModal();
    return;
  }
  if (e.key === 'Escape' && !document.getElementById('zoneDelModal').classList.contains('hidden')) {
    e.preventDefault();
    e.stopPropagation();
    closeZoneDelModal();
    return;
  }

  if ((e.key === 'Escape' || e.key === 'F3') && !document.getElementById('boxEdit').classList.contains('hidden')) {
    e.preventDefault();
    e.stopPropagation();

    const el = document.activeElement;
    if (el && el.tagName === 'INPUT' && el.type === 'number') {
      el.blur();
      return;
    }
    postSimple('hideBoxEditUI');
    return;
  }

  if (e.key === 'Escape' && !document.getElementById('pwModal').classList.contains('hidden')) {
    e.preventDefault();
    e.stopPropagation();
    closePwModal();
    return;
  }
  if (e.key === 'Escape' && !document.getElementById('pwResetModal').classList.contains('hidden')) {
    e.preventDefault();
    e.stopPropagation();
    closePwResetModal();
    return;
  }

  if (e.key === 'Escape' && !document.getElementById('grantModal').classList.contains('hidden')) {
    e.preventDefault();
    e.stopPropagation();
    closeGrantModal();
    return;
  }

  if (e.key === 'Escape' && !document.getElementById('onboardingModal').classList.contains('hidden')) {
    e.preventDefault();
    e.stopPropagation();
    closeOnboardingModal();
    return;
  }

  if (e.key === 'Escape' && !document.getElementById('weaponModal').classList.contains('hidden')) {
    e.preventDefault();
    e.stopPropagation();
    closeWeaponModal();
    return;
  }
  if (e.key === 'Escape' || e.key === 'F3') {
    e.preventDefault();
    closePanel();
  }
});

function vehMajorsInCatalog() {
  const set = {};
  vehicleCatalog.forEach((v) => { set[v.major || '기타'] = true; });

  const ordered = [];
  // 쿠키서버 전용 분류는 항상 가장 앞에 노출.
  ['일반차량', '한정차량', '뉴비차량'].forEach((m) => {
    if (set[m]) { ordered.push(m); delete set[m]; }
  });

  vehicleMajorOrder.forEach((m) => {
    if (set[m]) { ordered.push(m); delete set[m]; }
  });

  Object.keys(set).forEach((m) => ordered.push(m));
  return ordered;
}

function vehJobActive() { return vehJobFilter && vehJobFilter !== '전체'; }

const GARAGE_JOB = '쿠키 경찰국';
let lastVehMode = 'preview';
let factionsData = [];
let garageShop = {};
let vehGarageFilter = 'all';

function refreshGarageShop() {
  const gf = (factionsData || []).find((f) => f.name === GARAGE_JOB);
  garageShop = {};
  if (gf) (gf.shop || []).forEach((s) => { garageShop[s.model] = s; });
  return gf;
}

function isRegistered(model) { return !!garageShop[model]; }

function isOnDisplay(model) {
  const s = garageShop[model];
  return !!s && !(s.active === 0 || s.active === false);
}

function renderGarageStat() {
  const stat = document.getElementById('vehGarageStat');
  const filt = document.getElementById('vehGarageFilter');
  const on = (vehSpawnMode === 'lspd');
  if (stat) stat.classList.toggle('hidden', !on);
  if (filt) filt.classList.toggle('hidden', !on);
  if (!on || !stat || !filt) return;

  refreshGarageShop();
  const all = vehicleCatalog.filter((v) => v.job === GARAGE_JOB);
  const cntOn = all.filter((v) => isOnDisplay(v.model)).length;
  const cntOff = all.filter((v) => isRegistered(v.model) && !isOnDisplay(v.model)).length;
  const cntNone = all.length - cntOn - cntOff;

  stat.innerHTML =
    '<div class="ck-gstat-item"><span>' + escapeHtml(GARAGE_JOB) + ' 차량 총</span><b>' + all.length + '대</b></div>' +
    '<div class="ck-gstat-item"><span>전시 중</span><b class="ck-gstat-ok">' + cntOn + '대</b></div>' +
    '<div class="ck-gstat-item"><span>비활성</span><b class="ck-gstat-off">' + cntOff + '대</b></div>' +
    '<div class="ck-gstat-item"><span>미등록</span><b class="ck-gstat-no">' + cntNone + '대</b></div>';

  filt.innerHTML = '';
  [['all', '전체'], ['unreg', '미등록'], ['reg', '전시 중']].forEach((p) => {
    const c = document.createElement('span');
    c.className = 'ck-chip' + (p[0] === vehGarageFilter ? ' active' : '');
    c.textContent = p[1];
    c.addEventListener('click', () => { vehGarageFilter = p[0]; renderGarageStat(); renderVehList(); });
    filt.appendChild(c);
  });

}

function shootThumb(model, name) {
  if (currentState !== 'duty') { showToast('관리 업무를 시작해야 합니다', true); return; }
  doPreviewSpawn(model, name || model);
  showToast('각도를 잡고 [이 화면을 썸네일로 저장]을 누르세요', false);
}

function updateFilterVisibility() {
  const jobOn = vehJobActive();
  const garageMode = (vehSpawnMode === 'lspd');
  ['vehMajorLab', 'vehMajorChips', 'vehBrandLab', 'vehBrandChips'].forEach((id) => {
    const el = document.getElementById(id);
    if (el) el.classList.toggle('hidden', jobOn || garageMode);
  });
  ['vehJobLab', 'vehJobChips'].forEach((id) => {
    const el = document.getElementById(id);
    if (el) el.classList.toggle('hidden', garageMode);
  });
}

const JOB_PREF_ORDER = ['쿠키 경찰국', '택시', '트럭커'];
function vehJobsInCatalog() {
  const set = {};
  vehicleCatalog.forEach((v) => { if (v.job) set[v.job] = true; });
  const ordered = [];
  JOB_PREF_ORDER.forEach((j) => { if (set[j]) { ordered.push(j); delete set[j]; } });
  Object.keys(set).forEach((j) => ordered.push(j));
  return ordered;
}

function renderJobChips() {
  const wrap = document.getElementById('vehJobChips');
  if (!wrap) return;
  wrap.innerHTML = '';
  const jobs = ['전체'].concat(vehJobsInCatalog());
  jobs.forEach((j) => {
    const c = document.createElement('span');
    c.className = 'ck-chip' + (j === vehJobFilter ? ' active' : '');
    c.textContent = j;
    c.addEventListener('click', () => {
      vehJobFilter = j; vehBrandFilter = '전체';
      renderJobChips(); renderVehBrandChips(); renderVehList();
    });
    wrap.appendChild(c);
  });
  updateFilterVisibility();
}

function renderMajorChips() {
  const wrap = document.getElementById('vehMajorChips');
  if (!wrap) return;
  wrap.innerHTML = '';
  vehMajorsInCatalog().forEach((m) => {
    const c = document.createElement('span');
    c.className = 'ck-chip' + (m === vehMajorFilter ? ' active' : '');
    c.textContent = m;
    c.addEventListener('click', () => {
      vehMajorFilter = m; vehBrandFilter = '전체';
      renderMajorChips(); renderVehBrandChips(); renderVehList();
    });
    wrap.appendChild(c);
  });
}

function vehBrandsInCatalog() {
  const set = {};
  const jobOn = vehJobActive();
  vehicleCatalog.forEach((v) => {
    if (jobOn) { if (v.job !== vehJobFilter) return; }
    else if (vehMajorFilter && (v.major || '기타') !== vehMajorFilter) return;
    set[v.brand || '기타'] = true;
  });
  const ordered = [];
  vehicleBrandOrder.forEach((b) => { if (set[b]) { ordered.push(b); delete set[b]; } });
  Object.keys(set).forEach((b) => ordered.push(b));
  return ordered;
}

function setupVehicleTabs() {
  const rs = document.getElementById('rtabVehSpawn');
  const re = document.getElementById('rtabVehExhibit');
  if (rs) rs.classList.toggle('hidden', !vehiclePerms.spawn);
  if (re) re.classList.toggle('hidden', !vehiclePerms.exhibit);
  vehSpawnMode = 'preview';
  vehBrandFilter = '전체';
  vehJobFilter = '전체';
  exhibitPick = null;
  currentTestName = '';
  previewUiOn = false;
  overlay.classList.remove('preview-mode');
  const majors = vehMajorsInCatalog();
  // 일반차량이 있으면 관리자 차량창 첫 화면을 일반차량으로 연다.
  vehMajorFilter = majors.includes('일반차량')
    ? '일반차량'
    : (majors.length ? majors[0] : '');
  document.querySelectorAll('.ck-veh-tgt').forEach((b) => b.classList.toggle('active', b.dataset.t === 'preview'));
  const sel = document.getElementById('vehTargetSel'); if (sel) sel.classList.add('hidden');
  const vs = document.getElementById('vehSearch'); if (vs) vs.value = '';
  const es = document.getElementById('exSearch'); if (es) es.value = '';
  const ef = document.getElementById('exForm'); if (ef) ef.classList.add('hidden');
  updateTestBar();
  renderJobChips();
  renderMajorChips();
  renderVehBrandChips();
  renderVehTargetOptions();
  renderVehList();
  renderExhibitPick();
}

function renderVehBrandChips() {
  const wrap = document.getElementById('vehBrandChips');
  if (!wrap) return;
  wrap.innerHTML = '';
  const brands = ['전체'].concat(vehBrandsInCatalog());
  brands.forEach((b) => {
    const c = document.createElement('span');
    c.className = 'ck-chip' + (b === vehBrandFilter ? ' active' : '');
    c.textContent = b;
    c.addEventListener('click', () => { vehBrandFilter = b; renderVehBrandChips(); renderVehList(); });
    wrap.appendChild(c);
  });
}

function renderVehTargetOptions() {
  const sel = document.getElementById('vehTargetSel');
  if (!sel) return;
  const prev = sel.value;
  sel.innerHTML = '';
  currentPlayers.forEach((p) => {
    const o = document.createElement('option');
    o.value = p.serverId;
    o.textContent = '[' + p.serverId + '] ' + (p.nickname || p.name || p.realname || ('#' + p.serverId));
    sel.appendChild(o);
  });
  if (prev) sel.value = prev;
}

function vehMatch(v, q) {
  if (!q) return true;
  q = q.toLowerCase();
  return (v.name || '').toLowerCase().indexOf(q) !== -1
    || (v.model || '').toLowerCase().indexOf(q) !== -1
    || (v.brand || '').toLowerCase().indexOf(q) !== -1;
}

function renderVehList() {
  const list = document.getElementById('vehList');
  if (!list) return;

  if (vehSpawnMode !== lastVehMode) {
    if (vehSpawnMode === 'lspd') {
      vehJobFilter = GARAGE_JOB;
      vehBrandFilter = '전체';
      vehMajorFilter = '';
    } else if (lastVehMode === 'lspd') {
      vehJobFilter = '전체';
      vehBrandFilter = '전체';
    }
    lastVehMode = vehSpawnMode;
    vehGarageFilter = 'all';
    renderJobChips();
    renderVehBrandChips();
    renderGarageStat();
  }

  const q = (document.getElementById('vehSearch').value || '').trim();
  const jobOn = vehJobActive();
  const garageMode = (vehSpawnMode === 'lspd');
  const arr = vehicleCatalog.filter((v) =>
    (jobOn ? (v.job === vehJobFilter) : (!vehMajorFilter || (v.major || '기타') === vehMajorFilter)) &&
    (vehBrandFilter === '전체' || v.brand === vehBrandFilter) && vehMatch(v, q) &&

    (!garageMode || vehGarageFilter === 'all'
      || (vehGarageFilter === 'reg' ? isOnDisplay(v.model) : !isRegistered(v.model))));
  arr.sort((a, b) => (a.name || '').localeCompare(b.name || ''));
  const shown = arr.slice(0, 300);
  list.innerHTML = '';
  if (!arr.length) { list.innerHTML = '<div class="ck-veh-empty">검색 결과가 없습니다</div>'; return; }
  const label = vehSpawnMode === 'preview' ? '미리보기'
    : vehSpawnMode === 'self' ? '시승'
    : vehSpawnMode === 'lspd' ? '차량 등록'
    : '지급';
  const onDuty = currentState === 'duty';
  if (!onDuty) {
    const notice = document.createElement('div');
    notice.className = 'ck-veh-notice';
    notice.textContent = '⚠ 관리 업무를 시작해야 차량을 사용할 수 있습니다';
    list.appendChild(notice);
  }
  shown.forEach((v) => {
    const row = document.createElement('div');
    row.className = 'ck-veh-row';
    const info = document.createElement('div'); info.className = 'ck-veh-info';
    const nm = document.createElement('div'); nm.className = 'ck-veh-name';
    if (v.isNew) {
      const badge = document.createElement('span'); badge.className = 'ck-veh-new'; badge.textContent = 'NEW';
      nm.appendChild(badge);
    }

    const shopEntry = garageMode ? garageShop[v.model] : null;
    const shownName = (shopEntry && shopEntry.label) ? shopEntry.label : (v.name || v.model);
    nm.appendChild(document.createTextNode(shownName));

    if (garageMode && isRegistered(v.model)) {
      const rb = document.createElement('span');
      const displayed = isOnDisplay(v.model);
      rb.className = displayed ? 'ck-veh-reg' : 'ck-veh-off';
      rb.textContent = displayed ? '전시 중' : '비활성';
      nm.appendChild(rb);
    }
    info.appendChild(nm);
    const btn = document.createElement('button'); btn.className = 'ck-veh-spawn' + (onDuty ? '' : ' ck-disabled');
    btn.textContent = label;
    btn.addEventListener('click', () => {
      if (!onDuty) { showToast('관리 업무를 시작해야 사용할 수 있습니다', true); return; }
      if (vehSpawnMode === 'preview') doPreviewSpawn(v.model, v.name || v.model);
      else if (vehSpawnMode === 'self') doTestSpawn(v.model, v.name || v.model);
      else if (vehSpawnMode === 'lspd') openVehRegisterDialog(v.model, v.name || v.model);
      else doSpawn(v.model);
    });

    let shotBtn = null;
    if (garageMode && isRegistered(v.model)) {
      shotBtn = document.createElement('button');
      shotBtn.className = 'ck-veh-shot' + (onDuty ? '' : ' ck-disabled');
      shotBtn.textContent = '썸네일';
      shotBtn.addEventListener('click', () => {
        if (!onDuty) { showToast('관리 업무를 시작해야 사용할 수 있습니다', true); return; }
        shootThumb(v.model, v.name || v.model);
      });
    }

    if (vehSpawnMode !== 'preview') {
      const pv = document.createElement('button'); pv.className = 'ck-veh-prev' + (onDuty ? '' : ' ck-disabled');
      pv.textContent = '미리보기';
      pv.addEventListener('click', () => {
        if (!onDuty) { showToast('관리 업무를 시작해야 사용할 수 있습니다', true); return; }
        doPreviewSpawn(v.model, v.name || v.model);
      });
      row.appendChild(info);
      if (shotBtn) row.appendChild(shotBtn);
      row.appendChild(pv);
      row.appendChild(btn);
    } else {
      row.appendChild(info); row.appendChild(btn);
    }
    list.appendChild(row);
  });
  if (arr.length > shown.length) {
    const more = document.createElement('div'); more.className = 'ck-veh-empty';
    more.textContent = '외 ' + (arr.length - shown.length) + '대 — 검색으로 좁혀주세요';
    list.appendChild(more);
  }
}

function doSpawn(model) {
  let targetServerId = null;
  if (vehSpawnMode === 'target') {
    const sel = document.getElementById('vehTargetSel');
    targetServerId = sel && sel.value ? parseInt(sel.value, 10) : null;
    if (!targetServerId) { showToast('대상을 선택하세요', true); return; }
  }
  fetch('https://cookie_admin/spawnVehicle', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: model, targetServerId: targetServerId }),
  }).catch(() => {});
}

function doTestSpawn(model, name) {
  currentTestName = name || model;
  updateTestBar();
  fetch('https://cookie_admin/testSpawnVehicle', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: model }),
  }).catch(() => {});
}

function doReturn() {
  currentTestName = '';
  updateTestBar();
  fetch('https://cookie_admin/returnTestVehicle', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
  }).catch(() => {});
}

function doPreviewSpawn(model, name) {
  if (!previewUiOn) {
    previewUiOn = true;
    overlay.classList.add('preview-mode');
    fetch('https://cookie_admin/enterPreview', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
    }).catch(() => {});
  }
  currentPreviewModel = model;
  currentTestName = name || model;
  updateTestBar();
  fetch('https://cookie_admin/previewSpawn', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: model }),
  }).catch(() => {});
}

function resizeAndSaveVehShot(model, dataUrl) {
  if (!model || !dataUrl) return;
  const img = new Image();
  img.onload = () => {
    const W = 480, H = 270;
    const cv = document.createElement('canvas');
    cv.width = W; cv.height = H;
    const ctx = cv.getContext('2d');

    const r = Math.max(W / img.width, H / img.height);
    const w = img.width * r, h = img.height * r;
    ctx.drawImage(img, (W - w) / 2, (H - h) / 2, w, h);

    const saved = cv.toDataURL('image/jpeg', 0.72);
    exhibitImageByModel[model] = saved;
    fetch('https://cookie_admin/saveVehImage', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: model, image: saved }),
    }).catch(() => {});
    if (exhibitPick && exhibitPick.model === model) {
      const ep = document.getElementById('exPhotoPreview');
      if (ep) { ep.src = saved; ep.classList.remove('hidden'); }
      showToast('차량 사진을 저장했습니다', false);
      setTimeout(() => fetch('https://cookie_admin/requestExhibitList', {
        method:'POST', headers:{'Content-Type':'application/json'}, body:'{}'
      }).catch(()=>{}), 120);
    }
  };
  img.onerror = () => showToast('이미지 처리에 실패했습니다', true);
  img.src = dataUrl;
}

let facPreviewReturn = false;

function facPreview(model, name) {
  const c = document.getElementById('mfConsole');
  if (c) c.classList.add('hidden');
  facPreviewReturn = true;

  overlay.classList.add('fac-preview');

  const bar = document.getElementById('facPrevBar');
  const nm = document.getElementById('facPrevName');
  if (nm) nm.textContent = name || model;
  if (bar) bar.classList.remove('hidden');

  if (!previewUiOn) {
    previewUiOn = true;
    overlay.classList.add('preview-mode');
    fetch('https://cookie_admin/enterPreview', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
    }).catch(() => {});
  }
  currentPreviewModel = model;
  currentTestName = name || model;
  updateTestBar();
  fetch('https://cookie_admin/facPreviewVehicle', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: model }),
  }).catch(() => {});
}

function exitPreviewUi() {
  if (!previewUiOn) return;
  previewUiOn = false;
  overlay.classList.remove('preview-mode');
  currentTestName = '';
  updateTestBar();
  fetch('https://cookie_admin/exitPreview', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
  }).catch(() => {});

  overlay.classList.remove('fac-preview');
  overlay.classList.remove('exhibit-photo-mode');
  exhibitPhotoMode = false;
  const ecap = document.getElementById('exPhotoCapture');
  if (ecap) ecap.classList.add('hidden');
  const fbar = document.getElementById('facPrevBar');
  if (fbar) fbar.classList.add('hidden');

  if (facPreviewReturn) {
    facPreviewReturn = false;
    const c = document.getElementById('mfConsole');
    if (c) c.classList.remove('hidden');
  }
}

function updateTestBar() {
  const bar = document.getElementById('vehTestBar');
  if (!bar) return;

  const shot = document.getElementById('vehShotBtn');
  if (shot) shot.classList.toggle('hidden', !(previewUiOn && currentPreviewModel));

  const inPreview = previewUiOn;
  const show = inPreview || (vehSpawnMode === 'self' && !!currentTestName);
  bar.classList.toggle('hidden', !show);
  const nm = document.getElementById('vehTestName');
  if (nm) nm.textContent = currentTestName || '-';
  const rb = document.getElementById('vehReturnBtn');
  if (rb) rb.textContent = previewUiOn ? '닫기' : '반납';
  const cc = document.getElementById('vehCamCtl');
  if (cc) cc.classList.toggle('hidden', !inPreview);
}

function factionFromTarget(key) {
  if (!String(key).startsWith('faction:')) return null;
  const id = Number(String(key).split(':')[1]);
  return exhibitFactions.find((f) => Number(f.id) === id) || null;
}

function currentExFaction() {
  return factionFromTarget(exhibitAddTarget);
}

function renderExhibitTabs() {
  const render = (boxId, selected, onPick) => {
    const box = document.getElementById(boxId);
    if (!box) return;
    box.innerHTML = '';

    const add = (key, label) => {
      const b = document.createElement('button');
      b.className = 'ck-ex-tab' + (selected === key ? ' active' : '');
      b.textContent = label;
      b.onclick = () => onPick(key);
      box.appendChild(b);
    };

    add('citizen', '시민차량');
    add('limited', '한정차량');
    exhibitFactions.forEach((f) => add('faction:' + f.id, f.name));
  };

  render('exAddTabs', exhibitAddTarget, (key) => {
    exhibitAddTarget = key;
    exhibitPick = null;
    const form = document.getElementById('exForm');
    if (form) form.classList.add('hidden');
    renderExhibitTabs();
  });

  render('exListTabs', exhibitListTab, (key) => {
    exhibitListTab = key;
    renderExhibitTabs();
    renderExhibitCurrentList();
  });
}

function renderExhibitPick() {
  const box=document.getElementById('exPick'); if(!box)return;
  const q=(document.getElementById('exSearch').value||'').trim(); box.innerHTML='';
  if(!q){box.innerHTML='<div class="ck-veh-empty">위에서 차량을 검색하세요</div>';return;}
  const arr=vehicleCatalog.filter((v)=>vehMatch(v,q)).slice(0,40);
  if(!arr.length){box.innerHTML='<div class="ck-veh-empty">검색 결과가 없습니다</div>';return;}
  arr.forEach((v)=>{
    const row=document.createElement('div');row.className='ck-veh-row';
    const info=document.createElement('div');info.className='ck-veh-info';
    const nm=document.createElement('div');nm.className='ck-veh-name';nm.textContent=v.name||v.model;
    const meta=document.createElement('div');meta.className='ck-veh-meta';meta.textContent=(v.name||v.model)+' · '+v.model;
    info.append(nm,meta);
    const prev=document.createElement('button');prev.className='ck-veh-prev';prev.textContent='미리보기';
    prev.onclick=()=>openExhibitPhotoPreview(v.model,v.name||v.model);
    const btn=document.createElement('button');btn.className='ck-veh-spawn ck-veh-pickbtn';btn.textContent='차량 등록';
    btn.onclick=()=>pickExhibit(v);
    row.append(info,prev,btn);box.appendChild(row);
  });
}

function pickExhibit(v) {
  exhibitPick = v;
  const fac = currentExFaction();
  const limitedMode = exhibitAddTarget === 'limited';
  const existing = limitedMode
    ? exhibitLimitedRows.find((x) => x.model === v.model)
    : (fac ? ((fac.shop || []).find((x) => x.model === v.model))
           : exhibitCitizenRows.find((x) => x.model === v.model));

  document.getElementById('exModelName').textContent = v.name || v.model;
  document.getElementById('exModelCode').textContent = '(' + v.model + ')';
  document.getElementById('exDisplayName').value =
    existing ? (existing.label || existing.display_name || v.name || v.model) : (v.name || v.model);
  document.getElementById('exPrice').value = existing ? (existing.price || 0) : (v.price || 0);
  document.getElementById('exMinGrade').value = existing ? (existing.min_grade || 0) : 0;
  document.getElementById('exSpec').value = existing ? (existing.spec || '') : '';

  document.getElementById('exPriceFields').classList.toggle('hidden', limitedMode);
  document.getElementById('exFactionFields').classList.toggle('hidden', !fac);
  document.getElementById('exCitizenSpec').classList.toggle('hidden', !!fac || limitedMode);

  const img = (existing && existing.image) || exhibitImageByModel[v.model] || '';
  const ip = document.getElementById('exPhotoPreview');
  if (img) { ip.src = img; ip.classList.remove('hidden'); }
  else { ip.src = ''; ip.classList.add('hidden'); }

  document.getElementById('exSubmit').textContent = existing ? '저장' : '차량 등록';
  document.getElementById('exForm').classList.remove('hidden');
}

function openExhibitPhotoPreview(model, name) {
  exhibitPhotoMode = true;
  doPreviewSpawn(model, name || model);
  overlay.classList.add('exhibit-photo-mode');

  const cap = document.getElementById('exPhotoCapture');
  const nm = document.getElementById('exCapName');
  if (nm) nm.textContent = name || model;
  if (cap) cap.classList.remove('hidden');

  const a = document.getElementById('exCapAngle');
  const d = document.getElementById('exCapDist');
  const h = document.getElementById('exCapHeight');
  if (a) a.value = '210';
  if (d) d.value = '5.2';
  if (h) h.value = '1.4';
  syncExCapture(true);
}

function closeExhibitPhotoPreview() {
  exhibitPhotoMode = false;
  overlay.classList.remove('exhibit-photo-mode');
  const cap = document.getElementById('exPhotoCapture');
  if (cap) cap.classList.add('hidden');
  exitPreviewUi();
}

function syncExCapture(force) {
  const a = Number(document.getElementById('exCapAngle').value || 210);
  const d = Number(document.getElementById('exCapDist').value || 5.2);
  const h = Number(document.getElementById('exCapHeight').value || 1.4);
  document.getElementById('exCapAngleV').textContent = Math.round(a) + '°';
  document.getElementById('exCapDistV').textContent = d.toFixed(1);
  document.getElementById('exCapHeightV').textContent = h.toFixed(1);
  fetch('https://cookie_admin/previewSet', {
    method:'POST', headers:{'Content-Type':'application/json'},
    body:JSON.stringify({angle:a,distance:d,height:h,manual:true})
  }).catch(()=>{});
}

['exCapAngle','exCapDist','exCapHeight'].forEach((id) => {
  const el = document.getElementById(id);
  if (el) el.addEventListener('input', () => syncExCapture(false));
});
const exCapClose = document.getElementById('exCapClose');
if (exCapClose) exCapClose.addEventListener('click', closeExhibitPhotoPreview);
const exCapSave = document.getElementById('exCapSave');
if (exCapSave) exCapSave.addEventListener('click', () => {
  if (!currentPreviewModel) return;
  fetch('https://cookie_admin/captureVehImage', {
    method:'POST', headers:{'Content-Type':'application/json'},
    body:JSON.stringify({model:currentPreviewModel})
  }).catch(()=>{});
});

const exPreviewBtn=document.getElementById('exPreviewBtn');
if(exPreviewBtn)exPreviewBtn.onclick=()=>{if(exhibitPick)openExhibitPhotoPreview(exhibitPick.model,exhibitPick.name||exhibitPick.model)};

function submitExhibit() {
  if (!exhibitPick) return;
  const fac = currentExFaction();
  const limitedMode = exhibitAddTarget === 'limited';
  const displayName = (document.getElementById('exDisplayName').value || '').trim() ||
                      exhibitPick.name || exhibitPick.model;

  if (limitedMode) {
    fetch('https://cookie_admin/limitedVehicleSave', {
      method:'POST', headers:{'Content-Type':'application/json'},
      body:JSON.stringify({ model:exhibitPick.model, label:displayName })
    }).catch(()=>{});
  } else if (fac) {
    const existing = (fac.shop || []).find((x) => x.model === exhibitPick.model);
    fetch('https://cookie_admin/factionShopSave', {
      method:'POST', headers:{'Content-Type':'application/json'},
      body:JSON.stringify({
        id:existing ? existing.id : 0, factionId:fac.id, model:exhibitPick.model,
        label:displayName, price:parseInt(document.getElementById('exPrice').value,10)||0,
        minGrade:parseInt(document.getElementById('exMinGrade').value,10)||0, active:1
      })
    }).catch(()=>{});
  } else {
    fetch('https://cookie_admin/exhibitAdd', {
      method:'POST', headers:{'Content-Type':'application/json'},
      body:JSON.stringify({
        model:exhibitPick.model, brand:'일반', displayName:displayName,
        price:parseInt(document.getElementById('exPrice').value,10)||0,
        category:exhibitPick.category,
        spec:(document.getElementById('exSpec').value||'').trim(),
        image:exhibitImageByModel[exhibitPick.model]||''
      })
    }).catch(()=>{});
  }

  exhibitListTab = exhibitAddTarget;
  exhibitPick = null;
  document.getElementById('exForm').classList.add('hidden');
  document.getElementById('exSearch').value = '';
  renderExhibitTabs();
  renderExhibitPick();
  setTimeout(() => fetch('https://cookie_admin/requestExhibitList', {
    method:'POST', headers:{'Content-Type':'application/json'}, body:'{}'
  }).catch(()=>{}), 180);
}

function renderExhibitCurrentList() {
  const fac = factionFromTarget(exhibitListTab);
  const limitedMode = exhibitListTab === 'limited';
  const list = limitedMode ? exhibitLimitedRows : (fac ? (fac.shop || []) : exhibitCitizenRows);
  const box = document.getElementById('exList');
  if (!box) return;

  box.innerHTML = '';
  if (!list.length) {
    box.innerHTML = '<div class="ck-veh-empty">등록된 차량이 없습니다</div>';
    return;
  }

  list.forEach((r) => {
    const row = document.createElement('div'); row.className = 'ck-ex-row';
    if (r.image) {
      exhibitImageByModel[r.model] = r.image;
      const im = document.createElement('img'); im.className = 'ck-ex-row-thumb'; im.src = r.image;
      row.appendChild(im);
    }

    const info = document.createElement('div'); info.className = 'ck-veh-info';
    const nm = document.createElement('div'); nm.className = 'ck-veh-name';
    nm.textContent = r.label || r.display_name || r.model;
    const meta = document.createElement('div'); meta.className = 'ck-veh-meta';
    if (limitedMode) meta.textContent = '한정 차량 · ' + r.model;
    else if (fac) meta.textContent = '최소 계급 ' + Number(r.min_grade || 0) + ' · ' +
                                    Number(r.price || 0).toLocaleString() + '원 · ' + r.model;
    else meta.textContent = Number(r.price || 0).toLocaleString() + '원 · ' + r.model;
    info.append(nm, meta);

    const prev = document.createElement('button'); prev.className = 'ck-veh-prev'; prev.textContent = '이미지';
    prev.onclick = () => openExhibitPhotoPreview(r.model, r.label || r.display_name || r.model);

    const edit = document.createElement('button'); edit.className = 'ck-veh-spawn'; edit.textContent = '수정';
    edit.onclick = () => {
      exhibitAddTarget = exhibitListTab;
      renderExhibitTabs();
      pickExhibit(vehicleCatalog.find((x) => x.model === r.model) ||
        { model:r.model, name:r.label || r.display_name || r.model, price:r.price || 0 });
    };

    const del = document.createElement('button'); del.className = 'ck-ex-del'; del.textContent = '삭제';
    del.onclick = () => {
      const url = limitedMode ? 'limitedVehicleDelete' : (fac ? 'factionShopDelete' : 'exhibitRemove');
      fetch('https://cookie_admin/' + url, {
        method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({id:r.id})
      }).catch(()=>{});
      setTimeout(() => fetch('https://cookie_admin/requestExhibitList', {
        method:'POST', headers:{'Content-Type':'application/json'}, body:'{}'
      }).catch(()=>{}), 180);
    };

    row.append(info, prev, edit, del);
    box.appendChild(row);
  });
}

function renderExhibitList(list, limited, factions) {
  exhibitCitizenRows = list || [];
  exhibitLimitedRows = limited || [];
  exhibitFactions = factions || [];

  exhibitCitizenRows.forEach((r) => { if (r.image) exhibitImageByModel[r.model] = r.image; });
  exhibitLimitedRows.forEach((r) => { if (r.image) exhibitImageByModel[r.model] = r.image; });
  exhibitFactions.forEach((f) => (f.shop || []).forEach((r) => {
    if (r.image) exhibitImageByModel[r.model] = r.image;
  }));

  for (const keyName of ['add','list']) {
    const key = keyName === 'add' ? exhibitAddTarget : exhibitListTab;
    if (String(key).startsWith('faction:')) {
      const id = Number(String(key).split(':')[1]);
      if (!exhibitFactions.some((f) => Number(f.id) === id)) {
        if (keyName === 'add') exhibitAddTarget = 'citizen';
        else exhibitListTab = 'citizen';
      }
    }
  }
  renderExhibitTabs();
  renderExhibitCurrentList();
}

let vrModel = null;

function openVehRegisterDialog(model, name) {
  const gf = refreshGarageShop();
  if (!gf) { showToast(GARAGE_JOB + ' 조직을 찾을 수 없습니다', true); return; }

  vrModel = { id: gf.id, model: model, name: name || model };
  const exist = garageShop[model];

  document.getElementById('vrName').textContent = (name || model) + '  ' + model;

  document.getElementById('vrLabel').value = exist ? (exist.label || name || model) : (name || model);
  document.getElementById('vrPrice').value = exist ? (exist.price || '') : '';
  document.getElementById('vrOk').textContent = exist ? '저장' : '등록';

  const aw = document.getElementById('vrActiveWrap');
  const dl = document.getElementById('vrDel');
  if (aw) aw.classList.toggle('hidden', !exist);
  if (dl) dl.classList.toggle('hidden', !exist);
  if (exist) {
    const isOn = !(exist.active === 0 || exist.active === false);
    document.getElementById('vrActive').value = isOn ? '1' : '0';
  }

  document.getElementById('vrModal').classList.remove('hidden');
  document.getElementById('vrPrice').focus();
}

function closeVehRegisterDialog() {
  document.getElementById('vrModal').classList.add('hidden');
  vrModel = null;
}

function submitVehRegister() {
  if (!vrModel) return;
  const price = parseInt(document.getElementById('vrPrice').value, 10) || 0;
  const label = document.getElementById('vrLabel').value.trim();
  if (price <= 0) { showToast('가격을 입력하세요', true); return; }
  if (label.length < 1) { showToast('표시명을 입력하세요', true); return; }
  const exist = garageShop[vrModel.model];
  const activeSel = document.getElementById('vrActive');
  const active = exist ? (activeSel && activeSel.value === '0' ? 0 : 1) : 1;

  fetch('https://cookie_admin/factionShopSave', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      id: exist ? exist.id : 0,
      factionId: vrModel.id,
      model: vrModel.model,
      label: label,
      price: price,
      minGrade: exist ? (exist.min_grade || 0) : 0,
      active: active,
    }),
  }).catch(() => {});
  closeVehRegisterDialog();
}

function updateLspdBar() {

  const show = vehSpawnMode === 'lspd';
  if (show) {
    fetch('https://cookie_admin/requestFactionList', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
    }).catch(() => {});
  }
  renderGarageStat();
}

function renderLspdFleet(list) {
  fleetModels = {};
  (list || []).forEach((r) => { if (r.model) fleetModels[r.model] = true; });
  renderGarageStat();
  renderVehList();
}

function renderLspdFleetLegacy(list) {
  const box = document.getElementById('lspdFleetList');
  const cnt = document.getElementById('lspdCount');
  if (cnt) cnt.textContent = list.length;
  if (!box) return;
  box.innerHTML = '';
  if (!list.length) { box.innerHTML = '<div class="ck-veh-empty">차고에 등록된 차량이 없습니다</div>'; return; }
  list.forEach((r) => {
    const row = document.createElement('div'); row.className = 'ck-ex-row';
    const info = document.createElement('div'); info.className = 'ck-veh-info';
    const nm = document.createElement('div'); nm.className = 'ck-veh-name'; nm.textContent = r.name || r.model;
    const meta = document.createElement('div'); meta.className = 'ck-veh-meta';
    meta.textContent = (r.brand || '기타') + ' · ' + (r.plate || '') + ' · ' + r.model;
    info.appendChild(nm); info.appendChild(meta);
    const btn = document.createElement('button'); btn.className = 'ck-ex-del'; btn.textContent = '제거';
    btn.addEventListener('click', () => {
      fetch('https://cookie_admin/lspdFleetRemove', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: r.id }),
      }).catch(() => {});
    });
    row.appendChild(info); row.appendChild(btn);
    box.appendChild(row);
  });
}

(function bindVehicleUI() {
  const vs = document.getElementById('vehSearch');
  if (vs) vs.addEventListener('input', renderVehList);
  document.querySelectorAll('.ck-veh-tgt').forEach((b) => {
    b.addEventListener('click', () => {
      const newMode = b.dataset.t;
      if (newMode !== 'preview') exitPreviewUi();
      vehSpawnMode = newMode;
      document.querySelectorAll('.ck-veh-tgt').forEach((x) => x.classList.toggle('active', x === b));
      const sel = document.getElementById('vehTargetSel');
      if (sel) sel.classList.toggle('hidden', vehSpawnMode !== 'target');
      if (vehSpawnMode === 'target') renderVehTargetOptions();
      updateTestBar();
      updateLspdBar();
      renderVehList();
    });
  });
  const retBtn = document.getElementById('vehReturnBtn');
  if (retBtn) retBtn.addEventListener('click', () => {
    if (previewUiOn) exitPreviewUi();
    else doReturn();
  });
  const seedBtn = document.getElementById('lspdSeedBtn');
  if (seedBtn) seedBtn.addEventListener('click', () => {
    if (currentState !== 'duty') { showToast('관리 업무를 시작해야 사용할 수 있습니다', true); return; }
    showToast('라인업 일괄 추가 중…', false);
    fetch('https://cookie_admin/lspdFleetSeed', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
    }).catch(() => {});
  });
  document.querySelectorAll('.ck-cc-btn').forEach((b) => {
    b.addEventListener('click', () => {
      fetch('https://cookie_admin/previewCam', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: b.dataset.cc }),
      }).then((r) => r.json()).then((res) => {
        if (b.dataset.cc === 'auto') {
          const el = document.getElementById('ccAuto');
          if (el) el.classList.toggle('on', !!(res && res.auto));
        }
      }).catch(() => {});
    });
  });
  const colorsWrap = document.getElementById('vehColors');
  if (colorsWrap) {
    PREVIEW_COLORS.forEach((c) => {
      const s = document.createElement('span');
      s.className = 'ck-cc-color';
      s.style.background = 'rgb(' + c[1] + ',' + c[2] + ',' + c[3] + ')';
      s.title = c[0];
      s.addEventListener('click', () => {
        fetch('https://cookie_admin/previewColor', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ r: c[1], g: c[2], b: c[3] }),
        }).catch(() => {});
      });
      colorsWrap.appendChild(s);
    });
  }
  const tdBtn = document.getElementById('vehTestDriveBtn');
  if (tdBtn) tdBtn.addEventListener('click', () => {
    if (!currentPreviewModel) return;
    fetch('https://cookie_admin/startTestDrive', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: currentPreviewModel }),
    }).catch(() => {});
  });
  const es = document.getElementById('exSearch');
  if (es) es.addEventListener('input', renderExhibitPick);
  const exCancel = document.getElementById('exCancel');
  if (exCancel) exCancel.addEventListener('click', () => {
    exhibitPick = null;
    document.getElementById('exForm').classList.add('hidden');
  });
  const exSubmit = document.getElementById('exSubmit');
  if (exSubmit) exSubmit.addEventListener('click', submitExhibit);
})();



// 시스템 관리 > 낚시
let fishingSystemData = null;
let miningSystemData = null;
let miningSystemError = '';
let miningSystemRequestSeq = 0;
let jobLevelSystemData = null;
const FISH_ZONE_LABEL = { shore: '일반 낚시', boat: '선상 낚시' };

function renderFishingSystem() {
  const body = document.getElementById('fishSysBody');
  if (!body) return;
  if (!fishingSystemData || !fishingSystemData.grades) {
    body.innerHTML = '<div class="ck-skin-empty">설정을 불러오는 중…</div>';
    return;
  }

  const grades = fishingSystemData.grades || [];
  const weights = fishingSystemData.weights || { shore: {}, boat: {} };

  body.innerHTML = ['shore', 'boat'].map((kind) => {
    const rows = grades.map((g) =>
      '<div class="ck-fishsys-row">' +
        '<span class="ck-fishsys-grade">' + escapeHtml(g.label) + '</span>' +
        '<div class="ck-fishsys-inputwrap">' +
          '<input class="ck-fishsys-input" type="number" min="0" max="100" step="0.1" ' +
            'data-kind="' + kind + '" data-grade="' + escapeHtml(g.key) + '" value="' +
            Number((weights[kind] || {})[g.key] || 0) + '">' +
          '<span>%</span>' +
        '</div>' +
      '</div>').join('');

    return '<section class="ck-fishsys-card">' +
      '<div class="ck-fishsys-cardhead"><strong>' + FISH_ZONE_LABEL[kind] + '</strong>' +
      '<span class="ck-fishsys-total" id="fishTotal_' + kind + '">합계 0%</span></div>' +
      rows + '</section>';
  }).join('');

  body.querySelectorAll('.ck-fishsys-input').forEach((inp) =>
    inp.addEventListener('input', updateFishingTotals));
  updateFishingTotals();
}

function updateFishingTotals() {
  ['shore', 'boat'].forEach((kind) => {
    let total = 0;
    document.querySelectorAll('.ck-fishsys-input[data-kind="' + kind + '"]').forEach((inp) => {
      total += Number(inp.value) || 0;
    });
    const el = document.getElementById('fishTotal_' + kind);
    if (el) {
      el.textContent = '합계 ' + (Math.round(total * 100) / 100) + '%';
      el.classList.toggle('bad', Math.abs(total - 100) > 0.01);
    }
  });
}

const fishSysSave = document.getElementById('fishSysSave');
if (fishSysSave) fishSysSave.addEventListener('click', () => {
  if (!fishingSystemData) return;
  const weights = { shore: {}, boat: {} };
  let valid = true;

  document.querySelectorAll('.ck-fishsys-input').forEach((inp) => {
    const v = Number(inp.value);
    if (!Number.isFinite(v) || v < 0 || v > 100) valid = false;
    weights[inp.dataset.kind][inp.dataset.grade] = v;
  });

  for (const kind of ['shore', 'boat']) {
    const total = Object.values(weights[kind]).reduce((a, b) => a + (Number(b) || 0), 0);
    if (Math.abs(total - 100) > 0.01) valid = false;
  }

  if (!valid) {
    showToast('일반/선상 낚시 확률 합계를 각각 100%로 맞춰주세요', true);
    return;
  }

  fetch('https://cookie_admin/saveFishingSystem', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ weights }),
  }).catch(() => {});
});


function renderMiningSystem(){
  const body=document.getElementById('miningSysBody');
  if(!body)return;
  if(!miningSystemData){
    if(miningSystemError){
      body.innerHTML='<div class="ck-skin-empty"><b style="display:block;color:#b42318;margin-bottom:8px">설정을 불러오지 못했습니다</b><span>'+escapeHtml(miningSystemError)+'</span><br><button id="miningSystemRetry" class="ck-fc-abtn" style="margin-top:14px">다시 불러오기</button></div>';
      const retry=body.querySelector('#miningSystemRetry');
      if(retry) retry.onclick=()=>requestMiningSystemData();
    }else{
      body.innerHTML='<div class="ck-skin-empty">설정을 불러오는 중…</div>';
    }
    return;
  }
  const mineSec=Number(miningSystemData.mineDurationSec ?? ((Number(miningSystemData.mineDurationMs)||20000)/1000));
  const rhythmSuccessSec=Number(miningSystemData.rhythmSuccessSec ?? ((Number(miningSystemData.rhythmSuccessMs)||5000)/1000));
  const rhythmRounds=Number(miningSystemData.rhythmRounds||4);
  const nodeCount=Number(miningSystemData.nodeCount||9);
  const respawnSec=Number(miningSystemData.respawnSec ?? ((Number(miningSystemData.respawnMs)||45000)/1000));
  const purityMinMultiplier=Number(miningSystemData.purityMinMultiplier??0.5);
  const purityMaxMultiplier=Number(miningSystemData.purityMaxMultiplier??2.0);
  const pickaxeSkilledMultiplier=Number(miningSystemData.pickaxeSkilledMultiplier??0.80);
  const pickaxeExpertMultiplier=Number(miningSystemData.pickaxeExpertMultiplier??0.60);
  const pickaxeBasicPrice=Number(miningSystemData.pickaxeBasicPrice??50000);
  const pickaxeSkilledPrice=Number(miningSystemData.pickaxeSkilledPrice??150000);
  const pickaxeExpertPrice=Number(miningSystemData.pickaxeExpertPrice??350000);
  body.innerHTML=
    '<div class="ck-couple-admin-wrap">'+
      '<div class="ck-couple-admin-settings">'+
        '<label class="ck-couple-admin-price"><span>기본 채굴 시간</span><div><input id="miningDurationSec" type="number" min="5" max="120" step="1" value="'+mineSec+'"><b>초</b></div><small>리듬게임 실패 시 적용됩니다. 기본 20초.</small></label>'+
        '<label class="ck-couple-admin-price"><span>리듬 성공 채굴 시간</span><div><input id="miningRhythmSuccessSec" type="number" min="1" max="120" step="1" value="'+rhythmSuccessSec+'"><b>초</b></div><small>리듬게임 성공 시 적용됩니다. 기본 5초.</small></label>'+
        '<label class="ck-couple-admin-price"><span>리듬 입력 횟수</span><div><input id="miningRhythmRounds" type="number" min="1" max="10" step="1" value="'+rhythmRounds+'"><b>회</b></div><small>W/A/S/D 리듬 입력 횟수입니다.</small></label>'+
        '<label class="ck-couple-admin-price"><span>광산 바위 개수</span><div><input id="miningNodeCount" type="number" min="1" max="40" step="1" value="'+nodeCount+'"><b>개</b></div><small>각 광산 범위 안에 생성되는 채굴 가능한 바위 오브젝트 수입니다.</small></label>'+
        '<label class="ck-couple-admin-price"><span>바위 재생 시간</span><div><input id="miningRespawnSec" type="number" min="5" max="3600" step="1" value="'+respawnSec+'"><b>초</b></div><small>채굴 완료된 바위가 다시 채굴 가능해질 때까지 기다리는 시간입니다.</small></label>'+
        '<label class="ck-couple-admin-price"><span>보급형 곡괭이 기본 가격</span><div><input id="miningPickaxeBasicPrice" type="number" min="0" max="100000000" step="1000" value="'+pickaxeBasicPrice+'"><b>원</b></div><small>NPC에 별도 가격이 없을 때 적용되는 기본 판매가입니다.</small></label>'+
        '<label class="ck-couple-admin-price"><span>숙련자 곡괭이 기본 가격</span><div><input id="miningPickaxeSkilledPrice" type="number" min="0" max="100000000" step="1000" value="'+pickaxeSkilledPrice+'"><b>원</b></div><small>NPC에 별도 가격이 없을 때 적용되는 기본 판매가입니다.</small></label>'+
        '<label class="ck-couple-admin-price"><span>전문가 곡괭이 기본 가격</span><div><input id="miningPickaxeExpertPrice" type="number" min="0" max="100000000" step="1000" value="'+pickaxeExpertPrice+'"><b>원</b></div><small>NPC에 별도 가격이 없을 때 적용되는 기본 판매가입니다.</small></label>'+
        '<label class="ck-couple-admin-price"><span>숙련자 곡괭이 채굴시간 배율</span><div><input id="miningPickaxeSkilledMultiplier" type="number" min="0.10" max="2.00" step="0.05" value="'+pickaxeSkilledMultiplier+'"><b>x</b></div><small>기본값 x0.80. 기본/리듬 성공 시간 모두에 적용됩니다.</small></label>'+
        '<label class="ck-couple-admin-price"><span>전문가 곡괭이 채굴시간 배율</span><div><input id="miningPickaxeExpertMultiplier" type="number" min="0.10" max="2.00" step="0.05" value="'+pickaxeExpertMultiplier+'"><b>x</b></div><small>기본값 x0.60. 기본/리듬 성공 시간 모두에 적용됩니다.</small></label>'+
        '<label class="ck-couple-admin-price"><span>순도 최소 가격 배율</span><div><input id="miningPurityMin" type="number" min="0" max="10" step="0.05" value="'+purityMinMultiplier+'"><b>x</b></div><small>순도 0% 기준 배율입니다.</small></label>'+
        '<label class="ck-couple-admin-price"><span>순도 최대 가격 배율</span><div><input id="miningPurityMax" type="number" min="0" max="10" step="0.05" value="'+purityMaxMultiplier+'"><b>x</b></div><small>순도 100% 기준 배율입니다.</small></label>'+

      '</div>'+
      '<div class="ck-couple-admin-note"><b>실시간 적용</b><span>바위 개수를 변경하면 접속 중인 유저의 광산 오브젝트도 즉시 다시 생성됩니다. 출현 광물/가중치는 좌표 관리의 <b>광산설정</b>에서 따로 관리합니다.</span></div>'+
    '</div>';
}

document.getElementById('miningSysSave')?.addEventListener('click',()=>{
  const mineDurationSec=Number(document.getElementById('miningDurationSec')?.value);
  const rhythmSuccessSec=Number(document.getElementById('miningRhythmSuccessSec')?.value);
  const rhythmRounds=Math.floor(Number(document.getElementById('miningRhythmRounds')?.value));
  const nodeCount=Math.floor(Number(document.getElementById('miningNodeCount')?.value));
  const respawnSec=Number(document.getElementById('miningRespawnSec')?.value);
  const purityMinMultiplier=Number(document.getElementById('miningPurityMin')?.value);
  const purityMaxMultiplier=Number(document.getElementById('miningPurityMax')?.value);
  const pickaxeSkilledMultiplier=Number(document.getElementById('miningPickaxeSkilledMultiplier')?.value);
  const pickaxeExpertMultiplier=Number(document.getElementById('miningPickaxeExpertMultiplier')?.value);
  const pickaxeBasicPrice=Math.floor(Number(document.getElementById('miningPickaxeBasicPrice')?.value));
  const pickaxeSkilledPrice=Math.floor(Number(document.getElementById('miningPickaxeSkilledPrice')?.value));
  const pickaxeExpertPrice=Math.floor(Number(document.getElementById('miningPickaxeExpertPrice')?.value));
  if(!Number.isFinite(mineDurationSec)||mineDurationSec<5||mineDurationSec>120){showToast('기본 채굴 시간은 5~120초로 설정하세요',true);return;}
  if(!Number.isFinite(rhythmSuccessSec)||rhythmSuccessSec<1||rhythmSuccessSec>mineDurationSec){showToast('리듬 성공 시간은 1초 이상이며 기본 시간 이하여야 합니다',true);return;}
  if(!Number.isFinite(rhythmRounds)||rhythmRounds<1||rhythmRounds>10){showToast('리듬 입력 횟수는 1~10회로 설정하세요',true);return;}
  if(!Number.isFinite(nodeCount)||nodeCount<1||nodeCount>40){showToast('바위 개수는 1~40개로 설정하세요',true);return;}
  if(!Number.isFinite(respawnSec)||respawnSec<5||respawnSec>3600){showToast('재생 시간은 5~3600초로 설정하세요',true);return;}
  if(!Number.isFinite(purityMinMultiplier)||!Number.isFinite(purityMaxMultiplier)||purityMinMultiplier<0||purityMaxMultiplier<purityMinMultiplier||purityMaxMultiplier>10){showToast('순도 가격 배율을 확인하세요',true);return;}
  if(!Number.isFinite(pickaxeSkilledMultiplier)||!Number.isFinite(pickaxeExpertMultiplier)||pickaxeSkilledMultiplier<0.10||pickaxeSkilledMultiplier>2.00||pickaxeExpertMultiplier<0.10||pickaxeExpertMultiplier>2.00){showToast('곡괭이 채굴시간 배율은 0.10~2.00으로 설정하세요',true);return;}
  if(![pickaxeBasicPrice,pickaxeSkilledPrice,pickaxeExpertPrice].every(v=>Number.isFinite(v)&&v>=0&&v<=100000000)){showToast('곡괭이 가격은 0~100,000,000원으로 설정하세요',true);return;}
  const b=document.getElementById('miningSysSave');
  if(b){b.disabled=true;b.textContent='저장 중…';}
  fetch('https://cookie_admin/saveMiningSystem',{
    method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({mineDurationSec,rhythmSuccessSec,rhythmRounds,nodeCount,respawnSec,purityMinMultiplier,purityMaxMultiplier,pickaxeSkilledMultiplier,pickaxeExpertMultiplier,pickaxeBasicPrice,pickaxeSkilledPrice,pickaxeExpertPrice})
  }).catch(()=>{if(b){b.disabled=false;b.textContent='저장';}});
});

function renderNpcDelivery(){
 const main=document.getElementById('npcMain'),title=document.getElementById('npcTitle'),sub=document.getElementById('npcSub');if(!main)return;
 title.textContent='배달기사 작업 설정';sub.textContent='배달 관리인마다 식당 픽업 위치와 배달 목적지, 기본 보수와 거리 수수료를 설정합니다';
 const rows=((npcData&&npcData.rows)||[]).filter(r=>r.job_key==='delivery');if(!window.__dnpc&&rows[0])window.__dnpc=rows[0].id;
 const picker=rows.length?rows.map(r=>'<button class="ck-rtab'+(Number(window.__dnpc)===Number(r.id)?' active':'')+'" data-dnpc="'+r.id+'">'+escapeHtml(r.label)+'</button>').join(''):'<span class="ck-skin-empty">배달 관리인 NPC를 먼저 배치하세요</span>';
 const head='<p class="ck-fc-sec">배달 관리인 선택</p><div class="ck-rtabs" style="margin-bottom:16px">'+picker+'</div>';
 const d=window.__npcDelivery||{},rs=d.restaurants||[],ds=d.dropoffs||[];
 const rlist=rs.length?rs.map(r=>'<div class="ck-call ck-labor-card"><div class="ck-call-top"><span class="ck-hail-state ok">사용 가능</span><input class="ck-hail-name dr-name" data-id="'+r.id+'" value="'+escapeHtml(r.label)+'"><button class="ck-fc-abtn dr-save" data-id="'+r.id+'">저장</button><button class="ck-fc-xbtn dr-del" data-id="'+r.id+'">삭제</button></div><div class="ck-call-row"><span class="ck-call-k ok">기본 보수</span><input class="dr-base" data-id="'+r.id+'" type="number" value="'+r.base_pay+'" style="width:130px;padding:7px;border:1px solid #ddd;border-radius:8px"><span class="ck-call-k ok">KM당 수수료</span><input class="dr-km" data-id="'+r.id+'" type="number" value="'+r.per_km+'" style="width:130px;padding:7px;border:1px solid #ddd;border-radius:8px"></div><div class="ck-call-row"><span class="ck-call-k ok">식당 픽업 위치</span><span class="ck-call-v">'+Number(r.pickup_x).toFixed(0)+', '+Number(r.pickup_y).toFixed(0)+', '+Number(r.pickup_z).toFixed(0)+'</span><button class="ck-fc-abtn dr-set" data-id="'+r.id+'">현재 위치로 저장</button><button class="ck-fc-abtn d-go" data-x="'+r.pickup_x+'" data-y="'+r.pickup_y+'" data-z="'+r.pickup_z+'">이동</button></div></div>').join(''):'<div class="ck-skin-empty">등록된 식당이 없습니다</div>';
 const dlist=ds.length?ds.map(r=>'<div class="ck-call ck-labor-card"><div class="ck-call-top"><span class="ck-hail-state ok">사용 가능</span><input class="ck-hail-name dd-name" data-id="'+r.id+'" value="'+escapeHtml(r.label)+'"><button class="ck-fc-abtn dd-save" data-id="'+r.id+'">저장</button><button class="ck-fc-xbtn dd-del" data-id="'+r.id+'">삭제</button></div><div class="ck-call-row"><span class="ck-call-k ok">배달 목적지</span><span class="ck-call-v">'+Number(r.x).toFixed(0)+', '+Number(r.y).toFixed(0)+', '+Number(r.z).toFixed(0)+'</span><button class="ck-fc-abtn dd-set" data-id="'+r.id+'">현재 위치로 저장</button><button class="ck-fc-abtn d-go" data-x="'+r.x+'" data-y="'+r.y+'" data-z="'+r.z+'">이동</button></div></div>').join(''):'<div class="ck-skin-empty">등록된 배달 목적지가 없습니다</div>';
 main.innerHTML=head+'<div class="ck-fc-card"><p class="ck-fc-card-h">새 식당 픽업 지점</p><div class="ck-fc-body-p"><div class="ck-fc-fields"><label>식당 이름<input id="drName" placeholder="버거샷"></label><label>기본 보수<input id="drBase" type="number" value="15000"></label><label>KM당 수수료<input id="drKm" type="number" value="10000"></label></div><div style="font-size:11px;color:#999;margin:10px 0">생성 시 현재 위치가 음식 픽업 위치로 저장됩니다.</div><div class="ck-fc-btns"><button id="drAdd" class="ck-fc-btn primary">식당 생성 (현재 위치 = 픽업 지점)</button></div></div></div><div class="ck-fc-card"><p class="ck-fc-card-h">등록된 식당 ('+rs.length+')</p><div class="ck-fc-body-p"><div class="ck-call-list">'+rlist+'</div></div></div><div class="ck-fc-card"><p class="ck-fc-card-h">새 배달 목적지</p><div class="ck-fc-body-p"><div class="ck-fc-fields"><label>배달지 이름<input id="ddName" placeholder="아파트 A동"></label></div><div style="font-size:11px;color:#999;margin:10px 0">생성 시 현재 위치가 배달 완료 위치로 저장됩니다.</div><div class="ck-fc-btns"><button id="ddAdd" class="ck-fc-btn primary">목적지 생성 (현재 위치 = 배달 지점)</button></div></div></div><div class="ck-fc-card"><p class="ck-fc-card-h">등록된 배달 목적지 ('+ds.length+')</p><div class="ck-fc-body-p"><div class="ck-call-list">'+dlist+'</div></div></div>';
 main.querySelectorAll('[data-dnpc]').forEach(b=>b.onclick=()=>{window.__dnpc=Number(b.dataset.dnpc);window.__npcDelivery=null;fcPost('deliveryList',{npcId:window.__dnpc});renderNpcDelivery()});
 document.getElementById('drAdd').onclick=()=>fcPost('deliveryAddRestaurant',{npcId:window.__dnpc,label:document.getElementById('drName').value||'식당',basePay:Number(document.getElementById('drBase').value)||15000,perKm:Number(document.getElementById('drKm').value)||10000});
 document.getElementById('ddAdd').onclick=()=>fcPost('deliveryAddDropoff',{npcId:window.__dnpc,label:document.getElementById('ddName').value||'고객'});
 main.querySelectorAll('.dr-save').forEach(b=>b.onclick=()=>{const id=Number(b.dataset.id);fcPost('deliveryUpdateRestaurant',{npcId:window.__dnpc,id,label:main.querySelector('.dr-name[data-id="'+id+'"]').value,basePay:Number(main.querySelector('.dr-base[data-id="'+id+'"]').value),perKm:Number(main.querySelector('.dr-km[data-id="'+id+'"]').value)})});
 main.querySelectorAll('.dr-set').forEach(b=>b.onclick=()=>fcPost('deliverySetRestaurantCoord',{npcId:window.__dnpc,id:Number(b.dataset.id)}));
 main.querySelectorAll('.dr-del').forEach(b=>b.onclick=()=>fcPost('deliveryDeleteRestaurant',{npcId:window.__dnpc,id:Number(b.dataset.id)}));
 main.querySelectorAll('.dd-save').forEach(b=>b.onclick=()=>{const id=Number(b.dataset.id);fcPost('deliveryUpdateDropoff',{npcId:window.__dnpc,id,label:main.querySelector('.dd-name[data-id="'+id+'"]').value})});
 main.querySelectorAll('.dd-set').forEach(b=>b.onclick=()=>fcPost('deliverySetDropoffCoord',{npcId:window.__dnpc,id:Number(b.dataset.id)}));
 main.querySelectorAll('.dd-del').forEach(b=>b.onclick=()=>fcPost('deliveryDeleteDropoff',{npcId:window.__dnpc,id:Number(b.dataset.id)}));
 main.querySelectorAll('.d-go').forEach(b=>b.onclick=()=>{fcPost('hailGoto',{x:Number(b.dataset.x),y:Number(b.dataset.y),z:Number(b.dataset.z)});closeNpcConsole();closePanel()});
 if(window.__dnpc&&(!d.npcId||Number(d.npcId)!==Number(window.__dnpc)))fcPost('deliveryList',{npcId:window.__dnpc});
}


// ===== 시스템 관리 > 직업 레벨 =====
function renderJobLevelSystem(){
  const body=document.getElementById('jobLevelSysBody');
  if(!body)return;
  if(!jobLevelSystemData||!Array.isArray(jobLevelSystemData.jobs)){
    body.innerHTML='<div class="ck-skin-empty">설정을 불러오는 중…</div>';return;
  }
  body.innerHTML=jobLevelSystemData.jobs.map(j=>{
    const req=(j.requirements||[]).map(r=>
      '<div class="ck-jobcfg-lv">'+
        '<b>LV '+r.targetLevel+'</b>'+
        '<label>필요 경험치<input class="ck-jobcfg-exp" data-job="'+escapeHtml(j.key)+'" data-lv="'+r.targetLevel+'" type="number" min="0" value="'+Number(r.requiredExp||0)+'"></label>'+
        '<label>승급 아이템<input class="ck-jobcfg-item" data-job="'+escapeHtml(j.key)+'" data-lv="'+r.targetLevel+'" type="text" value="'+escapeHtml(r.itemName||'')+'" placeholder="비우면 없음 / 예: cookie_kuji_ticket"></label>'+
        '<label>개수<input class="ck-jobcfg-count" data-job="'+escapeHtml(j.key)+'" data-lv="'+r.targetLevel+'" type="number" min="0" max="999" value="'+Number(r.itemCount||0)+'"></label>'+
      '</div>'
    ).join('');
    return '<section class="ck-jobcfg-card" data-jobcard="'+escapeHtml(j.key)+'">'+
      '<div class="ck-jobcfg-head"><div><b>'+escapeHtml((j.emoji||'💼')+' '+j.label)+'</b><span>'+escapeHtml(j.key)+'</span></div>'+
      '<label>최대 레벨 <input class="ck-jobcfg-max" data-job="'+escapeHtml(j.key)+'" type="number" min="1" max="50" value="'+Number(j.maxLevel||5)+'"></label></div>'+
      '<div class="ck-jobcfg-levels">'+req+'</div>'+
    '</section>';
  }).join('');
}

function collectJobLevelSystem(){
  const jobs=[];
  document.querySelectorAll('[data-jobcard]').forEach(card=>{
    const key=card.dataset.jobcard;
    const maxEl=card.querySelector('.ck-jobcfg-max');
    const requirements=[];
    card.querySelectorAll('.ck-jobcfg-exp').forEach(exp=>{
      const lv=Number(exp.dataset.lv);
      requirements.push({
        targetLevel:lv,
        requiredExp:Number(exp.value)||0,
        itemName:(card.querySelector('.ck-jobcfg-item[data-lv="'+lv+'"]')?.value||'').trim(),
        itemCount:Number(card.querySelector('.ck-jobcfg-count[data-lv="'+lv+'"]')?.value)||0
      });
    });
    jobs.push({key,maxLevel:Number(maxEl?.value)||1,requirements});
  });
  return {jobs};
}

const jobLevelSysSave=document.getElementById('jobLevelSysSave');
if(jobLevelSysSave)jobLevelSysSave.addEventListener('click',()=>{
  fetch('https://cookie_admin/saveJobLevelSystem',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(collectJobLevelSystem())}).catch(()=>{});
});


let attendanceAdminData = null;
let attendanceAdminTab = 'daily';
let attendanceDailyDraft = [];
let attendanceMonthlyDraft = [];
let questAdminData = null;
let questAdminDraft = [];
let questAdminSeq = 0;

function attendanceAdminTypeLabel(type) {
  return ({ none: '미설정', bank: '계좌', cash: '현금', item: '아이템' })[type] || '미설정';
}

function cloneAttendanceDailyRows(rows){
  return (Array.isArray(rows)?rows:[]).map((r,idx)=>({
    id:Number(r.id)||0,
    requiredMinutes:Math.max(1,Number(r.requiredMinutes)||60),
    type:String(r.type||'none'), amount:Number(r.amount)||0,
    itemName:String(r.itemName||''), itemCount:Number(r.itemCount)||1,
    label:String(r.label||''), active:r.active!==false, sort:Number(r.sort)||((idx+1)*10)
  }));
}
function cloneAttendanceMonthlyRows(rows){
  const src=Array.isArray(rows)?rows:[];
  const out=[];
  for(let day=1;day<=28;day++){
    const r=src.find(x=>Number(x.day)===day)||{};
    out.push({day,type:String(r.type||'none'),amount:Number(r.amount)||0,itemName:String(r.itemName||''),itemCount:Number(r.itemCount)||1,label:String(r.label||'')});
  }
  return out;
}
function attendanceMinuteLabel(min){
  min=Math.max(0,Math.floor(Number(min)||0));
  const h=Math.floor(min/60),m=min%60;
  if(h>0&&m>0)return h+'시간 '+m+'분';
  if(h>0)return h+'시간';
  return min+'분';
}

function syncAttendanceDraftFromDom(){
  if(attendanceAdminTab==='daily'){
    if(attendanceAdminData?.daily){
      attendanceAdminData.daily.config=attendanceAdminData.daily.config||{};
      const en=document.getElementById('attendanceDailyEnabled'),title=document.getElementById('attendanceDailyTitle');
      if(en)attendanceAdminData.daily.config.enabled=!!en.checked;
      if(title)attendanceAdminData.daily.config.title=(title.value||'일일 출석 체크').trim();
    }
    const rows=[];
    document.querySelectorAll('[data-attdailyrow]').forEach(card=>rows.push({
      id:Number(card.dataset.id)||0,
      requiredMinutes:Math.max(1,Number(card.querySelector('.ck-atdaily-min')?.value)||1),
      type:card.querySelector('.ck-atdaily-type')?.value||'none',
      amount:Number(card.querySelector('.ck-atdaily-amount')?.value)||0,
      itemName:(card.querySelector('.ck-atdaily-itemname')?.value||'').trim(),
      itemCount:Number(card.querySelector('.ck-atdaily-count')?.value)||0,
      label:(card.querySelector('.ck-atdaily-label')?.value||'').trim(),
      active:!!card.querySelector('.ck-atdaily-active')?.checked
    }));
    if(rows.length)attendanceDailyDraft=rows;
  }else{
    if(attendanceAdminData?.monthly){
      attendanceAdminData.monthly.config=attendanceAdminData.monthly.config||{};
      const en=document.getElementById('attendanceMonthlyEnabled'),title=document.getElementById('attendanceMonthlyTitle');
      if(en)attendanceAdminData.monthly.config.enabled=!!en.checked;
      if(title)attendanceAdminData.monthly.config.title=(title.value||'월간 출석 체크').trim();
    }
    const rows=[];
    document.querySelectorAll('[data-attmonthday]').forEach(card=>rows.push({
      day:Number(card.dataset.attmonthday),
      type:card.querySelector('.ck-atadm-type')?.value||'none',
      amount:Number(card.querySelector('.ck-atadm-amount')?.value)||0,
      itemName:(card.querySelector('.ck-atadm-itemname')?.value||'').trim(),
      itemCount:Number(card.querySelector('.ck-atadm-count')?.value)||0,
      label:(card.querySelector('.ck-atadm-label')?.value||'').trim()
    }));
    if(rows.length)attendanceMonthlyDraft=rows;
  }
}

function attendanceRewardEditorFields(prefix,r){
  const type=r.type||'none';
  return '<label>보상 유형<select class="'+prefix+'-type">'+
    '<option value="none"'+(type==='none'?' selected':'')+'>미설정</option>'+
    '<option value="bank"'+(type==='bank'?' selected':'')+'>계좌</option>'+
    '<option value="cash"'+(type==='cash'?' selected':'')+'>현금</option>'+
    '<option value="item"'+(type==='item'?' selected':'')+'>아이템</option></select></label>'+
    '<div class="'+prefix+'-money '+((type==='bank'||type==='cash')?'':'hidden')+'"><label>금액<input class="'+prefix+'-amount" type="number" min="0" max="1000000000" step="1000" value="'+(Number(r.amount)||0)+'"></label></div>'+
    '<div class="'+prefix+'-item '+(type==='item'?'':'hidden')+'"><label>아이템 이름<input class="'+prefix+'-itemname" maxlength="80" value="'+escapeHtml(r.itemName||'')+'" placeholder="예: water"></label><label>개수<input class="'+prefix+'-count" type="number" min="1" max="999" value="'+(Number(r.itemCount)||1)+'"></label></div>'+
    '<label class="'+prefix+'-label-wrap">표시 문구<input class="'+prefix+'-label" maxlength="80" value="'+escapeHtml(r.label||'')+'" placeholder="비우면 자동 표시"></label>';
}

function renderAttendanceAdmin(){
  const body=document.getElementById('attendanceSysBody');
  if(!body)return;
  if(!attendanceAdminData||!attendanceAdminData.daily||!attendanceAdminData.monthly){
    body.innerHTML='<div class="ck-skin-empty">설정을 불러오는 중…</div>';return;
  }
  const daily=attendanceAdminData.daily||{}, monthly=attendanceAdminData.monthly||{};
  const dcfg=daily.config||{}, mcfg=monthly.config||{};
  let content='';

  if(attendanceAdminTab==='daily'){
    const rows=attendanceDailyDraft.map((r,idx)=>
      '<section class="ck-attdaily-admin-row" data-attdailyrow="'+idx+'" data-id="'+(Number(r.id)||0)+'">'+
        '<div class="ck-attdaily-admin-head"><div><b>'+attendanceMinuteLabel(r.requiredMinutes)+' 접속 보상</b><span>오늘 누적 접속시간 기준</span></div><button type="button" data-attdaily-remove="'+idx+'">삭제</button></div>'+
        '<div class="ck-attdaily-admin-fields">'+
          '<label>필요 접속시간(분)<input class="ck-atdaily-min" type="number" min="1" max="1440" value="'+Math.max(1,Number(r.requiredMinutes)||1)+'"></label>'+
          '<label class="ck-atdaily-active-wrap"><span>사용</span><input class="ck-atdaily-active" type="checkbox"'+(r.active!==false?' checked':'')+'></label>'+
          attendanceRewardEditorFields('ck-atdaily',r)+
        '</div>'+
      '</section>'
    ).join('');
    content='<div class="ck-atadm-top">'+
      '<label class="ck-atadm-enabled"><input id="attendanceDailyEnabled" type="checkbox"'+(dcfg.enabled?' checked':'')+'><span>일일 출석체크 활성화</span></label>'+
      '<label class="ck-atadm-title">제목<input id="attendanceDailyTitle" maxlength="40" value="'+escapeHtml(dcfg.title||'일일 출석 체크')+'"></label>'+
      '<div class="ck-atadm-info"><b>운영 방식</b><span>오늘 접속한 누적 시간으로 단계별 보상을 해금 · 자정(KST) 초기화</span></div>'+
      '<button class="ck-keyadm-add ck-attdaily-add" id="attendanceDailyAdd" type="button">+ 접속시간 보상 추가</button>'+ 
    '</div><div class="ck-attdaily-admin-list">'+(rows||'<div class="ck-skin-empty">등록된 접속시간 보상이 없습니다. 위의 추가 버튼으로 만들어주세요.</div>')+'</div>';
  }else{
    const cards=attendanceMonthlyDraft.map(r=>{
      const day=Number(r.day),bonus=day%7===0;
      return '<div class="ck-atadm-card'+(bonus?' bonus':'')+'" data-attmonthday="'+day+'">'+
        '<div class="ck-atadm-card-head"><b>'+day+'일차</b>'+(bonus?'<span>WEEK BONUS</span>':'')+'</div>'+attendanceRewardEditorFields('ck-atadm',r)+'</div>';
    }).join('');
    content='<div class="ck-atadm-top">'+
      '<label class="ck-atadm-enabled"><input id="attendanceMonthlyEnabled" type="checkbox"'+(mcfg.enabled?' checked':'')+'><span>월간 출석체크 활성화</span></label>'+
      '<label class="ck-atadm-title">제목<input id="attendanceMonthlyTitle" maxlength="40" value="'+escapeHtml(mcfg.title||'월간 출석 체크')+'"></label>'+
      '<div class="ck-atadm-info"><b>운영 방식</b><span>하루 1회 · 28단계 순차 지급 · 빠뜨려도 다음 보상 순서는 유지</span></div>'+ 
    '</div><div class="ck-atadm-grid">'+cards+'</div>';
  }

  body.innerHTML='<div class="ck-atadm-tabs"><button data-attadm-tab="daily" class="'+(attendanceAdminTab==='daily'?'on':'')+'">일일 출석체크</button><button data-attadm-tab="monthly" class="'+(attendanceAdminTab==='monthly'?'on':'')+'">월간 출석체크</button></div>'+content;

  body.querySelectorAll('[data-attadm-tab]').forEach(btn=>btn.addEventListener('click',()=>{
    if(btn.dataset.attadmTab===attendanceAdminTab)return;
    syncAttendanceDraftFromDom(); attendanceAdminTab=btn.dataset.attadmTab; renderAttendanceAdmin();
  }));
  body.querySelectorAll('.ck-atdaily-type,.ck-atadm-type').forEach(sel=>sel.addEventListener('change',()=>{
    const card=sel.closest('[data-attdailyrow],[data-attmonthday]'); if(!card)return;
    const p=sel.classList.contains('ck-atdaily-type')?'ck-atdaily':'ck-atadm';
    card.querySelector('.'+p+'-money')?.classList.toggle('hidden',!(sel.value==='bank'||sel.value==='cash'));
    card.querySelector('.'+p+'-item')?.classList.toggle('hidden',sel.value!=='item');
  }));
  body.querySelectorAll('[data-attdaily-remove]').forEach(btn=>btn.addEventListener('click',()=>{
    syncAttendanceDraftFromDom(); attendanceDailyDraft.splice(Number(btn.dataset.attdailyRemove),1); renderAttendanceAdmin();
  }));
  document.getElementById('attendanceDailyAdd')?.addEventListener('click',()=>{
    syncAttendanceDraftFromDom();
    const max=24;if(attendanceDailyDraft.length>=max){showToast('일일 접속시간 보상은 최대 '+max+'개까지 등록할 수 있습니다.',true);return;}
    const last=attendanceDailyDraft.reduce((m,r)=>Math.max(m,Number(r.requiredMinutes)||0),0);
    attendanceDailyDraft.push({id:0,requiredMinutes:Math.min(1440,last>0?last+60:60),type:'none',amount:0,itemName:'',itemCount:1,label:'',active:true});
    renderAttendanceAdmin();
  });
}

function collectAttendanceAdmin(){
  syncAttendanceDraftFromDom();
  const dcfg=attendanceAdminData?.daily?.config||{},mcfg=attendanceAdminData?.monthly?.config||{};
  return {
    daily:{config:{enabled:document.getElementById('attendanceDailyEnabled')?!!document.getElementById('attendanceDailyEnabled').checked:!!dcfg.enabled,title:(document.getElementById('attendanceDailyTitle')?.value||dcfg.title||'일일 출석 체크').trim()},rewards:attendanceDailyDraft},
    monthly:{config:{enabled:document.getElementById('attendanceMonthlyEnabled')?!!document.getElementById('attendanceMonthlyEnabled').checked:!!mcfg.enabled,title:(document.getElementById('attendanceMonthlyTitle')?.value||mcfg.title||'월간 출석 체크').trim()},rewards:attendanceMonthlyDraft}
  };
}

const attendanceSysSave=document.getElementById('attendanceSysSave');
if(attendanceSysSave)attendanceSysSave.addEventListener('click',()=>{
  attendanceSysSave.disabled=true;attendanceSysSave.textContent='저장 중…';
  fetch('https://cookie_admin/saveAttendanceAdmin',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(collectAttendanceAdmin())}).catch(()=>{attendanceSysSave.disabled=false;attendanceSysSave.textContent='저장';});
});

function cloneQuestAdminRows(rows){
  return (Array.isArray(rows)?rows:[]).map(q=>({
    id:String(q.id||''),period:q.period==='weekly'?'weekly':'daily',metric:String(q.metric||'playtime_min'),
    title:String(q.title||''),description:String(q.description||''),target:Math.max(1,Number(q.target)||1),unit:String(q.unit||'minute'),
    rewardType:String(q.rewardType||'none'),rewardAmount:Number(q.rewardAmount)||0,rewardItem:String(q.rewardItem||''),rewardCount:Number(q.rewardCount)||1,
    sort:Number(q.sort)||0,active:q.active!==false
  }));
}
function questMetricDef(key){return (questAdminData?.metrics||[]).find(m=>m.key===key)||{key:'playtime_min',label:'접속시간',unit:'minute'};}
function questRewardTypeOptions(type){return '<option value="none"'+(type==='none'?' selected':'')+'>미설정</option><option value="bank"'+(type==='bank'?' selected':'')+'>계좌</option><option value="cash"'+(type==='cash'?' selected':'')+'>현금</option><option value="item"'+(type==='item'?' selected':'')+'>아이템</option>';}
function collectQuestAdminRows(){
  const rows=[];
  document.querySelectorAll('[data-qadm-row]').forEach(card=>{
    const metric=card.querySelector('.ck-qadm-metric')?.value||'playtime_min';const md=questMetricDef(metric);
    rows.push({id:card.dataset.id||'',period:card.querySelector('.ck-qadm-period')?.value||'daily',metric,
      title:(card.querySelector('.ck-qadm-title')?.value||'').trim(),description:(card.querySelector('.ck-qadm-desc')?.value||'').trim(),
      target:Math.max(1,Number(card.querySelector('.ck-qadm-target')?.value)||1),unit:md.unit,
      rewardType:card.querySelector('.ck-qadm-rewardtype')?.value||'none',rewardAmount:Number(card.querySelector('.ck-qadm-rewardamount')?.value)||0,
      rewardItem:(card.querySelector('.ck-qadm-rewarditem')?.value||'').trim(),rewardCount:Number(card.querySelector('.ck-qadm-rewardcount')?.value)||0,
      sort:Number(card.querySelector('.ck-qadm-sort')?.value)||0,active:!!card.querySelector('.ck-qadm-active')?.checked});
  });
  return rows;
}
function renderQuestAdmin(){
  const body=document.getElementById('questAdminBody');if(!body)return;
  if(!questAdminData){body.innerHTML='<div class="ck-skin-empty">퀘스트 설정을 불러오는 중…</div>';return;}
  const metrics=Array.isArray(questAdminData.metrics)?questAdminData.metrics:[];
  const html=questAdminDraft.map((q,idx)=>{
    const md=questMetricDef(q.metric),type=q.rewardType||'none';
    const metricOpts=metrics.map(m=>'<option value="'+escapeHtml(m.key)+'"'+(m.key===q.metric?' selected':'')+'>'+escapeHtml(m.label)+'</option>').join('');
    return '<section class="ck-qadm-card" data-qadm-row="'+idx+'" data-id="'+escapeHtml(q.id||'')+'">'+
      '<div class="ck-qadm-card-head"><div><span>'+(q.period==='weekly'?'WEEKLY QUEST':'DAILY QUEST')+'</span><b>'+escapeHtml(q.title||'새 퀘스트')+'</b><small>'+escapeHtml(q.id||'새 퀘스트')+'</small></div><button type="button" data-qadm-remove="'+idx+'">삭제</button></div>'+ 
      '<div class="ck-qadm-fields">'+
        '<label>구분<select class="ck-qadm-period"><option value="daily"'+(q.period==='daily'?' selected':'')+'>일일</option><option value="weekly"'+(q.period==='weekly'?' selected':'')+'>주간</option></select></label>'+ 
        '<label>조건<select class="ck-qadm-metric">'+metricOpts+'</select></label>'+ 
        '<label>목표량 <span class="ck-qadm-unit">('+escapeHtml(md.unit==='second'?'초':'분')+')</span><input class="ck-qadm-target" type="number" min="1" max="1000000000" value="'+Math.max(1,Number(q.target)||1)+'"></label>'+ 
        '<label>정렬<input class="ck-qadm-sort" type="number" min="-9999" max="9999" value="'+(Number(q.sort)||0)+'"></label>'+ 
        '<label class="ck-qadm-active-wrap"><span>사용</span><input class="ck-qadm-active" type="checkbox"'+(q.active!==false?' checked':'')+'></label>'+ 
        '<label class="ck-qadm-wide">퀘스트 제목<input class="ck-qadm-title" maxlength="80" value="'+escapeHtml(q.title||'')+'" placeholder="예: 도시 적응"></label>'+ 
        '<label class="ck-qadm-wide">퀘스트 내용<textarea class="ck-qadm-desc" maxlength="180" placeholder="유저에게 표시될 퀘스트 설명">'+escapeHtml(q.description||'')+'</textarea></label>'+ 
        '<label>보상 유형<select class="ck-qadm-rewardtype">'+questRewardTypeOptions(type)+'</select></label>'+ 
        '<div class="ck-qadm-money '+((type==='bank'||type==='cash')?'':'hidden')+'"><label>보상 금액<input class="ck-qadm-rewardamount" type="number" min="0" max="1000000000" step="1000" value="'+(Number(q.rewardAmount)||0)+'"></label></div>'+ 
        '<div class="ck-qadm-item '+(type==='item'?'':'hidden')+'"><label>아이템 이름<input class="ck-qadm-rewarditem" maxlength="80" value="'+escapeHtml(q.rewardItem||'')+'" placeholder="예: water"></label><label>개수<input class="ck-qadm-rewardcount" type="number" min="1" max="999" value="'+(Number(q.rewardCount)||1)+'"></label></div>'+ 
      '</div></section>';
  }).join('');
  body.innerHTML='<div class="ck-qadm-summary"><b>등록된 퀘스트 '+questAdminDraft.length+' / '+(Number(questAdminData.maxQuests)||50)+'</b><span>조건은 서버에서 실제 집계되는 항목만 선택할 수 있습니다.</span></div><div class="ck-qadm-list">'+(html||'<div class="ck-skin-empty">등록된 퀘스트가 없습니다.</div>')+'</div>';
  body.querySelectorAll('[data-qadm-remove]').forEach(btn=>btn.addEventListener('click',()=>{questAdminDraft=collectQuestAdminRows();questAdminDraft.splice(Number(btn.dataset.qadmRemove),1);renderQuestAdmin();}));
  body.querySelectorAll('.ck-qadm-rewardtype').forEach(sel=>sel.addEventListener('change',()=>{const c=sel.closest('[data-qadm-row]');c?.querySelector('.ck-qadm-money')?.classList.toggle('hidden',!(sel.value==='bank'||sel.value==='cash'));c?.querySelector('.ck-qadm-item')?.classList.toggle('hidden',sel.value!=='item');}));
  body.querySelectorAll('.ck-qadm-metric').forEach(sel=>sel.addEventListener('change',()=>{const c=sel.closest('[data-qadm-row]');const md=questMetricDef(sel.value);const u=c?.querySelector('.ck-qadm-unit');if(u)u.textContent='('+(md.unit==='second'?'초':'분')+')';}));
}

document.getElementById('questAdminAdd')?.addEventListener('click',()=>{
  if(!questAdminData)return;questAdminDraft=collectQuestAdminRows();const max=Number(questAdminData.maxQuests)||50;
  if(questAdminDraft.length>=max){showToast('퀘스트는 최대 '+max+'개까지 등록할 수 있습니다.',true);return;}
  questAdminSeq++;questAdminDraft.push({id:'new_'+Date.now()+'_'+questAdminSeq,period:'daily',metric:'playtime_min',title:'새 퀘스트',description:'',target:60,unit:'minute',rewardType:'none',rewardAmount:0,rewardItem:'',rewardCount:1,sort:(questAdminDraft.length+1)*10,active:true});
  renderQuestAdmin();const b=document.getElementById('questAdminBody');if(b)b.scrollTop=b.scrollHeight;
});
document.getElementById('questAdminSave')?.addEventListener('click',()=>{
  const btn=document.getElementById('questAdminSave');questAdminDraft=collectQuestAdminRows();btn.disabled=true;btn.textContent='저장 중…';
  fetch('https://cookie_admin/saveQuestAdmin',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({quests:questAdminDraft})}).catch(()=>{btn.disabled=false;btn.textContent='저장';showToast('퀘스트 저장 요청에 실패했습니다.',true);});
});


let newbieKitSystemData = null;
let newbieKitDraft = [];

function newbieKitTypeLabel(type){
  return ({item:'아이템',bank:'계좌',cash:'현금',vehicle:'차량'})[type] || '아이템';
}

function cloneNewbieKitRewards(rows){
  return (Array.isArray(rows)?rows:[]).map(r=>({
    type:String(r.type||'item'),
    itemName:String(r.itemName||''),
    vehicleModel:String(r.vehicleModel||((String(r.type||'')==='vehicle')?r.itemName:'')||''),
    itemCount:Number(r.itemCount)||1,
    amount:Number(r.amount)||0,
    label:String(r.label||'')
  }));
}

function renderNewbieKitSystem(){
  const body=document.getElementById('newbieKitSysBody');
  if(!body)return;
  if(!newbieKitSystemData){
    body.innerHTML='<div class="ck-skin-empty">뉴비 키트 설정을 불러오는 중…</div>';
    return;
  }

  const maxRows=Number(newbieKitSystemData.maxRows)||30;
  const rows=newbieKitDraft;
  const list=rows.map((r,idx)=>{
    const type=r.type||'item';
    return '<div class="ck-newbiekit-row" data-newbiekit-row="'+idx+'">'+
      '<div class="ck-newbiekit-order"><span>#'+(idx+1)+'</span><b>'+newbieKitTypeLabel(type)+'</b></div>'+
      '<label class="ck-newbiekit-type"><span>유형</span><select class="ck-nk-type">'+
        '<option value="item"'+(type==='item'?' selected':'')+'>아이템</option>'+
        '<option value="bank"'+(type==='bank'?' selected':'')+'>계좌</option>'+
        '<option value="cash"'+(type==='cash'?' selected':'')+'>현금</option>'+
        '<option value="vehicle"'+(type==='vehicle'?' selected':'')+'>차량</option>'+
      '</select></label>'+
      '<div class="ck-nk-item-fields '+(type==='item'?'':'hidden')+'">'+
        '<label><span>아이템 이름</span><input class="ck-nk-itemname" maxlength="80" value="'+escapeHtml(r.itemName||'')+'" placeholder="예: medikit"></label>'+
        '<label class="small"><span>개수</span><input class="ck-nk-count" type="number" min="1" max="999" value="'+Math.max(1,Number(r.itemCount)||1)+'"></label>'+
      '</div>'+
      '<div class="ck-nk-money-fields '+(type==='bank'||type==='cash'?'':'hidden')+'">'+
        '<label><span>금액</span><input class="ck-nk-amount" type="number" min="1" max="1000000000" step="1000" value="'+Math.max(0,Number(r.amount)||0)+'"></label>'+
      '</div>'+
      '<div class="ck-nk-vehicle-fields '+(type==='vehicle'?'':'hidden')+'">'+
        '<label><span>차량 SpawnCode</span><input class="ck-nk-vehiclemodel" maxlength="60" value="'+escapeHtml(r.vehicleModel||'')+'" placeholder="예: noobles"></label>'+
      '</div>'+
      '<label class="ck-newbiekit-label"><span>표시 문구 <i>선택</i></span><input class="ck-nk-label" maxlength="80" value="'+escapeHtml(r.label||'')+'" placeholder="예: 정착지원금 50,000원"></label>'+
      '<button class="ck-newbiekit-delete" type="button" data-nk-delete="'+idx+'">삭제</button>'+
    '</div>';
  }).join('');

  body.innerHTML=
    '<div class="ck-newbiekit-summary">'+
      '<div><span>현재 구성</span><b>'+rows.length+'</b><small>개 보상</small></div>'+
      '<p>아이템은 ox_inventory의 실제 아이템 이름을 입력하세요. 차량은 <b>qbx_core에 등록된 SpawnCode</b>를 입력하면 개봉 시 개인 차고(cookie_personal_v2)로 바로 지급됩니다.<br>내용물을 바꾸면 <b>이미 지급됐지만 아직 개봉하지 않은 키트</b>에도 새 구성이 적용됩니다.</p>'+
    '</div>'+
    '<div class="ck-newbiekit-list">'+(list||'<div class="ck-skin-empty">현재 내용물이 없습니다. 상단의 + 보상 추가를 눌러 구성하세요.</div>')+'</div>'+
    '<div class="ck-newbiekit-foot"><span>최대 '+maxRows+'개</span><small>뉴비 보상 키트 자체는 인증 완료 계정당 1회만 지급·개봉됩니다.</small></div>';

  body.querySelectorAll('.ck-nk-type').forEach(sel=>sel.addEventListener('change',()=>{
    const row=sel.closest('[data-newbiekit-row]');
    if(!row)return;
    row.querySelector('.ck-nk-item-fields')?.classList.toggle('hidden',sel.value!=='item');
    row.querySelector('.ck-nk-money-fields')?.classList.toggle('hidden',!(sel.value==='bank'||sel.value==='cash'));
    row.querySelector('.ck-nk-vehicle-fields')?.classList.toggle('hidden',sel.value!=='vehicle');
    const badge=row.querySelector('.ck-newbiekit-order b');if(badge)badge.textContent=newbieKitTypeLabel(sel.value);
  }));

  body.querySelectorAll('[data-nk-delete]').forEach(btn=>btn.addEventListener('click',()=>{
    newbieKitDraft=collectNewbieKitRows();
    const idx=Number(btn.dataset.nkDelete);
    if(Number.isInteger(idx)&&idx>=0)newbieKitDraft.splice(idx,1);
    renderNewbieKitSystem();
  }));
}

function collectNewbieKitRows(){
  const out=[];
  document.querySelectorAll('[data-newbiekit-row]').forEach(row=>{
    out.push({
      type:row.querySelector('.ck-nk-type')?.value||'item',
      itemName:(row.querySelector('.ck-nk-itemname')?.value||'').trim(),
      vehicleModel:(row.querySelector('.ck-nk-vehiclemodel')?.value||'').trim(),
      itemCount:Number(row.querySelector('.ck-nk-count')?.value)||0,
      amount:Number(row.querySelector('.ck-nk-amount')?.value)||0,
      label:(row.querySelector('.ck-nk-label')?.value||'').trim(),
    });
  });
  return out;
}

function requestNewbieKitSystem(){
  newbieKitSystemData=null;
  newbieKitDraft=[];
  renderNewbieKitSystem();
  fetch('https://cookie_admin/requestNewbieKitSystem',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})
    .catch(()=>{showToast('뉴비 키트 설정 요청에 실패했습니다.',true);});
}

document.getElementById('newbieKitAdd')?.addEventListener('click',()=>{
  if(!newbieKitSystemData)return;
  newbieKitDraft=collectNewbieKitRows();
  const maxRows=Number(newbieKitSystemData.maxRows)||30;
  if(newbieKitDraft.length>=maxRows){showToast('뉴비 키트 보상은 최대 '+maxRows+'개까지 등록할 수 있습니다.',true);return;}
  newbieKitDraft.push({type:'item',itemName:'',itemCount:1,amount:0,label:''});
  renderNewbieKitSystem();
  const body=document.getElementById('newbieKitSysBody');if(body)body.scrollTop=body.scrollHeight;
});

document.getElementById('newbieKitSave')?.addEventListener('click',()=>{
  const btn=document.getElementById('newbieKitSave');
  const rewards=collectNewbieKitRows();
  btn.disabled=true;btn.textContent='저장 중…';
  fetch('https://cookie_admin/saveNewbieKitSystem',{
    method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({rewards})
  }).catch(()=>{btn.disabled=false;btn.textContent='저장';showToast('뉴비 키트 저장 요청에 실패했습니다.',true);});
});

const attendanceResetModal=document.getElementById('attendanceResetModal');
const attendanceResetAgree=document.getElementById('attendanceResetAgree');
const attendanceResetConfirm=document.getElementById('attendanceResetConfirm');

function closeAttendanceReset(){
  if(!attendanceResetModal)return;
  attendanceResetModal.classList.add('hidden');
  if(attendanceResetAgree)attendanceResetAgree.checked=false;
  if(attendanceResetConfirm){attendanceResetConfirm.disabled=true;attendanceResetConfirm.textContent='월간 출석 초기화';}
}

document.getElementById('attendanceResetOpen')?.addEventListener('click',()=>{
  if(attendanceResetAgree)attendanceResetAgree.checked=false;
  if(attendanceResetConfirm)attendanceResetConfirm.disabled=true;
  attendanceResetModal?.classList.remove('hidden');
});
document.getElementById('attendanceResetCancel')?.addEventListener('click',closeAttendanceReset);
attendanceResetModal?.addEventListener('mousedown',(e)=>{if(e.target===attendanceResetModal)closeAttendanceReset();});
attendanceResetAgree?.addEventListener('change',()=>{attendanceResetConfirm.disabled=!attendanceResetAgree.checked;});
attendanceResetConfirm?.addEventListener('click',()=>{
  if(!attendanceResetAgree?.checked)return;
  attendanceResetConfirm.disabled=true;
  attendanceResetConfirm.textContent='초기화 중…';
  fetch('https://cookie_admin/resetAttendance',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({mode:'monthly'})}).catch(()=>{
    attendanceResetConfirm.disabled=false;
    attendanceResetConfirm.textContent='월간 출석 초기화';
  });
});


let coupleAdminData=null;

function renderCoupleAdmin(){
  const body=document.getElementById('coupleSysBody');
  if(!body)return;
  if(!coupleAdminData||!coupleAdminData.config){
    body.innerHTML='<div class="ck-skin-empty">설정을 불러오는 중…</div>';
    return;
  }
  const cfg=coupleAdminData.config||{};
  body.innerHTML=
    '<div class="ck-couple-admin-wrap">'+
      '<div class="ck-couple-admin-stat">'+
        '<span>현재 커플</span><strong>'+Number(coupleAdminData.activeCouples||0)+'</strong><small>쌍</small>'+
      '</div>'+
      '<div class="ck-couple-admin-settings">'+
        '<label class="ck-couple-admin-toggle"><input id="coupleShopEnabled" type="checkbox" '+(cfg.shopEnabled?'checked':'')+'><div><b>커플링 상점 운영</b><small>끄면 유저가 새 반지를 구매할 수 없습니다.</small></div></label>'+
        '<label class="ck-couple-admin-price"><span>커플링 판매 가격</span><div><input id="coupleRingPrice" type="number" min="1" max="1000000000" step="10000" value="'+Number(cfg.ringPrice||0)+'"><b>원</b></div><small>유저의 은행 계좌에서 결제됩니다.</small></label>'+
      '</div>'+
      '<div class="ck-couple-admin-flow">'+
        '<b>시스템 흐름</b>'+
        '<span>F3 커뮤니티에서 반지 구매</span><i>→</i>'+
        '<span>상대를 바라보고 CAPSLOCK</span><i>→</i>'+
        '<span>고백하기</span><i>→</i>'+
        '<span>상대 수락</span><i>→</i>'+
        '<span>커플 1일차 시작</span>'+
      '</div>'+
      '<div class="ck-couple-admin-note"><b>반지 아이템</b><span>현재 ox_inventory의 <code>diamond_ring</code>을 COOKIE 커플링으로 사용합니다.</span></div>'+
    '</div>';
}
document.getElementById('coupleSysSave')?.addEventListener('click',()=>{
  const b=document.getElementById('coupleSysSave');
  b.disabled=true;b.textContent='저장 중…';
  fetch('https://cookie_admin/saveCoupleAdmin',{
    method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({
      shopEnabled:!!document.getElementById('coupleShopEnabled')?.checked,
      ringPrice:Number(document.getElementById('coupleRingPrice')?.value)||0
    })
  }).catch(()=>{b.disabled=false;b.textContent='저장';});
});

let devModeData=null;
let devModeError='';
let devModeRequestSeq=0;
let devModeToggleArmedUntil=0;

function devEsc(v){
  return escapeHtml(String(v==null?'':v));
}
function devReasonLabel(r){
  if(r==='admin')return '관리자 자동 허용';
  if(r==='whitelist')return '화이트리스트';
  return '미허용';
}
function renderDevMode(){
  const body=document.getElementById('devModeAdminBody');
  if(!body)return;

  if(devModeError){
    body.innerHTML=
      '<div class="ck-rankadm-error"><b>개발모드 데이터를 불러오지 못했습니다.</b><span>'+devEsc(devModeError)+'</span><button id="devModeRetry" type="button">다시 불러오기</button></div>';
    document.getElementById('devModeRetry')?.addEventListener('click',requestDevModeData);
    return;
  }
  if(!devModeData){
    body.innerHTML='<div class="ck-skin-empty">개발모드 설정을 불러오는 중…</div>';
    return;
  }

  const enabled=devModeData.enabled===true;
  const online=Array.isArray(devModeData.online)?devModeData.online:[];
  const whitelist=Array.isArray(devModeData.whitelist)?devModeData.whitelist:[];

  const onlineHtml=online.map(p=>{
    const label=devEsc(p.nickname||p.name||('ID '+p.serverId));
    const sub='고번 '+devEsc(p.gobun||'-')+' · ID '+devEsc(p.serverId)+' · '+devEsc(p.licenseMasked||'');
    const allowed=p.allowed===true;
    return '<div class="ck-dev-row">'+
      '<div class="ck-dev-person"><b>'+label+'</b><small>'+sub+'</small></div>'+
      '<span class="ck-dev-access '+(allowed?'ok':'no')+'">'+devReasonLabel(p.reason)+'</span>'+
      (p.reason==='admin'
        ? '<button class="ck-dev-static" type="button" disabled>자동 허용</button>'
        : (allowed
          ? '<button class="ck-dev-remove-online" data-license="'+devEsc(p.license)+'" type="button">허용 해제</button>'
          : '<button class="ck-dev-add-online" data-server-id="'+devEsc(p.serverId)+'" data-label="'+label+'" type="button">테스터 허용</button>'))+
    '</div>';
  }).join('');

  const whitelistHtml=whitelist.map(w=>
    '<div class="ck-dev-wl-row">'+
      '<div><b>'+devEsc(w.label||'테스터')+'</b><small>'+devEsc(w.licenseMasked||w.license||'')+(w.note?' · '+devEsc(w.note):'')+'</small></div>'+
      '<div class="ck-dev-wl-meta"><span>추가: '+devEsc(w.added_by||'-')+'</span><span>최근 접속: '+devEsc(w.last_join_at||'-')+'</span></div>'+
      '<button class="ck-dev-remove" data-license="'+devEsc(w.license)+'" type="button">삭제</button>'+
    '</div>'
  ).join('');

  body.innerHTML=
    '<div class="ck-dev-hero '+(enabled?'enabled':'disabled')+'">'+
      '<div class="ck-dev-status-icon">'+(enabled?'🔒':'🔓')+'</div>'+
      '<div class="ck-dev-status-copy"><span>현재 접속 정책</span><b>'+(enabled?'개발모드 ON':'개발모드 OFF')+'</b><small>'+(enabled?'관리자와 허가된 테스터만 접속할 수 있습니다.':'일반 유저도 서버에 접속할 수 있습니다.')+'</small></div>'+
      '<button id="devModeToggle" class="'+(enabled?'danger':'on')+'" type="button">'+(enabled?'개발모드 끄기':'개발모드 켜기')+'</button>'+
    '</div>'+
    '<div class="ck-dev-message">'+
      '<label><span>차단 안내 문구</span><input id="devModeMessage" maxlength="255" value="'+devEsc(devModeData.message||'')+'"><small>화이트리스트에 없는 유저가 접속할 때 표시됩니다.</small></label>'+
    '</div>'+
    '<div class="ck-dev-note"><b>관리자는 자동 허용</b><span>활성 cookie_admin 계정은 화이트리스트에 없어도 접속 가능합니다. 개발모드를 켠 관리자 본인도 자동 등록됩니다.</span></div>'+
    '<div class="ck-dev-section-head"><div><b>현재 접속자</b><small>테스터로 허용할 사람을 현재 서버에서 바로 선택할 수 있습니다.</small></div><button id="devModeRefresh" type="button">새로고침</button></div>'+
    '<div class="ck-dev-online">'+(onlineHtml||'<div class="ck-skin-empty">현재 접속자가 없습니다.</div>')+'</div>'+
    '<div class="ck-dev-manual">'+
      '<div><b>직접 화이트리스트 추가</b><small>접속자가 오프라인이어도 license 식별자로 미리 등록할 수 있습니다.</small></div>'+
      '<div class="ck-dev-manual-grid"><input id="devManualLicense" placeholder="license:xxxxxxxxxxxxxxxx"><input id="devManualLabel" placeholder="표시 이름 / 테스터명"><input id="devManualNote" placeholder="메모 (선택)"><button id="devManualAdd" type="button">추가</button></div>'+
    '</div>'+
    '<div class="ck-dev-section-head"><div><b>등록된 테스터</b><small>'+whitelist.length+'명 · 관리자는 별도로 자동 허용됩니다.</small></div></div>'+
    '<div class="ck-dev-whitelist">'+(whitelistHtml||'<div class="ck-skin-empty">등록된 테스터가 없습니다.</div>')+'</div>';

  document.getElementById('devModeRefresh')?.addEventListener('click',requestDevModeData);

  document.getElementById('devModeToggle')?.addEventListener('click',()=>{
    const btn=document.getElementById('devModeToggle');
    if(Date.now()>devModeToggleArmedUntil){
      devModeToggleArmedUntil=Date.now()+5000;
      btn.textContent=enabled?'한 번 더 눌러 개발모드 끄기':'한 번 더 눌러 개발모드 켜기';
      showToast(enabled?'5초 안에 한 번 더 누르면 일반 접속을 허용합니다.':'5초 안에 한 번 더 누르면 미허용 접속자를 차단합니다.',false);
      return;
    }
    devModeToggleArmedUntil=0;
    btn.disabled=true;btn.textContent='적용 중…';
    fetch('https://cookie_admin/setDevMode',{
      method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({enabled:!enabled,message:document.getElementById('devModeMessage')?.value||''})
    }).catch(()=>{btn.disabled=false;renderDevMode();showToast('개발모드 설정 요청에 실패했습니다.',true);});
  });

  document.querySelectorAll('.ck-dev-add-online').forEach(btn=>btn.addEventListener('click',()=>{
    btn.disabled=true;btn.textContent='추가 중…';
    fetch('https://cookie_admin/addDevWhitelist',{
      method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({serverId:Number(btn.dataset.serverId),label:btn.dataset.label||'',note:'현재 접속자에서 추가'})
    }).catch(()=>{btn.disabled=false;btn.textContent='테스터 허용';});
  }));

  document.querySelectorAll('.ck-dev-remove,.ck-dev-remove-online').forEach(btn=>btn.addEventListener('click',()=>{
    btn.disabled=true;
    fetch('https://cookie_admin/removeDevWhitelist',{
      method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({license:btn.dataset.license||''})
    }).catch(()=>{btn.disabled=false;});
  }));

  document.getElementById('devManualAdd')?.addEventListener('click',()=>{
    const lic=(document.getElementById('devManualLicense')?.value||'').trim();
    const label=(document.getElementById('devManualLabel')?.value||'').trim();
    const note=(document.getElementById('devManualNote')?.value||'').trim();
    if(!lic){showToast('license 식별자를 입력하세요.',true);return;}
    const btn=document.getElementById('devManualAdd');
    btn.disabled=true;btn.textContent='추가 중…';
    fetch('https://cookie_admin/addDevWhitelist',{
      method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({license:lic,label:label,note:note})
    }).catch(()=>{btn.disabled=false;btn.textContent='추가';});
  });
}

function requestDevModeData(){
  devModeData=null;devModeError='';devModeToggleArmedUntil=0;renderDevMode();
  const seq=++devModeRequestSeq;
  fetch('https://cookie_admin/requestDevMode',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})
    .catch(()=>{if(seq===devModeRequestSeq&&!devModeData){devModeError='NUI 요청 전송에 실패했습니다.';renderDevMode();}});
  setTimeout(()=>{
    if(seq===devModeRequestSeq&&!devModeData&&!devModeError){
      devModeError='5초 동안 서버 응답이 없습니다. cookie_admin 콘솔 로그를 확인하세요.';
      renderDevMode();
    }
  },5000);
}

let economySystemData=null;
let rankingAdminData=null;
let rankingAdminError='';
let rankingAdminSelected=new Set();
let rankingAdminRequestSeq=0;
let rankingResetArmedUntil=0;
function renderEconomySystem(){
  const body=document.getElementById('economySysBody');
  if(!body)return;
  if(!economySystemData){
    body.innerHTML='<div class="ck-skin-empty">설정을 불러오는 중…</div>';
    return;
  }
  body.innerHTML=
    '<div class="ck-couple-admin-wrap">'+
      '<div class="ck-couple-admin-settings">'+
        '<label class="ck-couple-admin-price"><span>시민 30분 급여</span><div><input id="economyCitizenSalary" type="number" min="0" max="1000000000" step="10" value="'+Number(economySystemData.citizenSalary||0)+'"><b>원</b></div><small>팩션/시민직이 없는 시민(unemployed)에게 30분마다 계좌로 지급됩니다.</small></label>'+
      '</div>'+
      '<div class="ck-couple-admin-note"><b>실시간 적용</b><span>저장 즉시 다음 30분 시민 급여부터 적용됩니다. Qbox 기본 급여와 중복 지급되지 않습니다.</span></div>'+
    '</div>';
}

document.getElementById('economySysSave')?.addEventListener('click',()=>{
  const salary=Math.floor(Number(document.getElementById('economyCitizenSalary')?.value)||0);
  if(salary<0){showToast('급여를 확인하세요',true);return;}
  const b=document.getElementById('economySysSave');
  if(b){b.disabled=true;b.textContent='저장 중…';}
  fetch('https://cookie_admin/saveEconomySystem',{
    method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({citizenSalary:salary})
  }).catch(()=>{if(b){b.disabled=false;b.textContent='저장';}});
});


function rankResetTime(v){
  if(!v)return '초기화 이력 없음';
  return String(v);
}

function renderRankingAdmin(){
  const body=document.getElementById('rankingAdminBody');
  const reset=document.getElementById('rankingResetSelected');
  if(!body)return;
  if(rankingAdminError){
    body.innerHTML='<div class="ck-rankadm-error"><b>순위표 관리 데이터를 불러오지 못했습니다.</b><span>'+escapeHtml(rankingAdminError)+'</span><button id="rankingRetry" type="button">다시 불러오기</button></div>';
    document.getElementById('rankingRetry')?.addEventListener('click',requestRankingAdminData);
    if(reset)reset.disabled=true;
    return;
  }
  if(!rankingAdminData){
    body.innerHTML='<div class="ck-skin-empty">순위표 상태를 불러오는 중…</div>';
    if(reset)reset.disabled=true;
    return;
  }
  const rows=Array.isArray(rankingAdminData.categories)?rankingAdminData.categories:[];
  body.innerHTML='<div class="ck-rankadm-warning"><b>원본 데이터는 삭제되지 않습니다.</b><span>ESC 순위 계산 기준만 현재 시점으로 이동합니다. 낚시·광물은 새 시즌 기록 테이블만 비웁니다.</span></div>'+
    '<div class="ck-rankadm-grid">'+rows.map(r=>{
      const on=rankingAdminSelected.has(r.key);
      return '<button class="ck-rankadm-card'+(on?' selected':'')+'" data-rank-key="'+escapeHtml(r.key)+'" type="button">'+
        '<span class="ck-rankadm-check">'+(on?'✓':'')+'</span>'+
        '<span class="ck-rankadm-icon">'+escapeHtml(r.icon||'🏆')+'</span>'+
        '<div class="ck-rankadm-info"><b>'+escapeHtml(r.label||r.key)+'</b><small>'+escapeHtml(r.description||'')+'</small>'+
        '<div class="ck-rankadm-last"><span>마지막 초기화</span><strong>'+escapeHtml(rankResetTime(r.resetAt))+'</strong></div>'+
        '<div class="ck-rankadm-by">'+(r.resetBy?('처리: '+escapeHtml(r.resetBy)):'아직 초기화한 적 없음')+(Number(r.resetCount||0)>0?(' · '+Number(r.resetCount)+'회'):'')+'</div></div>'+
      '</button>';
    }).join('')+'</div>';
  body.querySelectorAll('[data-rank-key]').forEach(card=>card.addEventListener('click',()=>{
    const key=card.dataset.rankKey;
    if(rankingAdminSelected.has(key))rankingAdminSelected.delete(key);else rankingAdminSelected.add(key);
    rankingResetArmedUntil=0;
    renderRankingAdmin();
  }));
  if(reset){reset.disabled=rankingAdminSelected.size===0;reset.textContent=rankingAdminSelected.size?('선택 초기화 ('+rankingAdminSelected.size+')'):'선택 초기화';}
}

function requestRankingAdminData(){
  rankingAdminData=null;rankingAdminError='';rankingResetArmedUntil=0;renderRankingAdmin();
  const seq=++rankingAdminRequestSeq;
  fetch('https://cookie_admin/requestRankingAdmin',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})
    .catch(()=>{if(seq===rankingAdminRequestSeq&&!rankingAdminData){rankingAdminError='NUI 요청 전송에 실패했습니다.';renderRankingAdmin();}});
  setTimeout(()=>{
    if(seq===rankingAdminRequestSeq&&!rankingAdminData&&!rankingAdminError){
      rankingAdminError='5초 동안 서버 응답이 없습니다. 서버 콘솔의 [cookie_admin][ranking] 오류를 확인하세요.';
      renderRankingAdmin();
    }
  },5000);
}

function closeSystemWindows(){
  document.querySelectorAll('.ck-system-window-overlay').forEach(w=>w.classList.add('hidden'));
}

function requestMiningSystemData(){
  miningSystemData=null;
  miningSystemError='';
  const seq=++miningSystemRequestSeq;
  renderMiningSystem();
  fetch('https://cookie_admin/requestMiningSystem',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})
    .catch(()=>{ if(seq===miningSystemRequestSeq && !miningSystemData){ miningSystemError='NUI 요청 전송에 실패했습니다'; renderMiningSystem(); } });
  setTimeout(()=>{
    if(seq===miningSystemRequestSeq && !miningSystemData && !miningSystemError){
      miningSystemError='5초 동안 서버 응답이 없습니다. cookie_mining 실행 상태와 서버 콘솔 오류를 확인하세요.';
      renderMiningSystem();
    }
  },5000);
}

function openSystemWindow(k){
  closeSystemWindows();
  const win=document.querySelector('[data-system-window="'+k+'"]');
  if(!win)return;
  win.classList.remove('hidden');

  if(k==='devmode'){
    requestDevModeData();
  }
  if(k==='ranking'){
    rankingAdminSelected=new Set();
    requestRankingAdminData();
  }
  if(k==='fishing'){
    fishingSystemData=null;
    renderFishingSystem();
    fetch('https://cookie_admin/requestFishingSystem',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).catch(()=>{});
  }
  if(k==='mining'){
    requestMiningSystemData();
  }
  if(k==='jobs'){
    jobLevelSystemData=null;
    renderJobLevelSystem();
    fetch('https://cookie_admin/requestJobLevelSystem',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).catch(()=>{});
  }
  if(k==='economy'){
    economySystemData=null;
    renderEconomySystem();
    fetch('https://cookie_admin/requestEconomySystem',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).catch(()=>{});
  }
  if(k==='kuji'){
    kujiSystemDirty=false;
    kujiSystemData=null;
    kujiDraftPrizes=[];
    renderKujiSystem();
    fetch('https://cookie_admin/requestKujiSystem',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).catch(()=>{});
  }
  if(k==='attendance'){
    attendanceAdminData=null;
    attendanceDailyDraft=[];
    attendanceMonthlyDraft=[];
    attendanceAdminTab='daily';
    renderAttendanceAdmin();
    fetch('https://cookie_admin/requestAttendanceAdmin',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).catch(()=>{});
  }
  if(k==='quest'){
    questAdminData=null;
    questAdminDraft=[];
    renderQuestAdmin();
    fetch('https://cookie_admin/requestQuestAdmin',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).catch(()=>{});
  }
  if(k==='newbiekit'){
    requestNewbieKitSystem();
  }
  if(k==='keyguide'){
    keyGuideAdminData=null;
    renderKeyGuideAdmin();
    fetch('https://cookie_admin/requestKeyGuideAdmin',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).catch(()=>{});
  }
  if(k==='couple'){
    coupleAdminData=null;
    renderCoupleAdmin();
    fetch('https://cookie_admin/requestCoupleAdmin',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).catch(()=>{});
  }
}

document.querySelectorAll('.ck-system-menu-btn').forEach(btn=>{
  btn.addEventListener('click',()=>openSystemWindow(btn.dataset.system));
});

document.querySelectorAll('[data-system-close]').forEach(btn=>{
  btn.addEventListener('click',()=>closeSystemWindows());
});


document.getElementById('rankingSelectAll')?.addEventListener('click',()=>{
  const rows=(rankingAdminData&&Array.isArray(rankingAdminData.categories))?rankingAdminData.categories:[];
  const allSelected=rows.length>0&&rows.every(r=>rankingAdminSelected.has(r.key));
  rankingAdminSelected=new Set(allSelected?[]:rows.map(r=>r.key));
  rankingResetArmedUntil=0;
  renderRankingAdmin();
});

document.getElementById('rankingResetSelected')?.addEventListener('click',()=>{
  const keys=[...rankingAdminSelected];
  if(!keys.length)return;
  const btn=document.getElementById('rankingResetSelected');
  if(Date.now()>rankingResetArmedUntil){
    rankingResetArmedUntil=Date.now()+5000;
    if(btn){btn.disabled=false;btn.textContent='한 번 더 눌러 초기화';}
    showToast('5초 안에 한 번 더 누르면 선택한 순위가 초기화됩니다.',false);
    return;
  }
  rankingResetArmedUntil=0;
  if(btn){btn.disabled=true;btn.textContent='초기화 중…';}
  fetch('https://cookie_admin/resetRankings',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({categories:keys})})
    .catch(()=>{showToast('순위표 초기화 요청에 실패했습니다.',true);if(btn){btn.disabled=false;btn.textContent='선택 초기화';}});
});

document.querySelectorAll('.ck-system-window-overlay').forEach(win=>{
  win.addEventListener('mousedown',(e)=>{if(e.target===win)closeSystemWindows();});
});

document.addEventListener('keydown',(e)=>{
  if(e.key==='Escape'){
    const open=[...document.querySelectorAll('.ck-system-window-overlay')].find(w=>!w.classList.contains('hidden'));
    if(open){e.preventDefault();closeSystemWindows();}
  }
});

window.addEventListener('message',(e)=>{
  const d=e.data||{};
  if(d.action==='devModeData'){
    devModeRequestSeq++;devModeError='';devModeToggleArmedUntil=0;
    devModeData=d.data||{};
    renderDevMode();
    return;
  }
  if(d.action==='devModeError'){
    devModeRequestSeq++;devModeToggleArmedUntil=0;
    devModeError=String(d.message||'개발모드 데이터를 불러오지 못했습니다.');
    renderDevMode();
    return;
  }
  if(d.action==='rankingAdminData'){
    rankingAdminRequestSeq++;rankingResetArmedUntil=0;
    rankingAdminError='';
    rankingAdminData=d.data||{categories:[]};
    rankingAdminSelected=new Set();
    renderRankingAdmin();
    return;
  }
  if(d.action==='rankingAdminError'){
    rankingAdminRequestSeq++;rankingResetArmedUntil=0;
    rankingAdminError=String(d.message||'순위표 관리 데이터를 불러오지 못했습니다.');
    renderRankingAdmin();
    return;
  }
  if(d.action==='fishingCollectionData'){
    fishCollectionData=d.data||{};
    renderFishCollectionModal();
  }
  if(d.action==='fishingZoneSettingsData'){
    fishPointSettingsError='';
    fishPointSettingsData=d.data||{};
    renderFishingPointFishList();
  }
  if(d.action==='fishingZoneSettingsError'){fishPointSettingsError=String(d.message||'어종 설정을 불러오지 못했습니다.');renderFishingPointFishList();return;}
  if(d.action==='miningZoneSettingsError'){miningZoneSettingsError=String(d.message||'광물 설정을 불러오지 못했습니다.');renderMiningZoneMinerals();return;}
  if(d.action==='miningZoneSettingsData'){
    miningZoneSettingsError='';
    miningZoneSettingsData=d.data||{};
    renderMiningZoneMinerals();
  }
  if(d.action==='miningCollectionData'){
    miningCollectionData=d.data||{};
    renderFishCollectionModal();
  }
  if(d.action==='jobLevelsRefresh'){
    jobLevelsData=d.data||[];
    const m=document.getElementById('ckJobLevelModal');
    if(m){m.remove();const b=document.getElementById('uJobLevelBtn');if(b)b.click();}
  }
  if(d.action==='jobLevelSystemData'){
    jobLevelSystemData=d.data||{};
    renderJobLevelSystem();
  }
  if(d.action==='economySystemData'){
    economySystemData=d.data||{};
    renderEconomySystem();
    const b=document.getElementById('economySysSave');
    if(b){b.disabled=false;b.textContent='저장';}
  }
  if(d.action==='newbieKitSystemData'){
    newbieKitSystemData=d.data||{};
    newbieKitDraft=cloneNewbieKitRewards(newbieKitSystemData.rewards||[]);
    renderNewbieKitSystem();
    const b=document.getElementById('newbieKitSave');
    if(b){b.disabled=false;b.textContent='저장';}
    if(d.message)showToast(d.message,!!d.isError);
  }
  if(d.action==='newbieKitSystemSaved'){
    const b=document.getElementById('newbieKitSave');
    if(b){b.disabled=false;b.textContent='저장';}
    if(d.message)showToast(d.message,d.ok!==true);
  }
  if(d.action==='coupleData'){
    coupleLoadToken++;
    coupleData=d.data||{};
    coupleBuyBusy=false;
    renderCoupleModal();
    if(d.message)showToast(d.message,!!d.isError);
  }
  if(d.action==='coupleInteraction'){
    showCoupleInteraction(d.data||{});
  }
  if(d.action==='coupleActionClose'){
    document.getElementById('ckCoupleInteraction')?.remove();
    coupleInteractionData=null;
  }
  if(d.action==='coupleProposalIncoming'){
    showCoupleProposal(d.data||{});
  }
  if(d.action==='coupleProposalClose'){
    closeCoupleProposal();
  }
  if(d.action==='coupleAdminData'){
    coupleAdminData=d.data||{};
    renderCoupleAdmin();
  }
  if(d.action==='coupleAdminSaved'){
    const b=document.getElementById('coupleSysSave');
    if(b){b.disabled=false;b.textContent='저장';}
    if(d.message)showToast(d.message,!d.ok);
  }
  if(d.action==='keyGuideData'){
    COOKIE_KEY_GUIDE_CATEGORIES=Array.isArray(d.data?.categories)?d.data.categories:[];
    activeKeyGuideCategoryId=COOKIE_KEY_GUIDE_CATEGORIES[0]?.id??null;
    COOKIE_KEY_GUIDE=Array.isArray(COOKIE_KEY_GUIDE_CATEGORIES[0]?.items)?COOKIE_KEY_GUIDE_CATEGORIES[0].items:[];
    renderKeyGuideCategoryTabs();
    renderMechanicalKeyboard();
  }
  if(d.action==='keyGuideAdminData'){
    keyGuideAdminData=d.data||{categories:[],factions:[]};
    renderKeyGuideAdmin();
  }
  if(d.action==='keyGuideAdminSaved'){
    const b=document.getElementById('keyGuideSysSave');
    if(b){b.disabled=false;b.textContent='저장';}
    if(d.message)showToast(d.message,!d.ok);
  }
  if(d.action==='attendanceData'){
    attendanceData=d.data||{};
    attendanceClaimBusy=false;
    renderAttendanceModal();
    renderAttendanceHub();
    if(d.message)showToast(d.message,!!d.isError);
  }
  if(d.action==='attendanceAdminData'){
    attendanceAdminData=d.data||{};
    attendanceDailyDraft=cloneAttendanceDailyRows(attendanceAdminData.daily?.rewards||[]);
    attendanceMonthlyDraft=cloneAttendanceMonthlyRows(attendanceAdminData.monthly?.rewards||[]);
    renderAttendanceAdmin();
  }
  if(d.action==='attendanceAdminSaved'){
    const b=document.getElementById('attendanceSysSave');
    if(b){b.disabled=false;b.textContent='저장';}
    if(d.message)showToast(d.message,!d.ok);
  }
  if(d.action==='questAdminData'){
    questAdminData=d.data||{};
    questAdminDraft=cloneQuestAdminRows(questAdminData.quests||[]);
    renderQuestAdmin();
  }
  if(d.action==='questAdminSaved'){
    const b=document.getElementById('questAdminSave');
    if(b){b.disabled=false;b.textContent='저장';}
    if(d.message)showToast(d.message,!d.ok);
  }
  if(d.action==='attendanceResetResult'){
    closeAttendanceReset();
    if(d.message)showToast(d.message,!d.ok);
    if(d.ok){
      attendanceAdminData=null;
      renderAttendanceAdmin();
      fetch('https://cookie_admin/requestAttendanceAdmin',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).catch(()=>{});
    }
  }
});



document.addEventListener('keydown',(e)=>{
  if(e.key!=='Escape')return;
  if(attendanceResetModal && !attendanceResetModal.classList.contains('hidden')){
    e.stopImmediatePropagation();
    closeAttendanceReset();
    return;
  }
  const openSystem=document.querySelector('.ck-system-window-overlay:not(.hidden)');
  if(openSystem){
    e.stopImmediatePropagation();
    closeSystemWindows();
  }
},true);


document.addEventListener('keydown',(e)=>{
  if(e.key!=='Escape')return;
  const proposal=document.getElementById('ckCoupleProposal');
  if(proposal){
    e.stopImmediatePropagation();
    return; // proposal requires accept/reject or timeout
  }
  const action=document.getElementById('ckCoupleInteraction');
  if(action){
    e.stopImmediatePropagation();
    closeCoupleInteraction();
    return;
  }
  const modal=document.getElementById('ckCoupleModal');
  if(modal){
    e.stopImmediatePropagation();
    closeCoupleModal();
  }
},true);


document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  const keyGuide = document.getElementById('ckKeyGuideModal');
  if (keyGuide) {
    e.stopImmediatePropagation();
    closeKeyGuideModal();
  }
}, true);

document.addEventListener('keydown',(e)=>{
  if(e.key!=='Escape')return;
  const modal=document.getElementById('ckKeyGuideModal');
  if(modal){
    e.stopImmediatePropagation();
    closeKeyGuideModal();
  }
},true);


// ============================================================
// COOKIE OPEN EVENT V1
// F3 > 내정보 > 상점 · 이벤트 > 이벤트
// ============================================================
let cookieOpenEventData = null;
let cookieOpenEventBusy = false;

function cookieEventFallbackData(){
  const jobs=[
    ['taxi','택시기사','오픈 택시왕','「초대 택시왕」'],
    ['trucker','트럭커','오픈 트럭왕','「초대 트럭왕」'],
    ['delivery','배달기사','오픈 배달왕','「초대 배달왕」'],
    ['labor','건설 인부','오픈 건설왕','「초대 건설왕」'],
    ['mechanic','정비공','오픈 정비왕','「초대 정비왕」'],
  ];
  const events=jobs.map(([jobKey,label,title,rewardTitle])=>({
    id:'open_job_'+jobKey,
    metric:'job', jobKey, title,
    description:'오픈 이벤트 기간 동안 '+label+' 근무시간이 가장 긴 시민이 우승합니다. 다른 직업의 근무시간과는 합산하지 않습니다.',
    badge:label+' 1위',
    rewards:[{kind:'칭호',text:rewardTitle}],
    ranking:[], my:{rank:null,minute:0,jobKey,jobLabel:label},
  }));
  events.push({id:'open_fishing_king',metric:'activity',activityKey:'fishing',activityLabel:'낚시',title:'오픈 낚시왕',description:'오픈 이벤트 기간 동안 실제 낚시를 가장 오래 진행한 시민이 우승합니다.',badge:'낚시시간 1위',rewards:[{kind:'칭호',text:'「초대 낚시왕」'}],ranking:[],my:{rank:null,seconds:0}});
  events.push({id:'open_mining_king',metric:'activity',activityKey:'mining',activityLabel:'광질',title:'오픈 광부왕',description:'오픈 이벤트 기간 동안 실제 광질을 가장 오래 진행한 시민이 우승합니다.',badge:'광질시간 1위',rewards:[{kind:'칭호',text:'「초대 광부왕」'}],ranking:[],my:{rank:null,seconds:0}});
  events.push({
    id:'open_playtime', metric:'rp', title:'도시의 개척자',
    description:'오픈 이벤트 기간 동안 쿠키서버에 가장 오래 접속해 RP 시간을 기록한 시민이 우승합니다.',
    badge:'접속시간 1위',
    rewards:[{kind:'칭호',text:'「초대 접속왕」'}],
    ranking:[], my:{rank:null,minute:0},
  });
  return {enabled:true,startedAt:'서버 기록 동기화 중',canManage:false,events};
}

function cookieEventTime(minute){
  const m=Math.max(0,Number(minute)||0);
  const d=Math.floor(m/1440), h=Math.floor((m%1440)/60), mm=Math.floor(m%60);
  if(d>0)return d+'일 '+h+'시간 '+mm+'분';
  if(h>0)return h+'시간 '+mm+'분';
  return mm+'분';
}

function cookieEventSeconds(seconds){
  const s=Math.max(0,Number(seconds)||0);
  const h=Math.floor(s/3600),m=Math.floor((s%3600)/60),ss=Math.floor(s%60);
  if(h>0)return h+'시간 '+m+'분 '+ss+'초';
  if(m>0)return m+'분 '+ss+'초';
  return ss+'초';
}

function cookieEventRankRows(rows, ev){
  rows=Array.isArray(rows)?rows:[];
  if(!rows.length)return '<div class="ck-evt-empty">아직 집계된 기록이 없습니다.</div>';
  const metric=ev?.metric||'rp';
  return rows.slice(0,5).map((r,i)=>{
    const rank=Number(r.rank||i+1);
    const medal=rank===1?'🥇':rank===2?'🥈':rank===3?'🥉':String(rank);
    let detail='RP 접속 시간',value=cookieEventTime(r.minute||0);
    if(metric==='job')detail=escapeHtml(r.jobLabel||r.jobKey||'-');
    else if(metric==='activity'){detail=escapeHtml(ev?.activityLabel||r.activityKey||'활동')+' 활동시간';value=cookieEventSeconds(r.seconds||0);}
    else if(metric==='purity'){detail=escapeHtml((r.mineralLabel||r.mineral||'-')+' · '+(r.rarityLabel||'-'));value='순도 '+Number(r.purity||0)+'%';}
    return '<div class="ck-evt-rank '+(rank<=3?'top':'')+'">'+
      '<span class="ck-evt-rank-no">'+medal+'</span>'+
      '<span class="ck-evt-rank-user"><b>'+escapeHtml(r.nickname||('고번 '+(r.gobun||'-')))+'</b><small>고번 '+escapeHtml(String(r.gobun||'-'))+' · '+detail+'</small></span>'+
      '<strong>'+value+'</strong>'+
    '</div>';
  }).join('');
}

function cookieEventRewardRows(rewards){
  rewards=Array.isArray(rewards)?rewards:[];
  return rewards.map(r=>'<span class="ck-evt-reward"><b>'+escapeHtml(r.kind||'보상')+'</b>'+escapeHtml(r.text||'-')+'</span>').join('');
}

let cookieEventHubTab = 'event';
let cookieEventHubStandalone = false;
let cookieEventHubHideQuest = false;
let cookieQuestData = null;
let cookieQuestClaimBusy = false;

function cookieQuestValue(value, unit){
  const n=Math.max(0,Math.floor(Number(value)||0));
  if(unit==='second'){
    const h=Math.floor(n/3600),m=Math.floor((n%3600)/60),sec=n%60;
    if(h>0)return h+'시간 '+m+'분';
    if(m>0)return m+'분 '+sec+'초';
    return sec+'초';
  }
  if(unit==='minute')return cookieEventTime(n);
  return n.toLocaleString('ko-KR');
}

function cookieEventHubRoot(tab){
  if(tab==='attendance_daily'||tab==='attendance_monthly')return 'attendance';
  if(tab==='quest_daily'||tab==='quest_weekly')return 'quest';
  return 'event';
}

function renderCookieEventHubTabs(){
  const root=cookieEventHubRoot(cookieEventHubTab);
  document.querySelectorAll('#ckEventModal [data-eventhub-main]').forEach(btn=>{
    btn.classList.toggle('on',btn.dataset.eventhubMain===root);
  });

  const sub=document.getElementById('ckEventSubNav');
  if(!sub)return;

  if(root==='attendance'){
    sub.innerHTML=
      '<button data-eventhub-sub="attendance_daily">일일 출석체크</button>'+ 
      '<button data-eventhub-sub="attendance_monthly">월간 출석체크</button>';
  }else if(root==='quest'&&!cookieEventHubHideQuest){
    sub.innerHTML=
      '<button data-eventhub-sub="quest_daily">일일 퀘스트</button>'+ 
      '<button data-eventhub-sub="quest_weekly">주간 퀘스트</button>';
  }else{
    sub.innerHTML='<div class="ck-eventhub-current"><b>오픈 이벤트</b><span>현재 진행 중인 이벤트와 순위를 확인할 수 있습니다.</span></div>';
  }

  sub.querySelectorAll('[data-eventhub-sub]').forEach(btn=>{
    btn.classList.toggle('on',btn.dataset.eventhubSub===cookieEventHubTab);
    btn.addEventListener('click',()=>setCookieEventHubTab(btn.dataset.eventhubSub));
  });
}

function requestAttendanceForHub(){
  attendanceData=null;
  attendanceClaimBusy=false;
  renderAttendanceHub();
  fetch('https://cookie_admin/requestAttendance',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).catch(()=>{});
}

function requestQuestsForHub(){
  cookieQuestData=null;
  renderQuestHub(cookieEventHubTab==='quest_weekly'?'weekly':'daily');
  fetch('https://cookie_admin/requestQuests',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).catch(()=>{});
}

function setCookieEventHubTab(tab){
  const allowed=['event','attendance_daily','attendance_monthly','quest_daily','quest_weekly'];
  cookieEventHubTab=allowed.includes(tab)?tab:'event';
  if(cookieEventHubHideQuest&&cookieEventHubRoot(cookieEventHubTab)==='quest')cookieEventHubTab='event';

  renderCookieEventHubTabs();
  if(cookieEventHubTab==='event'){
    renderCookieEventModal();
    cookieEventRequest('requestOpenEvents',{}).catch(()=>{});
  }else if(cookieEventHubRoot(cookieEventHubTab)==='attendance'){
    requestAttendanceForHub();
  }else{
    requestQuestsForHub();
  }
}

function dailyAttendanceProgressText(minute){
  minute=Math.max(0,Math.floor(Number(minute)||0));
  const h=Math.floor(minute/60),m=minute%60;
  if(h>0&&m>0)return h+'시간 '+m+'분';
  if(h>0)return h+'시간';
  return m+'분';
}

function renderDailyAttendanceHub(d){
  const body=document.getElementById('ckEventBody');if(!body)return;
  const minute=Math.max(0,Number(d.minute)||0);
  const rewards=Array.isArray(d.rewards)?d.rewards:[];
  const cards=rewards.map(r=>{
    const req=Math.max(1,Number(r.requiredMinutes)||1);
    const pct=Math.max(0,Math.min(100,Math.floor(minute/req*100)));
    const claimed=!!r.claimed,unlocked=!!r.unlocked,canClaim=!!r.canClaim;
    const state=claimed?'claimed':(unlocked?'ready':'locked');
    const status=claimed?'수령 완료':(unlocked?'수령 가능':'진행 중');
    const btnText=claimed?'수령 완료':(canClaim?'보상 받기':(!d.enabled?'비활성화':'조건 미달'));
    return '<section class="ck-attdaily-user-card '+state+'">'+
      '<div class="ck-attdaily-user-head"><div><span>PLAYTIME REWARD</span><h3>'+escapeHtml(attendanceMinuteLabel(req))+' 접속</h3></div><em>'+status+'</em></div>'+ 
      '<div class="ck-attdaily-user-reward"><span>보상</span><b>'+escapeHtml(attendanceRewardText(r))+'</b></div>'+ 
      '<div class="ck-attdaily-user-progress"><div><span>'+dailyAttendanceProgressText(minute)+'</span><b>/ '+attendanceMinuteLabel(req)+'</b></div><strong>'+pct+'%</strong></div>'+ 
      '<div class="ck-attdaily-user-bar"><i style="width:'+pct+'%"></i></div>'+ 
      '<button class="ck-attdaily-user-claim" data-attdaily-claim="'+Number(r.id)+'" '+(canClaim?'':'disabled')+'>'+btnText+'</button>'+ 
    '</section>';
  }).join('');

  body.innerHTML=
    '<div class="ck-evt-status '+(d.enabled?'on':'off')+'"><div><b>일일 출석체크</b><span>'+escapeHtml(d.cycleLabel||'-')+' · 오늘 접속한 시간이 누적됩니다.</span></div><i>DAILY TIME</i></div>'+ 
    '<div class="ck-attdaily-user-summary"><div><span>TODAY PLAYTIME</span><b>'+escapeHtml(d.title||'일일 출석 체크')+'</b><small>'+escapeHtml(d.reason||'접속시간 조건을 달성하면 단계별 보상을 받을 수 있습니다.')+'</small></div><strong>'+dailyAttendanceProgressText(minute)+'</strong></div>'+ 
    '<div class="ck-attdaily-user-grid">'+(cards||'<div class="ck-evt-empty">등록된 일일 접속시간 보상이 없습니다.</div>')+'</div>';

  body.querySelectorAll('[data-attdaily-claim]').forEach(btn=>btn.addEventListener('click',()=>{
    if(attendanceClaimBusy||btn.disabled)return;
    attendanceClaimBusy=true;btn.disabled=true;btn.textContent='지급 중…';
    fetch('https://cookie_admin/claimAttendance',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({mode:'daily',rewardId:Number(btn.dataset.attdailyClaim)})}).catch(()=>{attendanceClaimBusy=false;});
  }));
}

function monthlyAttendanceClaimButton(d,progress,nextDay,id){
  let claimText='오늘 월간 출석 완료';
  if(d.canClaim)claimText=nextDay+'일차 보상 받기';
  else if(progress>=28)claimText='28일 출석 완료';
  else if(!d.enabled)claimText='월간 출석 비활성화';
  return '<div class="ck-att-bottom"><div class="ck-att-note">'+escapeHtml(d.reason||'오늘 받을 수 있는 월간 출석 보상이 있습니다.')+'</div><button id="'+id+'" class="ck-att-claim" '+(d.canClaim?'':'disabled')+'>'+claimText+'</button></div>';
}
function bindMonthlyAttendanceClaim(d,id){
  document.getElementById(id)?.addEventListener('click',()=>{
    if(!d.canClaim||attendanceClaimBusy)return;
    attendanceClaimBusy=true;const b=document.getElementById(id);if(b){b.disabled=true;b.textContent='보상 지급 중…';}
    fetch('https://cookie_admin/claimAttendance',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({mode:'monthly'})}).catch(()=>{attendanceClaimBusy=false;});
  });
}

function renderMonthlyAttendanceHub(d){
  const body=document.getElementById('ckEventBody');if(!body)return;
  const claimed=d.claimed||{},rewards=Array.isArray(d.rewards)?d.rewards:[];
  const nextDay=Number(d.nextDay||1),progress=Math.max(0,Math.min(28,Number(d.claimedCount||0)));
  const cards=[];
  for(let day=1;day<=28;day++){
    const r=rewards.find(x=>Number(x.day)===day)||{day,type:'none',label:'보상 미설정'};
    const isClaimed=!!claimed[String(day)],isNext=!isClaimed&&day===nextDay&&progress<28,isFuture=!isClaimed&&day>nextDay,bonus=day%7===0;
    let state='';if(isClaimed)state='claimed';else if(isNext)state='today';else if(isFuture)state='locked';
    const status=isClaimed?'<span class="ck-att-state done">완료</span>':(isNext?'<span class="ck-att-state today">NEXT</span>':'<span class="ck-att-state">대기</span>');
    cards.push('<div class="ck-att-day '+state+(bonus?' bonus':'')+'"><div class="ck-att-day-top"><b>'+day+'일차</b>'+status+'</div><div class="ck-att-reward-icon">'+attendanceRewardIcon(r)+'</div><div class="ck-att-reward">'+escapeHtml(attendanceRewardText(r))+'</div>'+(bonus?'<div class="ck-att-bonus">WEEK BONUS</div>':'')+(isClaimed?'<div class="ck-att-check">✓</div>':'')+'</div>');
  }
  body.innerHTML='<div class="ck-evt-status '+(d.enabled?'on':'off')+'"><div><b>월간 출석체크</b><span>'+escapeHtml(d.cycleLabel||'-')+' · 하루 한 번, 28단계 순차 지급</span></div><i>MONTHLY</i></div>'+ 
    '<div class="ck-att-summary"><div><span>'+escapeHtml(d.cycleLabel||'-')+'</span><b>'+escapeHtml(d.title||'월간 출석 체크')+'</b><small>빠뜨린 날이 있어도 보상 순서는 건너뛰지 않습니다.</small></div><div class="ck-att-progress"><strong>'+progress+'</strong><span>/ 28</span></div></div>'+ 
    '<div class="ck-att-progressbar"><i style="width:'+Math.round(progress/28*100)+'%"></i></div><div class="ck-att-grid">'+cards.join('')+'</div>'+monthlyAttendanceClaimButton(d,progress,nextDay,'ckHubAttendClaimMonthly');
  bindMonthlyAttendanceClaim(d,'ckHubAttendClaimMonthly');
}

function renderAttendanceHub(){
  if(cookieEventHubRoot(cookieEventHubTab)!=='attendance')return;
  const body=document.getElementById('ckEventBody');if(!body)return;
  if(!attendanceData){body.innerHTML='<div class="ck-evt-loading">출석 정보를 불러오는 중입니다…</div>';return;}
  if(cookieEventHubTab==='attendance_monthly')renderMonthlyAttendanceHub(attendanceData.monthly||{});
  else renderDailyAttendanceHub(attendanceData.daily||{});
}

function renderQuestHub(period){
  const tab=period==='weekly'?'weekly':'daily';
  const expected=tab==='weekly'?'quest_weekly':'quest_daily';
  if(cookieEventHubTab!==expected)return;
  const body=document.getElementById('ckEventBody');if(!body)return;
  const d=cookieQuestData&&cookieQuestData[tab];
  if(!d){body.innerHTML='<div class="ck-evt-loading">'+(tab==='weekly'?'주간':'일일')+' 퀘스트를 불러오는 중입니다…</div>';return;}
  const quests=Array.isArray(d.quests)?d.quests:[];
  const cards=quests.map(q=>{
    const progress=Math.max(0,Number(q.progress)||0),target=Math.max(1,Number(q.target)||1);
    const pct=Math.max(0,Math.min(100,Math.floor(progress/target*100)));
    let status=q.claimed?'보상 수령 완료':(q.complete?'완료':'진행 중');
    let btnText=q.claimed?'수령 완료':(q.complete?'보상 받기':'진행 중');
    return '<section class="ck-quest-card '+(q.complete?'complete':'')+(q.claimed?' claimed':'')+'">'+
      '<div class="ck-quest-head"><div><span>'+(tab==='weekly'?'WEEKLY QUEST':'DAILY QUEST')+'</span><h3>'+escapeHtml(q.title||'퀘스트')+'</h3><p>'+escapeHtml(q.description||'')+'</p></div><em>'+status+'</em></div>'+
      '<div class="ck-quest-progress-row"><div><b>'+cookieQuestValue(progress,q.unit)+'</b><span>/ '+cookieQuestValue(target,q.unit)+'</span></div><strong>'+pct+'%</strong></div>'+
      '<div class="ck-quest-bar"><i style="width:'+pct+'%"></i></div>'+
      '<div class="ck-quest-foot"><span class="ck-evt-reward"><b>보상</b>'+escapeHtml(q.reward?.label||'-')+'</span><button data-quest-claim="'+escapeHtml(q.id||'')+'" '+(q.canClaim?'':'disabled')+'>'+btnText+'</button></div>'+
    '</section>';
  }).join('');
  body.innerHTML='<div class="ck-evt-status on"><div><b>'+(tab==='weekly'?'주간 퀘스트':'일일 퀘스트')+'</b><span>'+escapeHtml(d.label||'-')+' · '+escapeHtml(d.resetText||'')+'</span></div><i>'+(tab==='weekly'?'WEEKLY':'DAILY')+'</i></div>'+
    '<div class="ck-quest-grid">'+(cards||'<div class="ck-evt-empty">등록된 퀘스트가 없습니다.</div>')+'</div>';
  body.querySelectorAll('[data-quest-claim]').forEach(btn=>btn.addEventListener('click',()=>{
    if(cookieQuestClaimBusy||btn.disabled)return;
    cookieQuestClaimBusy=true;btn.disabled=true;btn.textContent='지급 중…';
    fetch('https://cookie_admin/claimQuest',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({questId:btn.dataset.questClaim})}).catch(()=>{cookieQuestClaimBusy=false;});
  }));
}

function renderCookieEventModal(){
  if(cookieEventHubTab!=='event')return;
  const body=document.getElementById('ckEventBody');
  if(!body)return;
  const d=cookieOpenEventData;
  if(!d){
    body.innerHTML='<div class="ck-evt-loading">이벤트 정보를 불러오는 중입니다…</div>';
    return;
  }
  const enabled=!!d.enabled;
  const cards=(Array.isArray(d.events)?d.events:[]).map(ev=>{
    const mine=ev.my||{};
    const metric=ev.metric||'rp';
    const myDetail=metric==='job' && mine.jobLabel ? ' · '+escapeHtml(mine.jobLabel) : '';
    const myValue=metric==='activity'?cookieEventSeconds(mine.seconds||0):(metric==='purity'?('순도 '+Number(mine.purity||0)+'%'+(mine.mineralLabel?' · '+escapeHtml(mine.mineralLabel):'')):cookieEventTime(mine.minute||0)+myDetail);
    return '<section class="ck-evt-card">'+
      '<div class="ck-evt-card-head"><div><span>OPEN EVENT</span><h3>'+escapeHtml(ev.title||'오픈 이벤트')+'</h3><p>'+escapeHtml(ev.description||'')+'</p></div><em>'+escapeHtml(ev.badge||'진행 중')+'</em></div>'+
      '<div class="ck-evt-rewards">'+cookieEventRewardRows(ev.rewards)+'</div>'+
      '<div class="ck-evt-my"><span>내 현재 순위</span><b>'+(mine.rank?('#'+mine.rank):'-')+'</b><small>'+myValue+'</small></div>'+
      '<div class="ck-evt-board"><div class="ck-evt-board-title"><b>현재 TOP 5</b><span>실시간 집계</span></div>'+cookieEventRankRows(ev.ranking,ev)+'</div>'+
    '</section>';
  }).join('');

  body.innerHTML=
    '<div class="ck-evt-status '+(enabled?'on':'off')+'"><div><b>'+(enabled?'오픈 이벤트 집계 중':'오픈 이벤트 집계 일시정지')+'</b><span>집계 시작: '+escapeHtml(d.startedAt||'-')+'</span></div><i>'+(enabled?'LIVE':'PAUSED')+'</i></div>'+
    '<div class="ck-evt-grid">'+cards+'</div>'+
    '<div class="ck-evt-note"><b>안내</b><span>각 시민직은 서로 독립적으로 순위를 집계합니다. 같은 유저가 여러 직업 또는 접속시간 이벤트에서 동시에 1위를 할 수도 있습니다.</span></div>'+
    (d.canManage?'<div class="ck-evt-admin"><div><b>관리자 테스트/오픈 준비</b><span>정식 오픈 직전에 집계를 초기화하면 테스트 기록을 모두 지우고 0분부터 시작합니다.</span></div><button id="ckEventToggle">'+(enabled?'집계 일시정지':'집계 시작')+'</button><button class="danger" id="ckEventReset">집계 초기화</button></div>':'');

  document.getElementById('ckEventToggle')?.addEventListener('click',async()=>{
    if(cookieOpenEventBusy)return; cookieOpenEventBusy=true;
    try{ await cookieEventRequest('toggleOpenEvents',{enabled:!enabled}); }
    finally{ cookieOpenEventBusy=false; }
  });
  document.getElementById('ckEventReset')?.addEventListener('click',async()=>{
    if(cookieOpenEventBusy)return;
    if(!confirm('오픈 이벤트의 접속시간/직업시간 집계를 전부 0으로 초기화할까요?'))return;
    cookieOpenEventBusy=true;
    try{ await cookieEventRequest('resetOpenEvents',{}); }
    finally{ cookieOpenEventBusy=false; }
  });
}

async function cookieEventRequest(endpoint,payload){
  const response=await fetch('https://cookie_admin/'+endpoint,{
    method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload||{})
  });
  const result=await response.json();
  if(result && result.data){
    cookieOpenEventData=result.data;
    renderCookieEventModal();
  }
  if(result && result.message)showToast(result.message,!!result.isError);
  if(!result || result.ok===false){
    const msg=(result&&result.error)||'이벤트 정보를 불러오지 못했습니다.';
    const b=document.getElementById('ckEventBody');
    if(b && (!result || !result.data || !Array.isArray(result.data.events) || !result.data.events.length)){
      b.innerHTML='<div class="ck-evt-empty">'+escapeHtml(msg)+'</div>';
    }
    if(result && result.error)showToast(result.error,true);
  }
  return result;
}

function closeCookieEventHub(){
  const m=document.getElementById('ckEventModal');
  if(m)m.remove();

  // standalone 여부를 먼저 보존한 뒤 상태를 즉시 초기화한다.
  // 중복 ESC/F3/X 입력에도 닫기 요청이 꼬이지 않게 한다.
  const wasStandalone=cookieEventHubStandalone===true;
  cookieEventHubStandalone=false;
  cookieOpenEventBusy=false;
  attendanceClaimBusy=false;
  cookieQuestClaimBusy=false;

  if(wasStandalone){
    fetch('https://cookie_admin/closeEventHub',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).catch(()=>{});
  }
}

function openCookieEventHub(initialTab='event',standalone=false,hideQuest=false){
  document.getElementById('ckEventModal')?.remove();
  cookieEventHubStandalone=standalone===true;
  cookieEventHubHideQuest=hideQuest===true;
  cookieOpenEventData=cookieEventFallbackData();

  const aliases={
    attendance:'attendance_daily',
    daily:'quest_daily',
    weekly:'quest_weekly'
  };
  initialTab=aliases[initialTab]||initialTab;
  cookieEventHubTab=['event','attendance_daily','attendance_monthly','quest_daily','quest_weekly'].includes(initialTab)?initialTab:'event';
  if(cookieEventHubHideQuest&&cookieEventHubRoot(cookieEventHubTab)==='quest')cookieEventHubTab='event';

  const m=document.createElement('div');
  m.id='ckEventModal';
  m.className='ck-evt-overlay';
  const escClass=cookieEventHubHideQuest?' ck-eventhub-esc':'';
  const questButton=cookieEventHubHideQuest?'':'<button data-eventhub-main="quest"><span>03</span><b>퀘스트</b><small>일일 · 주간 목표</small></button>';

  m.innerHTML='<div class="ck-evt-modal ck-eventhub-modal'+escClass+'">'+
    '<div class="ck-evt-head"><div><span>COOKIE SERVER</span><h2>이벤트</h2><p>'+(cookieEventHubHideQuest?'이벤트와 출석 현황을 확인하세요.':'이벤트, 출석, 퀘스트를 한 화면에서 확인하세요.')+'</p></div><button id="ckEventClose">×</button></div>'+
    '<div class="ck-eventhub-layout">'+
      '<aside class="ck-eventhub-side">'+
        '<button data-eventhub-main="event"><span>01</span><b>이벤트</b><small>오픈 이벤트</small></button>'+
        '<button data-eventhub-main="attendance"><span>02</span><b>출석체크</b><small>일일 · 월간</small></button>'+
        questButton+
      '</aside>'+
      '<main class="ck-eventhub-main"><div id="ckEventSubNav" class="ck-eventhub-subnav"></div><div id="ckEventBody"></div></main>'+
    '</div>'+
  '</div>';

  document.body.appendChild(m);
  document.getElementById('ckEventClose').onclick=closeCookieEventHub;
  m.addEventListener('mousedown',e=>{if(e.target===m)closeCookieEventHub();});

  m.querySelectorAll('[data-eventhub-main]').forEach(btn=>btn.addEventListener('click',()=>{
    const main=btn.dataset.eventhubMain;
    if(main==='event')setCookieEventHubTab('event');
    else if(main==='attendance')setCookieEventHubTab(cookieEventHubRoot(cookieEventHubTab)==='attendance'?cookieEventHubTab:'attendance_daily');
    else if(main==='quest'&&!cookieEventHubHideQuest)setCookieEventHubTab(cookieEventHubRoot(cookieEventHubTab)==='quest'?cookieEventHubTab:'quest_daily');
  }));

  setCookieEventHubTab(cookieEventHubTab);
}

function openCookieEventModal(){ openCookieEventHub('event', false, false); }

window.addEventListener('message',(e)=>{
  const d=e.data||{};
  if(d.action==='openEventHub'){
    openCookieEventHub(d.tab||'event',d.standalone===true,d.hideQuest===true);
    return;
  }
  if(d.action==='openEventData'){
    cookieOpenEventBusy=false;
    cookieOpenEventData=d.data||{};
    renderCookieEventModal();
    if(d.message)showToast(d.message,!!d.isError);
    return;
  }
  if(d.action==='questData'){
    cookieQuestClaimBusy=false;
    cookieQuestData=d.data||{};
    if(cookieEventHubTab==='quest_daily')renderQuestHub('daily');
    else if(cookieEventHubTab==='quest_weekly')renderQuestHub('weekly');
    if(d.message)showToast(d.message,!!d.isError);
  }
});

document.addEventListener('keydown',(e)=>{
  if(e.key!=='Escape')return;
  if(document.getElementById('ckEventModal')){
    e.stopImmediatePropagation();
    closeCookieEventHub();
  }
},true);

// COOKIE EVENT + DAILY/MONTHLY ATTENDANCE + QUEST HUB V14.2.7 CLOSE FIX


document.getElementById('openNativeMapMarkers')?.addEventListener('click',()=>fcPost('openNativeMapMarkers',{}));

// ============================================================
// COOKIE 시스템 관리 > 월간 쿠지
// V1.4.0: 경품 편집을 DOM 임시행이 아니라 draft 배열로 보존
// ============================================================
let kujiSystemData = null;
let kujiSystemDirty = false;
let kujiDraftPrizes = [];
let kujiDraftSeq = 1;

function kujiEsc(s){return String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));}
function kujiNormalizePrize(p={}){
  return {
    id:Number(p.id)||null,
    _draftKey:p._draftKey||('draft_'+(kujiDraftSeq++)),
    grade:String(p.grade||'C'),
    label:String(p.label||''),
    rewardType:String(p.rewardType||'item'),
    rewardKey:String(p.rewardKey||''),
    amount:Math.max(1,Number(p.amount)||1),
    stock:Math.max(1,Number(p.stock)||1),
    remaining:Math.max(0,Number(p.remaining??p.stock??1)||0),
    image:String(p.image||''),
    sortOrder:Number(p.sortOrder)||0
  };
}
function kujiPrizeRow(p={},idx=0){
  const q=kujiNormalizePrize(p);
  return `<div class="ck-kuji-row" data-kuji-index="${idx}" data-kuji-id="${Number(q.id||0)}">
    <input class="kj-grade" data-field="grade" placeholder="등급" value="${kujiEsc(q.grade)}">
    <input class="kj-label" data-field="label" placeholder="경품 이름" value="${kujiEsc(q.label)}">
    <select class="kj-type" data-field="rewardType">
      ${['item','money','vehicle','skin','cosmetic','furniture','collectible'].map(x=>`<option value="${x}" ${q.rewardType===x?'selected':''}>${x}</option>`).join('')}
    </select>
    <input class="kj-key" data-field="rewardKey" placeholder="아이템명 / spawncode / ID" value="${kujiEsc(q.rewardKey)}">
    <input class="kj-amount" data-field="amount" type="number" min="1" value="${Number(q.amount)}">
    <input class="kj-stock" data-field="stock" type="number" min="1" value="${Number(q.stock)}">
    <div class="ck-kuji-rem">${Number(q.remaining)} 남음</div>
    <input class="kj-image" data-field="image" placeholder="이미지 URL(선택)" value="${kujiEsc(q.image)}">
    <button class="ck-kuji-del" type="button" data-kuji-delete="${idx}">삭제</button>
  </div>`;
}
function renderKujiPrizeRows(){
  const rows=document.getElementById('kujiPrizeRows');
  if(!rows)return;
  rows.innerHTML=kujiDraftPrizes.map((p,i)=>kujiPrizeRow(p,i)).join('');
  if(!kujiDraftPrizes.length){
    rows.innerHTML='<div class="ck-kuji-empty-row">경품이 없습니다. 오른쪽의 <b>+ 경품 추가</b>를 눌러 추가하세요.</div>';
  }
}
function renderKujiSystem(){
  const body=document.getElementById('kujiSysBody'); if(!body)return;
  if(!kujiSystemData){body.innerHTML='<div class="ck-skin-empty">설정을 불러오는 중…</div>';return;}
  if(kujiSystemData.loadError){
    body.innerHTML='<div class="ck-skin-empty"><b style="display:block;margin-bottom:10px;color:#d33">쿠지 설정을 불러오지 못했습니다.</b><span>'+kujiEsc(kujiSystemData.loadError)+'</span><br><button id="kujiRetryLoad" type="button" style="margin-top:16px;padding:10px 18px;border:0;border-radius:10px;background:#ffb400;font-weight:800;cursor:pointer">다시 불러오기</button></div>';
    document.getElementById('kujiRetryLoad')?.addEventListener('click',()=>{kujiSystemData=null;kujiSystemDirty=false;renderKujiSystem();fetch('https://cookie_admin/requestKujiSystem',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).catch(()=>{});});
    return;
  }
  const d=kujiSystemData;
  body.innerHTML=`
    <div class="ck-kuji-settings">
      <label><span>운영</span><select id="kujiEnabled"><option value="1" ${d.enabled?'selected':''}>켜짐</option><option value="0" ${!d.enabled?'selected':''}>꺼짐</option></select></label>
      <label><span>쿠지 이름</span><input id="kujiTitle" value="${kujiEsc(d.title||'')}"></label>
      <label><span>시즌 월</span><input id="kujiMonth" placeholder="YYYY-MM" value="${kujiEsc(d.seasonMonth||'')}"></label>
      <label><span>티켓 아이템</span><input id="kujiTicket" value="${kujiEsc(d.ticketItem||'cookie_kuji_ticket')}"></label>
    </div>
    <div class="ck-kuji-beacon" style="grid-template-columns:1fr">
      <div><b>📍 쿠지 비콘은 '비콘 관리'에서 설치합니다.</b><small>F3 → 관리자 → 비콘 관리 → 새 비콘 만들기 → 기능 '쿠지' → 저장</small></div>
    </div>
    <div class="ck-kuji-prize-head"><div><b>경품 구성</b><small>추가한 행은 저장 전까지 절대 자동 삭제되지 않습니다. 빈 칸이 있으면 저장하지 않고 알려줍니다.</small></div><button id="kujiAddPrize" type="button">+ 경품 추가</button></div>
    <div class="ck-kuji-row ck-kuji-row-head"><span>등급</span><span>이름</span><span>타입</span><span>키/코드</span><span>수량</span><span>재고</span><span>현재</span><span>이미지</span><span></span></div>
    <div id="kujiPrizeRows"></div>
    <div class="ck-kuji-foot">전체 재고 <b>${Number(d.remaining||0)} / ${Number(d.total||0)}</b> · vehicle/skin/cosmetic/furniture는 당첨 시 <b>보관함</b>에 영구보관됩니다.<br>furniture 키: <b>chair:prop_model</b> 또는 <b>decor:prop_model</b> · cosmetic 키: <b>prop:슬롯:drawable:texture</b></div>`;

  renderKujiPrizeRows();

  document.querySelector('.ck-kuji-settings')?.addEventListener('input',()=>{kujiSystemDirty=true;});
  document.querySelector('.ck-kuji-settings')?.addEventListener('change',()=>{kujiSystemDirty=true;});

  document.getElementById('kujiAddPrize')?.addEventListener('click',e=>{
    e.preventDefault(); e.stopPropagation();
    kujiDraftPrizes.push(kujiNormalizePrize({grade:'C',rewardType:'item',amount:1,stock:1,remaining:1}));
    kujiSystemDirty=true;
    renderKujiPrizeRows();
    const rows=document.getElementById('kujiPrizeRows');
    if(rows)rows.scrollTop=rows.scrollHeight;
  });
}

// 경품 행은 다시 렌더되어도 document 위임으로 항상 작동한다.
document.addEventListener('input',e=>{
  const el=e.target.closest?.('#kujiPrizeRows [data-field]');
  if(!el)return;
  const row=el.closest('.ck-kuji-row');
  const idx=Number(row?.dataset.kujiIndex);
  if(!Number.isInteger(idx)||!kujiDraftPrizes[idx])return;
  const field=el.dataset.field;
  let value=el.value;
  if(field==='amount'||field==='stock')value=Math.max(1,Number(value)||1);
  kujiDraftPrizes[idx][field]=value;
  kujiSystemDirty=true;
});
document.addEventListener('change',e=>{
  const el=e.target.closest?.('#kujiPrizeRows [data-field]');
  if(!el)return;
  const row=el.closest('.ck-kuji-row');
  const idx=Number(row?.dataset.kujiIndex);
  if(!Number.isInteger(idx)||!kujiDraftPrizes[idx])return;
  const field=el.dataset.field;
  let value=el.value;
  if(field==='amount'||field==='stock')value=Math.max(1,Number(value)||1);
  kujiDraftPrizes[idx][field]=value;
  kujiSystemDirty=true;
});
document.addEventListener('click',e=>{
  const del=e.target.closest?.('[data-kuji-delete]');
  if(!del)return;
  e.preventDefault();e.stopPropagation();
  const idx=Number(del.dataset.kujiDelete);
  if(Number.isInteger(idx)&&kujiDraftPrizes[idx]){
    kujiDraftPrizes.splice(idx,1);
    kujiSystemDirty=true;
    renderKujiPrizeRows();
  }
});

function collectKujiSystem(){
  const savedBeacon=(kujiSystemData&&kujiSystemData.beacon)||{x:0,y:0,z:0};
  const savedColor=(kujiSystemData&&kujiSystemData.beaconColor)||{r:255,g:190,b:45,a:155};
  const rgb={r:Number(savedColor.r)||255,g:Number(savedColor.g)||190,b:Number(savedColor.b)||45,a:Number(savedColor.a)||155};
  const prizes=kujiDraftPrizes.map((p,i)=>({
    id:Number(p.id)||null,
    grade:String(p.grade||'C').trim()||'C',
    label:String(p.label||'').trim(),
    rewardType:String(p.rewardType||'item').trim(),
    rewardKey:String(p.rewardKey||'').trim(),
    amount:Math.max(1,Number(p.amount)||1),
    stock:Math.max(1,Number(p.stock)||1),
    image:String(p.image||'').trim(),
    sortOrder:(i+1)*10
  }));
  return {enabled:document.getElementById('kujiEnabled')?.value==='1',title:document.getElementById('kujiTitle')?.value||'',seasonMonth:document.getElementById('kujiMonth')?.value||'',ticketItem:document.getElementById('kujiTicket')?.value||'',beacon:{x:Number(savedBeacon.x)||0,y:Number(savedBeacon.y)||0,z:Number(savedBeacon.z)||0},beaconColor:rgb,prizes};
}
function validateKujiSystem(d){
  if(!/^\d{4}-\d{2}$/.test(String(d.seasonMonth||'')))return '시즌 월은 YYYY-MM 형식으로 입력하세요.';
  if(!String(d.ticketItem||'').trim())return '티켓 아이템명을 입력하세요.';
  if(!d.prizes.length)return '경품을 1개 이상 추가하세요.';
  for(let i=0;i<d.prizes.length;i++){
    const p=d.prizes[i];
    if(!p.label)return `${i+1}번째 경품 이름을 입력하세요.`;
    if(!p.rewardType)return `${i+1}번째 경품 타입을 선택하세요.`;
    if(!p.rewardKey)return `${i+1}번째 경품 키/코드를 입력하세요.`;
    if(Number(p.amount)<1)return `${i+1}번째 지급 수량을 확인하세요.`;
    if(Number(p.stock)<1)return `${i+1}번째 재고를 확인하세요.`;
  }
  return '';
}

document.getElementById('kujiSysSave')?.addEventListener('click',()=>{
  const d=collectKujiSystem();
  const err=validateKujiSystem(d);
  if(err){showToast(err,true);return;}
  fetch('https://cookie_admin/saveKujiSystem',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(d)}).catch(()=>showToast('쿠지 저장 요청에 실패했습니다.',true));
});
document.getElementById('kujiResetStock')?.addEventListener('click',()=>{if(confirm('현재 월의 모든 경품 재고를 최초 수량으로 되돌릴까요?'))fetch('https://cookie_admin/resetKujiStock',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).catch(()=>{});});
document.getElementById('kujiStartMonth')?.addEventListener('click',()=>{
  const d=collectKujiSystem();
  const err=validateKujiSystem(d);
  if(err){showToast(err,true);return;}
  if(confirm(`${d.seasonMonth} 쿠지를 새로 시작할까요?\n모든 경품 재고가 가득 찬 상태로 시작됩니다.`))fetch('https://cookie_admin/startKujiMonth',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(d)}).catch(()=>{});
});
window.addEventListener('message',e=>{
  const m=e.data||{};
  if(m.action==='kujiSystemData'){
    // 편집 중에는 서버의 늦은 응답이 작성 중인 행을 덮지 못한다.
    if(kujiSystemDirty)return;
    kujiSystemData=m.data||{};
    kujiDraftPrizes=(kujiSystemData.prizes||[]).map(kujiNormalizePrize);
    renderKujiSystem();
  }
  if(m.action==='kujiSystemSaved'){
    if(m.data?.success){
      kujiSystemDirty=false;
      showToast(m.data.message||'쿠지 설정을 저장했습니다.',false);
      fetch('https://cookie_admin/requestKujiSystem',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).catch(()=>{});
    }else{
      showToast(m.data?.message||'쿠지 설정 저장에 실패했습니다.',true);
    }
  }
});


window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'personalStorageData') {
    personalStorageData = d.data || { vehicle: [], cosmetic: [], chair: [], skin: [], summary: {} };
    const modal = document.getElementById('personalStorageModal');
    if (modal && !modal.classList.contains('hidden')) renderPersonalStorageModal();
  }
});


(function wirePersonalStorageStatic(){
  const modal=document.getElementById('personalStorageModal');
  if(!modal) return;
  const close=document.getElementById('personalStorageClose');
  const refresh=document.getElementById('personalStorageRefresh');
  if(close) close.onclick=()=>modal.classList.add('hidden');
  if(refresh) refresh.onclick=()=>fetch('https://cookie_admin/requestPersonalStorage',{
    method:'POST',headers:{'Content-Type':'application/json'},body:'{}'
  }).catch(()=>{});
  modal.querySelectorAll('[data-personal-tab]').forEach(b=>{
    b.onclick=()=>{
      personalStorageTab=b.dataset.personalTab||'skin';
      renderPersonalStorageModal();
    };
  });
  modal.addEventListener('click',e=>{if(e.target===modal)modal.classList.add('hidden');});
})();



// ============================================================
// COOKIE TITLE USER UI V4
// ============================================================
let cookieTitleData = null;

function closeCookieTitleModal(){
  document.getElementById('ckTitleUserModal')?.remove();
}
function titleCardHtml(t, kind, equippedId){
  const on = Number(equippedId||0) === Number(t.id||0);
  return `<button class="ck-title-card ${on?'on':''}" data-title-kind="${escapeHtml(kind)}" data-title-id="${Number(t.id)||0}">
    <span class="ck-title-preview" style="color:${escapeHtml(t.color||'#FFE08A')}">${escapeHtml(t.text||t.name||'칭호')}</span>
    <b>${escapeHtml(t.name||'칭호')}</b>
    <small>${on?'현재 장착 중':'클릭하여 장착'}</small>
  </button>`;
}
function renderCookieTitleModal(){
  const body=document.getElementById('ckTitleUserBody'); if(!body)return;
  const d=cookieTitleData||{};
  const eq=d.equipped||{};
  const chat=Array.isArray(d.chat)?d.chat:[];
  const head=Array.isArray(d.head)?d.head:[];
  body.innerHTML=`
    <section class="ck-title-section">
      <div class="ck-title-section-head"><div><b>채팅 칭호</b><small>채팅 닉네임 앞에 표시됩니다.</small></div><button data-title-clear="chat">해제</button></div>
      <div class="ck-title-grid">${chat.length?chat.map(t=>titleCardHtml(t,'chat',eq.chat)).join(''):'<div class="ck-skin-empty">보유한 채팅 칭호가 없습니다.</div>'}</div>
    </section>
    <section class="ck-title-section">
      <div class="ck-title-section-head"><div><b>머리 위 칭호</b><small>캐릭터 머리 위 이름표에 표시됩니다.</small></div><button data-title-clear="head">해제</button></div>
      <div class="ck-title-grid">${head.length?head.map(t=>titleCardHtml(t,'head',eq.head)).join(''):'<div class="ck-skin-empty">보유한 머리 위 칭호가 없습니다.</div>'}</div>
    </section>
    <section class="ck-title-settings">
      <label>표시 순서<select id="ckTitleHeadOrder"><option value="title_first" ${d.display?.headOrder!=='lover_first'?'selected':''}>칭호 먼저</option><option value="lover_first" ${d.display?.headOrder==='lover_first'?'selected':''}>연인 표시 먼저</option></select></label>
      <label class="ck-title-check"><input id="ckTitleLoverVisible" type="checkbox" ${d.display?.loverVisible!==false?'checked':''}> 연인 표시 사용</label>
      <button id="ckTitleSettingSave" type="button">표시 설정 저장</button>
    </section>`;
  body.querySelectorAll('[data-title-id]').forEach(btn=>btn.onclick=()=>{
    fetch('https://cookie_admin/equipTitle',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({kind:btn.dataset.titleKind,id:Number(btn.dataset.titleId)})}).catch(()=>{});
  });
  body.querySelectorAll('[data-title-clear]').forEach(btn=>btn.onclick=()=>{
    fetch('https://cookie_admin/equipTitle',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({kind:btn.dataset.titleClear,id:null})}).catch(()=>{});
  });
  document.getElementById('ckTitleSettingSave')?.addEventListener('click',()=>{
    fetch('https://cookie_admin/saveTitleDisplaySettings',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({
      headOrder:document.getElementById('ckTitleHeadOrder')?.value||'title_first',
      loverVisible:!!document.getElementById('ckTitleLoverVisible')?.checked
    })}).catch(()=>{});
  });
}
function openCookieTitleModal(){
  closeCookieTitleModal();
  const m=document.createElement('div');
  m.id='ckTitleUserModal';m.className='ck-title-overlay';
  m.innerHTML='<div class="ck-title-modal"><div class="ck-title-head"><div><span>COOKIE IDENTITY</span><b>칭호</b><small>보유한 칭호를 장착하거나 해제합니다.</small></div><button id="ckTitleUserClose">×</button></div><div id="ckTitleUserBody"><div class="ck-skin-empty">칭호를 불러오는 중입니다…</div></div></div>';
  document.body.appendChild(m);
  document.getElementById('ckTitleUserClose').onclick=closeCookieTitleModal;
  m.addEventListener('mousedown',e=>{if(e.target===m)closeCookieTitleModal();});
  fetch('https://cookie_admin/requestTitles',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).catch(()=>{});
}
window.addEventListener('message',(e)=>{
  const d=e.data||{};
  if(d.action==='titleUserData'){
    cookieTitleData=d.data||{};
    renderCookieTitleModal();
    if(d.message)showToast(d.message,!!d.isError);
  }
});

// COOKIE HAIR UI + AFK COORD ADMIN V13.9.1

// COOKIE AFKZONE DRAWABLE COORD ADMIN V13.9.2

// COOKIE AFK ENTER/LEAVE BEACON MOVE V13.9.3

// COOKIE COORD WALK UI HIDE FIX V13.9.4

// COOKIE NEWBIE SINGLE BEACON V13.9.6

// COOKIE AFK WALK ZONE UNLIMITED V13.9.10


// ============================================================
// COOKIE ITEM CONFISCATION V14.2.8
// ============================================================
let ckConfiscateTarget = null;
let ckConfiscateData = null;

function closeConfiscateModal(){
  document.getElementById('ckConfiscateModal')?.remove();
  ckConfiscateTarget = null;
  ckConfiscateData = null;
}

function requestConfiscateInventory(){
  if(!ckConfiscateTarget) return;
  fetch('https://cookie_admin/requestTargetInventory',{
    method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({targetServerId:ckConfiscateTarget.serverId})
  }).catch(()=>{});
}

function renderConfiscateModal(){
  const body=document.getElementById('ckConfiscateBody');
  if(!body) return;
  const d=ckConfiscateData||{};
  const rows=Array.isArray(d.items)?d.items:[];
  const count=rows.reduce((n,r)=>n+(Number(r.count)||0),0);
  const targetName=String(d.targetName || ckConfiscateTarget?.name || '대상');
  document.getElementById('ckConfiscateTargetName')?.replaceChildren(document.createTextNode(targetName));
  const stat=document.getElementById('ckConfiscateStat');
  if(stat) stat.textContent=`${rows.length}칸 · 총 ${count.toLocaleString('ko-KR')}개`;

  if(!d.ok && d.message){
    body.innerHTML='<div class="ck-conf-empty danger">'+escapeHtml(d.message)+'</div>';
    return;
  }
  if(!rows.length){
    body.innerHTML='<div class="ck-conf-empty">보유 중인 아이템이 없습니다.</div>';
    return;
  }
  body.innerHTML=rows.map(r=>{
    const slot=Number(r.slot)||0, max=Math.max(1,Number(r.count)||1);
    const img='nui://ox_inventory/web/images/'+encodeURIComponent(String(r.name||'').toLowerCase())+'.png';
    return `<div class="ck-conf-row" data-slot="${slot}">
      <div class="ck-conf-icon"><img src="${img}" onerror="this.style.display='none'" alt=""></div>
      <div class="ck-conf-info"><b>${escapeHtml(r.label||r.name||'아이템')}</b><small>${escapeHtml(r.name||'')} · 슬롯 ${slot}</small></div>
      <div class="ck-conf-owned">보유 <b>${max.toLocaleString('ko-KR')}</b></div>
      <input class="ck-conf-qty" type="number" min="1" max="${max}" value="${max}">
      <button class="ck-conf-take" type="button">압수</button>
    </div>`;
  }).join('');

  body.querySelectorAll('.ck-conf-take').forEach(btn=>btn.onclick=()=>{
    const row=btn.closest('.ck-conf-row'); if(!row||!ckConfiscateTarget)return;
    const input=row.querySelector('.ck-conf-qty');
    const count=Math.max(1,Math.floor(Number(input?.value)||1));
    btn.disabled=true; btn.textContent='처리 중';
    fetch('https://cookie_admin/confiscateItem',{
      method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({targetServerId:ckConfiscateTarget.serverId,slot:Number(row.dataset.slot),count})
    }).catch(()=>{btn.disabled=false;btn.textContent='압수';});
  });
}

function openConfiscateModal(){
  if(!activeTarget) return;
  closeConfiscateModal();
  ckConfiscateTarget={
    serverId:Number(activeTarget.serverId),
    name:activeTarget.nickname||activeTarget.name||activeTarget.realname||('#'+activeTarget.serverId)
  };
  closeTargetModal();
  const m=document.createElement('div');
  m.id='ckConfiscateModal'; m.className='ck-conf-overlay';
  m.innerHTML=`<div class="ck-conf-modal">
    <div class="ck-conf-head"><div><span>ADMIN INVENTORY</span><b>아이템 압수</b><small><strong id="ckConfiscateTargetName">${escapeHtml(ckConfiscateTarget.name)}</strong>님의 현재 인벤토리</small></div><button id="ckConfiscateClose" type="button">×</button></div>
    <div class="ck-conf-toolbar"><span id="ckConfiscateStat">불러오는 중...</span><div><button id="ckConfiscateRefresh" class="ck-conf-ghost" type="button">새로고침</button><button id="ckConfiscateAll" class="ck-conf-all" type="button">전체 압수</button></div></div>
    <div id="ckConfiscateBody" class="ck-conf-body"><div class="ck-conf-empty">인벤토리를 불러오는 중입니다...</div></div>
    <div class="ck-conf-foot">압수 즉시 대상 인벤토리에서 제거되며 관리자 로그가 남습니다.</div>
  </div>`;
  document.body.appendChild(m);
  document.getElementById('ckConfiscateClose').onclick=closeConfiscateModal;
  document.getElementById('ckConfiscateRefresh').onclick=requestConfiscateInventory;
  document.getElementById('ckConfiscateAll').onclick=()=>{
    if(!ckConfiscateTarget)return;
    if(!confirm(`${ckConfiscateTarget.name}님의 모든 아이템을 압수할까요?\n이 작업은 되돌릴 수 없습니다.`))return;
    fetch('https://cookie_admin/confiscateAllItems',{
      method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({targetServerId:ckConfiscateTarget.serverId})
    }).catch(()=>{});
  };
  m.addEventListener('mousedown',e=>{if(e.target===m)closeConfiscateModal();});
  requestConfiscateInventory();
}

window.addEventListener('message',(e)=>{
  const d=e.data||{};
  if(d.action==='targetInventory'){
    ckConfiscateData=d.data||{};
    if(document.getElementById('ckConfiscateModal')) renderConfiscateModal();
    if(d.data?.message) showToast(d.data.message,!!d.data.isError);
  }
});

window.addEventListener('keydown',(e)=>{
  if(e.key==='Escape' && document.getElementById('ckConfiscateModal')){
    e.preventDefault(); e.stopImmediatePropagation(); closeConfiscateModal();
  }
},true);


/* =========================================================
   COOKIE ADMIN F3 CUSTOM HORIZONTAL SLIDER V14.3.7
   - FiveM CEF native scrollbar visibility에 의존하지 않음
   - F3 관리자 탭에 실제 커스텀 가로 슬라이더 생성
   ========================================================= */
(function(){
  if(window.__COOKIE_ADMIN_HSLIDER_V1437__) return;
  window.__COOKIE_ADMIN_HSLIDER_V1437__ = true;

  const TARGETS = ['rightTabs']; // 관리자 오른쪽 탭만: 시민/직업/팝업 탭 제외

  // V14.3.8: 관리자 메인 탭에서만 슬라이더를 표시한다.
  // 팩션 관리 같은 별도 창을 열면 원래 관리자 탭이 뒤에 남아 있으므로
  // activeRoot === 'admin' 검사만으로는 팝업 위에 슬라이더가 새어 나온다.
  const DETAIL_WINDOW_SELECTOR = [
    '#facConsole', '#npcConsole', '#mfConsole', '#armory',
    '#npcEditBar', '#boxEdit', '#zonePreviewBar',
    '.ck-system-window-overlay', '.ck-door-modal',
    '.ck-evt-overlay', '.ck-jlv-overlay', '.ck-key-overlay',
    '.ck-fishdex-overlay', '.ck-conf-overlay', '.ck-att-overlay',
    '.ck-couple-overlay', '.ck-zone-modal', '.ck-fa-dismiss-overlay',
    '[id$="Modal"]', '#rolePick'
  ].join(',');

  function isDetailWindowOpen() {
    const dialogs = document.querySelectorAll(DETAIL_WINDOW_SELECTOR);
    for (const dialog of dialogs) {
      // 숨겨진 DOM 노드는 제외하고 현재 화면에 표시된 상세 창만 판단한다.
      if (dialog.classList.contains('hidden')) continue;
      if (dialog.getClientRects().length > 0 && getComputedStyle(dialog).visibility !== 'hidden') {
        return true;
      }
    }
    return false;
  }


  function setupSlider(id){
    const tabs = document.getElementById(id);
    if(!tabs || tabs.dataset.ckHsliderReady === '1') return;
    tabs.dataset.ckHsliderReady = '1';

    const wrap = document.createElement('div');
    wrap.className = 'ck-admin-hslider hidden';
    wrap.dataset.forTabs = id;
    wrap.innerHTML = '<div class="ck-admin-hslider-track"><div class="ck-admin-hslider-thumb"></div></div>';
    tabs.insertAdjacentElement('afterend', wrap);

    const track = wrap.querySelector('.ck-admin-hslider-track');
    const thumb = wrap.querySelector('.ck-admin-hslider-thumb');
    let drag = null;

    function update(){
      const max = Math.max(0, tabs.scrollWidth - tabs.clientWidth);
      const trackW = Math.max(1, track.clientWidth);
      const adminPane = document.getElementById('paneAdmin');
      const rootOverlay = document.getElementById('overlay');
      const panelWrap = document.getElementById('panelWrap');
      const adminVisible = !!adminPane && !!rootOverlay &&
        !rootOverlay.classList.contains('hidden') &&
        !rootOverlay.classList.contains('preview-mode') &&
        !rootOverlay.classList.contains('npc-edit') &&
        !rootOverlay.classList.contains('zone-only') &&
        (!panelWrap || !panelWrap.classList.contains('hidden')) &&
        !adminPane.classList.contains('hidden') && activeRoot === 'admin';
      const visible = adminVisible && !isDetailWindowOpen() &&
        max > 3 && tabs.clientWidth > 0 && tabs.scrollWidth > tabs.clientWidth + 3;
      wrap.classList.toggle('hidden', !visible);
      if(!visible) return;

      const thumbW = Math.max(64, Math.min(trackW, trackW * (tabs.clientWidth / tabs.scrollWidth)));
      const travel = Math.max(0, trackW - thumbW);
      const left = max > 0 ? (tabs.scrollLeft / max) * travel : 0;
      thumb.style.width = thumbW + 'px';
      thumb.style.transform = 'translateX(' + Math.max(0, Math.min(travel, left)) + 'px)';
    }

    function setFromPointer(clientX){
      const rect = track.getBoundingClientRect();
      const thumbW = thumb.getBoundingClientRect().width || 64;
      const travel = Math.max(1, rect.width - thumbW);
      const x = Math.max(0, Math.min(travel, clientX - rect.left - (drag ? drag.offset : thumbW / 2)));
      const max = Math.max(0, tabs.scrollWidth - tabs.clientWidth);
      tabs.scrollLeft = (x / travel) * max;
      update();
    }

    thumb.addEventListener('pointerdown', function(e){
      e.preventDefault();
      e.stopPropagation();
      const r = thumb.getBoundingClientRect();
      drag = { id: e.pointerId, offset: e.clientX - r.left };
      try { thumb.setPointerCapture(e.pointerId); } catch (_) {}
      thumb.classList.add('dragging');
    });

    thumb.addEventListener('pointermove', function(e){
      if(!drag || e.pointerId !== drag.id) return;
      e.preventDefault();
      setFromPointer(e.clientX);
    });

    function endDrag(e){
      if(!drag || (e.pointerId != null && e.pointerId !== drag.id)) return;
      drag = null;
      thumb.classList.remove('dragging');
    }
    thumb.addEventListener('pointerup', endDrag);
    thumb.addEventListener('pointercancel', endDrag);

    track.addEventListener('pointerdown', function(e){
      if(e.target === thumb) return;
      e.preventDefault();
      setFromPointer(e.clientX);
    });

    // 상세 화면의 열기/닫기(.hidden) 변경을 즉시 감지한다.
    // 슬라이더 자신의 hidden 변경은 무시해 Observer 재호출 루프를 막는다.
    try {
      const observer = new MutationObserver(function(mutations){
        for (const m of mutations) {
          const el = m.target;
          if (el === wrap || wrap.contains(el)) continue;
          if (el.id === 'overlay' || el.id === 'panelWrap' ||
              el.id === 'paneAdmin' || el.matches(DETAIL_WINDOW_SELECTOR)) {
            requestAnimationFrame(update);
            break;
          }
        }
      });
      observer.observe(document.body, {
        subtree: true, attributes: true, attributeFilter: ['class', 'style']
      });
    } catch (_) {}

    tabs.addEventListener('scroll', update, { passive: true });
    tabs.addEventListener('wheel', function(e){
      if(Math.abs(e.deltaY) > Math.abs(e.deltaX) && tabs.scrollWidth > tabs.clientWidth){
        tabs.scrollLeft += e.deltaY;
        e.preventDefault();
      }
    }, { passive: false });

    try { new ResizeObserver(update).observe(tabs); } catch (_) {}
    try {
      new MutationObserver(function(){ requestAnimationFrame(update); }).observe(
        tabs,
        { childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'style'] }
      );
    } catch (_) {}

    setTimeout(update, 0);
    setTimeout(update, 150);
    setTimeout(update, 500);
  }

  function init(){
    TARGETS.forEach(setupSlider);
    TARGETS.forEach(function(id){
      const tabs = document.getElementById(id);
      if(tabs) tabs.dispatchEvent(new Event('scroll'));
    });
  }

  if(document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', init, { once: true });
  } else {
    init();
  }

  window.addEventListener('resize', function(){ setTimeout(init, 0); });
  window.addEventListener('message', function(){ setTimeout(init, 30); setTimeout(init, 250); });
  setInterval(init, 1200);
})();
