

const root = document.getElementById('root');
const stage = document.getElementById('stage');

const screens = {
    welcome: document.getElementById('screen-welcome'),
    consent: document.getElementById('screen-consent'),
    nick: document.getElementById('screen-nick'),
    verify: document.getElementById('screen-verify'),
    verified: document.getElementById('screen-verified'),
    create: document.getElementById('screen-create'),
    entry: document.getElementById('screen-entry')
};

const welcomeFade = document.getElementById('welcome-fade');
const logoImg = document.getElementById('welcome-logo');
const logoText = document.getElementById('welcome-logo-text');
const startBtn = document.getElementById('btn-start');

const agree = document.getElementById('agree');
const agreeBtn = document.getElementById('btn-agree');

const nickInput = document.getElementById('nick-input');
const nickHint = document.getElementById('nick-hint');
const checkNickBtn = document.getElementById('btn-check-nick');

const idGenderBtns = document.querySelectorAll('.id-gbtn');
const ageInput = document.getElementById('age-input');
const ageHint = document.getElementById('age-hint');
const juminView = document.getElementById('jumin-view');
const juminBtn = document.getElementById('btn-jumin');
const phoneView = document.getElementById('phone-view');
const phoneBtn = document.getElementById('btn-phone');
const idHint = document.getElementById('id-hint');
const confirmBtn = document.getElementById('btn-confirm');

const lastName = document.getElementById('in-lastname');
const firstName = document.getElementById('in-firstname');
const birth = document.getElementById('in-birth');
const genderBtns = document.querySelectorAll('.gender-btn');
const createBtn = document.getElementById('btn-create');
const createHint = document.getElementById('create-hint');

const entryTitle = document.getElementById('entry-title');
const enterBtn = document.getElementById('btn-enter');
const entryLogoImg = document.getElementById('entry-logo');
const entryLogoText = document.getElementById('entry-logo-text');

const verifyInvite = document.getElementById('verify-invite');
const verifyChannelLine = document.getElementById('verify-channel-line');
const verifyStatus = document.getElementById('verify-status');
const verifyInput = document.getElementById('verify-input');
const verifySubmit = document.getElementById('btn-verify-submit');
const copyInviteBtn = document.getElementById('btn-copy-invite');
const openDiscordBtn = document.getElementById('btn-open-discord');
const verifiedGobun = document.getElementById('verified-gobun');
const verifiedNext = document.getElementById('btn-verified-next');

const editModal = document.getElementById('edit-modal');
const editNoBtn = document.getElementById('btn-edit-no');
const editYesBtn = document.getElementById('btn-edit-yes');

let nickAvailable = false;

let juminIssued = '';
let phoneIssued = '';
let idGender = '';
let debounceTimer = null;
let selectedGender = '';

async function post(name, body) {
    const res = await fetch('https://cookie_select/' + name, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body || {})
    });
    return res.json();
}

function showOnly(name) {
    const keys = Object.keys(screens);
    for (let i = 0; i < keys.length; i++) {
        screens[keys[i]].classList.add('hidden');
    }
    screens[name].classList.remove('hidden');
    const isEntry = name === 'entry';
    root.classList.toggle('root--world', isEntry);
    stage.classList.toggle('hidden', isEntry);
}

function playWelcomeFade() {
    welcomeFade.classList.remove('fade-in');
    void welcomeFade.offsetWidth;
    requestAnimationFrame(function () {
        welcomeFade.classList.add('fade-in');
    });
}

function setNickHint(text, tone) {
    nickHint.textContent = text;
    nickHint.className = 'hint hint-' + tone;
}

function resetTransient(name, d) {
    if (name === 'consent') {
        agree.checked = false;
        agreeBtn.disabled = true;
    } else if (name === 'nick') {
        nickInput.value = '';
        nickAvailable = false;
        confirmBtn.disabled = true;
        setNickHint('2~10자, 한글/영문/숫자', 'neutral');

        idGender = '';
        pendingGender = '';
        if (genderModal) genderModal.classList.add('hidden');
        for (let g = 0; g < idGenderBtns.length; g++) {
            idGenderBtns[g].classList.remove('id-gon');
            idGenderBtns[g].disabled = false;
        }
        ageInput.readOnly = false;
        ageInput.value = '';
        ageHint.textContent = '18~80세';
        ageHint.className = 'hint hint-neutral';
        juminIssued = '';
        phoneIssued = '';
        juminView.textContent = '미발급';
        juminView.classList.remove('id-done');
        phoneView.textContent = '미발급';
        phoneView.classList.remove('id-done');
        juminBtn.disabled = true;
        juminBtn.textContent = '발급받기';
        phoneBtn.disabled = false;
        phoneBtn.textContent = '발급받기';
        idHint.textContent = '발급된 번호는 변경할 수 없습니다';
        idHint.className = 'hint hint-neutral';

        if (debounceTimer) { clearTimeout(debounceTimer); debounceTimer = null; }
        setTimeout(function () { nickInput.focus(); }, 50);
    } else if (name === 'verify') {
        verifyInput.value = '';
        verifySubmit.disabled = true;
    } else if (name === 'verified') {
        verifiedNext.disabled = false;
    } else if (name === 'create') {
        lastName.value = '';
        firstName.value = '';
        birth.value = '';

        const locked = (d && d.gender) || '';
        selectedGender = locked;
        for (let j = 0; j < genderBtns.length; j++) {
            const btn = genderBtns[j];
            const mine = btn.dataset.gender === locked;
            btn.classList.toggle('gender-on', !!locked && mine);
            btn.disabled = !!locked;
        }

        createBtn.disabled = false;
        createHint.textContent = '';
    } else if (name === 'entry') {
        enterBtn.disabled = false;
    }
}

startBtn.addEventListener('click', function () {
    post('welcomeDone', {});
});

agree.addEventListener('change', function () {
    agreeBtn.disabled = !agree.checked;
});

agreeBtn.addEventListener('click', function () {
    if (agreeBtn.disabled) return;
    post('consentDone', {});
});

function updateConfirm() {
    confirmBtn.disabled = !nickAvailable;
}

async function runCheck(val) {
    const data = await post('checkNick', { nickname: val });
    if (nickInput.value !== val) return;
    if (data.pending) {
        setTimeout(function () { if (nickInput.value === val) runCheck(val); }, 300);
        return;
    }
    if (data.ok) {
        setNickHint(data.reason || '사용 가능한 별명입니다', 'ok');
        nickAvailable = true;
    } else {
        setNickHint(data.reason || '사용할 수 없는 별명입니다', 'bad');
        nickAvailable = false;
    }
    updateConfirm();
}

nickInput.addEventListener('input', function () {
    nickAvailable = false;
    updateConfirm();
    setNickHint('별명을 입력한 뒤 중복 확인을 눌러주세요', 'neutral');
});

checkNickBtn.addEventListener('click', function () {
    const val = nickInput.value.trim();
    if (!val) {
        setNickHint('별명을 입력해주세요', 'bad');
        return;
    }
    nickInput.value = val;
    nickAvailable = false;
    updateConfirm();
    setNickHint('중복 확인 중...', 'neutral');
    runCheck(val);
});

function ageValid() {
    const n = parseInt(ageInput.value, 10);
    return !isNaN(n) && n >= 18 && n <= 80;
}

function refreshJuminBtn() {
    if (juminIssued) return;
    juminBtn.disabled = !(idGender && ageValid());
}

function setGender(g) {
    idGender = g;
    for (let j = 0; j < idGenderBtns.length; j++) {
        idGenderBtns[j].classList.toggle('id-gon', idGenderBtns[j].dataset.gender === g);
    }
    refreshJuminBtn();
}

const genderModal = document.getElementById('gender-modal');
const gmFrom = document.getElementById('gm-from');
const gmTo = document.getElementById('gm-to');
const gmYes = document.getElementById('gm-yes');
const gmNo = document.getElementById('gm-no');
let pendingGender = '';

gmNo.addEventListener('click', function () {
    genderModal.classList.add('hidden');
    pendingGender = '';
});

gmYes.addEventListener('click', function () {
    genderModal.classList.add('hidden');
    if (pendingGender) setGender(pendingGender);
    pendingGender = '';
});

for (let g = 0; g < idGenderBtns.length; g++) {
    idGenderBtns[g].addEventListener('click', async function () {
        if (juminIssued) return;
        const want = this.dataset.gender;
        if (want === idGender) return;

        const c = await post('genderConflict', { gender: want });
        if (c && c.conflict) {
            pendingGender = want;
            gmFrom.textContent = (c.current === '여') ? '여성' : '남성';
            gmTo.textContent = (want === '여') ? '여성' : '남성';
            genderModal.classList.remove('hidden');
            return;
        }

        setGender(want);
    });
}

ageInput.addEventListener('input', function () {
    if (juminIssued) {
        ageInput.value = String(ageInput.dataset.locked || '');
        return;
    }
    ageInput.value = ageInput.value.replace(/[^0-9]/g, '');
    const valid = ageValid();

    ageHint.textContent = ageInput.value === '' ? '18~80세'
        : (valid ? '입력 완료' : '18~80세만 가능합니다');
    ageHint.className = 'hint hint-' + (ageInput.value === '' ? 'neutral' : (valid ? 'ok' : 'bad'));

    refreshJuminBtn();
});

juminBtn.addEventListener('click', async function () {
    if (juminBtn.disabled || juminIssued) return;
    juminBtn.disabled = true;
    juminBtn.textContent = '발급 중';

    const data = await post('issueJumin', {
        age: parseInt(ageInput.value, 10),
        gender: idGender
    });
    if (data && data.ok) {
        juminIssued = data.jumin;
        juminView.textContent = data.jumin;
        juminView.classList.add('id-done');
        juminBtn.textContent = '발급 완료';
        ageInput.dataset.locked = String(data.age);
        ageInput.readOnly = true;
        ageHint.textContent = '확정되었습니다';
        ageHint.className = 'hint hint-ok';

        for (let j = 0; j < idGenderBtns.length; j++) idGenderBtns[j].disabled = true;
    } else {
        juminBtn.disabled = false;
        juminBtn.textContent = '발급받기';
        idHint.textContent = (data && data.reason) || '발급에 실패했습니다';
        idHint.className = 'hint hint-bad';
    }
    updateConfirm();
});

phoneBtn.addEventListener('click', async function () {
    if (phoneBtn.disabled || phoneIssued) return;
    phoneBtn.disabled = true;
    phoneBtn.textContent = '발급 중';

    const data = await post('issuePhone', {});
    if (data && data.ok) {
        phoneIssued = data.phone;
        phoneView.textContent = data.phone;
        phoneView.classList.add('id-done');
        phoneBtn.textContent = '발급 완료';
    } else {
        phoneBtn.disabled = false;
        phoneBtn.textContent = '발급받기';
        idHint.textContent = (data && data.reason) || '발급에 실패했습니다';
        idHint.className = 'hint hint-bad';
    }
    updateConfirm();
});

confirmBtn.addEventListener('click', async function () {
    if (confirmBtn.disabled) return;
    confirmBtn.disabled = true;
    const data = await post('submitNick', { nickname: nickInput.value });
    if (!data.ok) {
        setNickHint(data.reason || '확정에 실패했습니다', 'bad');
        nickAvailable = false;
        updateConfirm();
    }
});

let verifyInviteText = 'discord.gg/DTDMfCvFbn';
let verifyUrl = 'https://discord.gg/DTDMfCvFbn';

function setVerifyStatus(text, tone) {
    verifyStatus.textContent = text;
    verifyStatus.className = 'hint hint-' + tone;
}

function renderVerify(info) {
    verifyInput.value = '';
    verifySubmit.disabled = true;

    if (info && info.ok) {
        if (info.invite) {
            verifyInviteText = String(info.invite);
            verifyInvite.textContent = verifyInviteText;
        }
        if (info.url) verifyUrl = String(info.url);
        if (info.channel) verifyChannelLine.textContent = '‘' + info.channel + '’ 채널';
        if (info.length) verifyInput.maxLength = Number(info.length);
        setVerifyStatus('디스코드에서 받은 ' + (info.length || 6) + '자리 숫자를 입력하세요', 'neutral');
    } else {
        setVerifyStatus('서버에서 안내 정보를 받지 못했습니다. 코드 입력은 계속 가능합니다', 'bad');
    }

    setTimeout(function () { verifyInput.focus(); }, 60);
}

function openDiscord() {
    let opened = false;
    try {
        if (typeof window.invokeNative === 'function') {
            window.invokeNative('openUrl', verifyUrl);
            opened = true;
        }
    } catch (err) {
        opened = false;
    }

    if (opened) {
        setVerifyStatus('디스코드를 열었습니다. 인증 채널에서 [뉴비 인증] 버튼을 눌러주세요', 'ok');
    } else {
        copyText(verifyUrl);
        setVerifyStatus('브라우저를 열지 못해 주소를 복사했습니다 ' + verifyInviteText, 'bad');
    }
}

verifyInput.addEventListener('input', function () {
    const only = verifyInput.value.replace(/[^0-9]/g, '');
    if (only !== verifyInput.value) verifyInput.value = only;
    verifySubmit.disabled = only.length < (verifyInput.maxLength || 6);
});

async function submitCode() {
    const code = verifyInput.value.trim();
    if (!code || verifySubmit.disabled) return;

    verifySubmit.disabled = true;
    setVerifyStatus('인증하는 중...', 'neutral');

    const r = await post('verifyRedeem', { code: code });

    if (r && r.ok) {

        verifiedGobun.textContent = r.gobun !== undefined && r.gobun !== null ? String(r.gobun) : '-';
        resetTransient('verified');
        showOnly('verified');
        return;
    }

    setVerifyStatus((r && r.reason) || '인증에 실패했습니다', 'bad');
    verifyInput.value = '';
    verifySubmit.disabled = true;
    verifyInput.focus();
}

verifySubmit.addEventListener('click', submitCode);

verifyInput.addEventListener('keydown', function (e) {
    if (e.key === 'Enter') submitCode();
});

verifiedNext.addEventListener('click', function () {
    verifiedNext.disabled = true;
    post('verifyDone', {});
});

function copyText(text) {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    let ok = false;
    try { ok = document.execCommand('copy'); } catch (err) { ok = false; }
    document.body.removeChild(ta);
    if (!ok && navigator.clipboard) {
        navigator.clipboard.writeText(text).catch(function () { });
        ok = true;
    }
    return ok;
}

function flashBtn(btn, label) {
    const orig = btn.dataset.orig || btn.textContent;
    btn.dataset.orig = orig;
    btn.textContent = label;
    setTimeout(function () { btn.textContent = btn.dataset.orig; }, 1200);
}

openDiscordBtn.addEventListener('click', openDiscord);

copyInviteBtn.addEventListener('click', function () {
    const v = verifyUrl || verifyInviteText;
    flashBtn(copyInviteBtn, copyText(v) ? '복사됨' : '복사 실패');
});

for (let i = 0; i < genderBtns.length; i++) {
    genderBtns[i].addEventListener('click', function () {
        selectedGender = genderBtns[i].dataset.gender;
        for (let j = 0; j < genderBtns.length; j++) {
            genderBtns[j].classList.remove('gender-on');
        }
        genderBtns[i].classList.add('gender-on');
    });
}

createBtn.addEventListener('click', async function () {
    createHint.textContent = '';
    const payload = {
        lastname: lastName.value.trim(),
        firstname: firstName.value.trim(),
        birthdate: birth.value.trim(),
        gender: selectedGender
    };
    if (!payload.lastname || !payload.firstname || !payload.birthdate || !payload.gender) {
        createHint.textContent = '모든 항목을 입력해주세요';
        return;
    }
    createBtn.disabled = true;
    const data = await post('createChar', payload);
    if (!data.ok) {
        createHint.textContent = data.reason || '생성에 실패했습니다';
        createBtn.disabled = false;
    }
});

enterBtn.addEventListener('click', function () {
    enterBtn.disabled = true;
    post('enterGame', {});
});

editNoBtn.addEventListener('click', function () {
    editModal.classList.add('hidden');
    post('editDecline', {});
});
editYesBtn.addEventListener('click', function () {
    editModal.classList.add('hidden');
    post('editAccept', {});
});

logoImg.addEventListener('error', function () {
    logoImg.classList.add('hidden');
    logoText.classList.remove('hidden');
});
entryLogoImg.addEventListener('error', function () {
    entryLogoImg.classList.add('hidden');
    entryLogoText.classList.remove('hidden');
});

document.addEventListener('keydown', function (e) {
    if (e.key === 'F2') {
        e.preventDefault();
        if (!screens.verify.classList.contains('hidden')) openDiscord();
        return;
    }
    if (e.key === 'Escape') { e.preventDefault(); return; }
    if (e.key === 'Backspace') {
        const t = e.target;
        const editable = t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA');
        if (!editable) e.preventDefault();
    }
});

window.addEventListener('message', function (e) {
    const d = e.data || {};
    if (d.action === 'show') {

        if (d.screen === 'editPrompt') {
            editModal.classList.remove('hidden');
            setTimeout(function () { editNoBtn.focus(); }, 50);
            return;
        }
        resetTransient(d.screen, d);
        root.classList.remove('hidden');
        showOnly(d.screen);
        if (d.screen === 'welcome') playWelcomeFade();
        if (d.screen === 'verify') renderVerify(d.info);
        if (d.screen === 'entry') {
            entryTitle.textContent = (d.nick || '플레이어') + '님, 어서오세요';
        }
    } else if (d.action === 'verifyReject') {

        resetTransient('verify');
        showOnly('verify');
        setVerifyStatus('인증이 확인되지 않았습니다. 다시 시도해주세요', 'bad');
    } else if (d.action === 'hide') {
        editModal.classList.add('hidden');
        root.classList.add('hidden');
    }
});
