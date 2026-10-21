

'use strict';

var DEBUG = false;
function dbg() { if (DEBUG) { try {  } catch (e) {} } }

var RES = 'chat';

var chatEl, messagesEl, inputLineEl, modeEl, inputEl, sugEl, newBadgeEl, tabEls;

var inputActive = false;
var hideState = 0;
var modes = [];
var modeIdx = 0;
var suggestions = [];
var MAX_LINES = 100;

var CHAT_HOLD_MS = 8000;
var fadeTimer = null;
var SCROLL_THRESHOLD = 30;
var scrollPaused = false;
var unreadCount = 0;

var activeTab = 'all';

var SETTINGS_KEY = 'ck_chat_settings_v2';
var CHANNEL_KEY = 'ck_last_channel';
var DEFAULTS = { defaultChannel: 'all', fadeOn: false, fadeSec: 8, size: 'md', timestamp: false };
var SIZE_PX = { sm: 12, md: 13, lg: 15 };
var settingsEl;
var initialChannelDone = false;
var settings = (function () {
    var s = {};
    try { s = JSON.parse(localStorage.getItem(SETTINGS_KEY) || '{}') || {}; } catch (e) { s = {}; }
    var out = {};
    for (var k in DEFAULTS) out[k] = (s[k] === undefined ? DEFAULTS[k] : s[k]);
    return out;
})();
function saveSettings() { try { localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings)); } catch (e) {} }
function saveLastChannel(name) { try { localStorage.setItem(CHANNEL_KEY, name || ''); } catch (e) {} }
function loadLastChannel() { try { return localStorage.getItem(CHANNEL_KEY); } catch (e) { return null; } }
function applySettings() {
    CHAT_HOLD_MS = (settings.fadeSec || 8) * 1000;
    chatEl.style.setProperty('--ck-fs', (SIZE_PX[settings.size] || 13) + 'px');
    if (!settings.fadeOn) chatShow(); else chatScheduleFade();
}
function timeStr() {
    var d = new Date();
    function p(n) { return (n < 10 ? '0' : '') + n; }
    return '[' + p(d.getHours()) + ':' + p(d.getMinutes()) + ']';
}

function channelToModeIdx(name) {
    if (!name || name === 'all') return 0;
    var target = (name === 'prox') ? 'proximity' : name;
    for (var i = 0; i < modes.length; i++) if (modes[i].name === target) return i + 1;
    return 0;
}

function applyInitialChannel() {
    if (initialChannelDone) return;
    initialChannelDone = true;
    var last = loadLastChannel();
    var name = (last !== null && last !== undefined) ? last : (settings.defaultChannel === 'prox' ? 'proximity' : '');
    modeIdx = channelToModeIdx(name);
}
function toggleSettings() { settingsEl.classList.toggle('ck-hidden'); chatWake(); }
function setSetting(key, val) {
    if (key === 'fadeOn') settings.fadeOn = (val === 'on');
    else if (key === 'timestamp') settings.timestamp = (val === 'on');
    else if (key === 'fadeSec') settings.fadeSec = parseInt(val, 10);
    else settings[key] = val;
    saveSettings(); renderSettings(); applySettings();
}
function resetSettings() {
    for (var k in DEFAULTS) settings[k] = DEFAULTS[k];
    saveSettings(); renderSettings(); applySettings();
}
function renderSettings() {
    var segs = document.querySelectorAll('.ck-seg');
    for (var i = 0; i < segs.length; i++) {
        var key = segs[i].getAttribute('data-set');
        var cur;
        if (key === 'fadeOn') cur = settings.fadeOn ? 'on' : 'off';
        else if (key === 'timestamp') cur = settings.timestamp ? 'on' : 'off';
        else cur = String(settings[key]);
        var opts = segs[i].querySelectorAll('.ck-seg-opt');
        for (var j = 0; j < opts.length; j++) {
            opts[j].classList.toggle('ck-seg-on', opts[j].getAttribute('data-val') === cur);
        }
    }
}

function post(name, body) {
    try {
        var x = new XMLHttpRequest();
        x.open('POST', 'http://' + RES + '/' + name, true);
        x.setRequestHeader('Content-Type', 'application/json; charset=UTF-8');
        x.send(body || '{}');

    } catch (e) {  }
}

function stripColors(t) {
    return String(t == null ? '' : t)
        .replace(/\^#[0-9A-Fa-f]{3,6}/g, '')
        .replace(/\^[0-9]/g, '')
        .replace(/~[a-z]~/gi, '')
        .replace(/\^[\*_=~\/r]/gi, '');
}

function messageToText(msg) {
    if (!msg) return '';
    if (msg.templateId === 'cookie_msg' && Array.isArray(msg.args) && msg.args.length >= 6) {
        var gobun = msg.args[1], label = msg.args[3], nick = msg.args[4], body = msg.args[5];
        var title = msg.args[6] || '';
        var head = '[' + gobun + ']';
        if (title) head += ' [' + title + ']';
        if (label) head += ' ' + label;
        if (nick) head += ' ' + nick;
        return head + ' : ' + body;
    }
    if (Array.isArray(msg.args)) {
        if (msg.args.length > 1) return msg.args[0] + ': ' + msg.args.slice(1).join(' ');
        return msg.args.join(' ');
    }
    if (typeof msg.message === 'string') return msg.message;
    return '';
}

function channelInfo(mode) {
    if (mode === 'admin') return { mod: 'ck-ch--admin', label: '시스템' };
    if (mode === 'proximity') return { mod: 'ck-ch--prox', label: '근접' };
    if (mode === 'faction') return { mod: 'ck-ch--faction', label: '팩션' };
    if (mode === 'ad') return { mod: 'ck-ch--ad', label: '광고' };
    if (mode === 'rp') return { mod: 'ck-ch--rp', label: 'RP' };
    return { mod: 'ck-ch--all', label: '전체' };
}

function spanEl(cls, text) {
    var s = document.createElement('span');
    s.className = cls;
    s.textContent = text == null ? '' : String(text);
    return s;
}

function safeHex(value, fallback) {
    value = String(value || '').trim();
    return /^#[0-9a-fA-F]{6}$/.test(value) ? value : fallback;
}

function renderCookieMsg(div, msg) {
    var a = msg.args;
    var gobun = a[1], labelClass = a[2], label = a[3], nick = a[4], body = a[5];
    var title = a[6] || '';
    var titleColor = safeHex(a[7], '#FFE08A');
    var titleBg = safeHex(a[8], '#251B0B');
    var src = a[9];
    var labelBg = safeHex(a[10], '#FFB800');
    var labelText = safeHex(a[11], '#1A1A1A');
    var ch = channelInfo(msg.mode);

    if (src) {
        div.dataset.src = String(src);
        div.dataset.gobun = String(gobun);
        div.dataset.nick = stripColors(nick);
    }
    div.appendChild(spanEl('ck-ch ' + ch.mod, ch.label));

    if (title) {
        var titleChip = spanEl('ck-title-chip', stripColors(title));
        titleChip.style.color = titleColor;
        titleChip.style.backgroundColor = titleBg;
        titleChip.style.borderColor = titleColor + '66';
        div.appendChild(titleChip);
    }

    div.appendChild(spanEl('ck-chip ck-chip--gobun', gobun));
    if (labelClass !== 'ck-chip--hide' && label) {
        var lc = 'ck-chip ck-chip--label';
        if (labelClass === 'ck-chip--admin') lc += ' ck-chip--admin';
        if (labelClass === 'ck-chip--faction') lc += ' ck-chip--faction';
        var labelChip = spanEl(lc, label);
        labelChip.style.backgroundColor = labelBg;
        labelChip.style.color = labelText;
        div.appendChild(labelChip);

        if (labelClass === 'ck-chip--faction') {
            div.style.borderLeftColor = labelBg;
        }
    }
    if (nick) div.appendChild(spanEl('ck-nick', stripColors(nick)));
    div.appendChild(spanEl('ck-body', stripColors(body)));
}

function classifyChannel(msg) {
    var t = msg && msg.templateId;

    if (t === 'cookie_join' || t === 'cookie_leave' || t === 'cookie_system' || t === 'cookie_notice'
        || t === 'cookie_warn' || t === 'cookie_rp') return 'system';
    if (msg && msg.mode === 'proximity') return 'prox';
    return 'other';
}
function rowVisibleInTab(channel, tab) {
    if (tab === 'all') return true;
    if (tab === 'prox') return channel === 'prox';
    if (tab === 'sys') return channel === 'system';
    return true;
}

function chatShow() {
    chatEl.style.transition = 'none';
    chatEl.classList.remove('ck-faded');
    void chatEl.offsetWidth;
    chatEl.style.transition = '';
}
function chatScheduleFade() {
    if (fadeTimer) { clearTimeout(fadeTimer); fadeTimer = null; }
    if (!settings.fadeOn || inputActive || scrollPaused) return;
    fadeTimer = setTimeout(function () { chatEl.classList.add('ck-faded'); }, CHAT_HOLD_MS);
}
function chatWake() { chatShow(); chatScheduleFade(); }

function atBottom() {
    return messagesEl.scrollHeight - messagesEl.scrollTop - messagesEl.clientHeight <= SCROLL_THRESHOLD;
}
function scrollToBottom() { messagesEl.scrollTop = messagesEl.scrollHeight; }
function showNewBadge() {
    if (!newBadgeEl) return;
    newBadgeEl.textContent = '새 메시지 ' + unreadCount + '개 ↓';
    newBadgeEl.classList.remove('ck-hidden');
}
function hideNewBadge() {
    unreadCount = 0;
    if (newBadgeEl) newBadgeEl.classList.add('ck-hidden');
}

function setTabDot(channel, on) {
    var name = channel === 'prox' ? 'prox' : (channel === 'system' ? 'sys' : null);
    if (!name || !tabEls) return;
    for (var i = 0; i < tabEls.length; i++) {
        if (tabEls[i].getAttribute('data-tab') === name) tabEls[i].classList.toggle('ck-tab--dot', !!on);
    }
}
function applyFilter() {
    var rows = messagesEl.childNodes;
    for (var i = 0; i < rows.length; i++) {
        var ch = rows[i].getAttribute && rows[i].getAttribute('data-ch');
        if (ch == null) continue;
        if (rowVisibleInTab(ch, activeTab)) rows[i].classList.remove('ck-hidden');
        else rows[i].classList.add('ck-hidden');
    }
    scrollToBottom();
}
function selectTab(tab) {
    activeTab = tab;
    if (tabEls) {
        for (var i = 0; i < tabEls.length; i++) {
            var name = tabEls[i].getAttribute('data-tab');
            var on = (name === tab);
            tabEls[i].classList.toggle('active', on);
            if (on) tabEls[i].classList.remove('ck-tab--dot');
        }
    }
    applyFilter();
    chatWake();
}

function addMessage(msg) {
    var mode = msg && msg.mode;
    var div = document.createElement('div');
    div.className = 'ck-wrap';
    if (mode === 'proximity') div.classList.add('ck-wrap--prox');
    else if (mode === 'admin') div.classList.add('ck-wrap--admin');
    else if (mode === 'faction') div.classList.add('ck-wrap--faction');
    else if (mode === 'ad') div.classList.add('ck-wrap--ad');
    else if (mode === 'rp') div.classList.add('ck-wrap--rp');
    else div.classList.add('ck-wrap--all');

    if (settings.timestamp) div.appendChild(spanEl('ck-time', timeStr()));

    if (msg && msg.templateId === 'cookie_join' && Array.isArray(msg.args) && msg.args.length >= 1) {
        div.className = 'ck-wrap ck-wrap--join';
        div.appendChild(spanEl('ck-ch ck-ch--join', '입장'));
        div.appendChild(spanEl('ck-body', stripColors(msg.args[0])));

    } else if (msg && msg.templateId === 'cookie_leave' && Array.isArray(msg.args) && msg.args.length >= 1) {
        div.className = 'ck-wrap ck-wrap--leave';
        div.appendChild(spanEl('ck-ch ck-ch--leave', '퇴장'));
        div.appendChild(spanEl('ck-body', stripColors(msg.args[0])));

    } else if (msg && msg.templateId === 'cookie_system' && Array.isArray(msg.args) && msg.args.length >= 1) {
        div.className = 'ck-wrap ck-wrap--system';
        div.appendChild(spanEl('ck-ch ck-ch--system', '시스템'));
        div.appendChild(spanEl('ck-body ck-body--system', stripColors(msg.args[0])));

    } else if (msg && msg.templateId === 'cookie_rp' && Array.isArray(msg.args) && msg.args.length >= 4) {

        div.className = 'ck-wrap ck-wrap--system';
        div.appendChild(spanEl('ck-ch ck-ch--system', '시스템'));

        const body = document.createElement('span');
        body.className = 'ck-body ck-body--system';
        body.appendChild(document.createTextNode(stripColors(msg.args[0])));
        body.appendChild(spanEl('ck-rp-hl ck-rp-hl--' + String(msg.args[3] || ''),
            stripColors(msg.args[1])));
        body.appendChild(document.createTextNode(stripColors(msg.args[2])));
        div.appendChild(body);

    } else if (msg && msg.templateId === 'cookie_notice' && Array.isArray(msg.args) && msg.args.length >= 1) {

        div.className = 'ck-wrap ck-wrap--notice';
        div.appendChild(spanEl('ck-notice', stripColors(msg.args[0])));

    } else if (msg && msg.templateId === 'cookie_warn' && Array.isArray(msg.args) && msg.args.length >= 1) {
        div.className = 'ck-wrap ck-wrap--warn';
        div.appendChild(spanEl('ck-warn', stripColors(msg.args[0])));

    } else if (msg && msg.templateId === 'cookie_msg' && Array.isArray(msg.args) && msg.args.length >= 6) {
        renderCookieMsg(div, msg);

    } else {
        div.appendChild(spanEl('ck-body', stripColors(messageToText(msg))));
    }

    var channel = classifyChannel(msg);
    div.setAttribute('data-ch', channel);

    messagesEl.appendChild(div);
    while (messagesEl.childNodes.length > MAX_LINES) messagesEl.removeChild(messagesEl.firstChild);

    if (!rowVisibleInTab(channel, activeTab)) {
        div.classList.add('ck-hidden');
        setTabDot(channel, true);
        return;
    }

    if (scrollPaused) { unreadCount++; showNewBadge(); }
    else { scrollToBottom(); }

    if (hideState !== 2) {
        chatEl.classList.remove('ck-hidden');
        chatWake();
    }
}

function openInput() {
    inputActive = true;
    inputLineEl.classList.remove('ck-hidden');
    syncIdleBar();
    applyInitialChannel();
    updateModeLabel();
    inputEl.value = '';
    renderSuggestions();

    chatEl.classList.remove('ck-hidden');
    chatShow();
    if (fadeTimer) { clearTimeout(fadeTimer); fadeTimer = null; }
    setTimeout(function () {
        inputEl.focus();

        var s = getComputedStyle(inputEl), r = inputEl.getBoundingClientRect();

    }, 0);

}
function closeInput() {
    inputActive = false;
    inputEl.value = '';
    inputLineEl.classList.add('ck-hidden');
    syncIdleBar();
    sugEl.classList.add('ck-hidden');
    sugEl.innerHTML = '';
    if (settingsEl) settingsEl.classList.add('ck-hidden');

    chatScheduleFade();
}
function submit(text) {
    text = (text || '').trim();
    var mode = currentModeName();
    closeInput();
    post('chatResult', JSON.stringify({ canceled: text === '', message: text, mode: mode }));

}
function cancel() {
    closeInput();
    post('chatResult', JSON.stringify({ canceled: true, message: '', mode: currentModeName() }));

}

var MODE_ORDER = {
    proximity: 10,  // 전체 다음
    ad:        20,
    rp:        30,
    admin:     40,  // 화면 표시는 시스템
    faction:   50
};

function sortModes() {
    modes.sort(function(a, b) {
        var av = MODE_ORDER[a.name] || 999;
        var bv = MODE_ORDER[b.name] || 999;
        if (av !== bv) return av - bv;
        return String(a.displayName || a.name).localeCompare(String(b.displayName || b.name), 'ko');
    });
}

function addMode(m) {
    if (!m || !m.name) return;
    if (!findMode(m.name)) {
        modes.push(m);
        sortModes();
    }
}
function removeMode(name) {
    var current = currentModeName();
    modes = modes.filter(function (x) { return x.name !== name; });
    sortModes();

    if (current === name || modeIdx > modes.length) {
        modeIdx = 0;
        if (inputActive) updateModeLabel();
    }
}
function findMode(name) { for (var i = 0; i < modes.length; i++) if (modes[i].name === name) return modes[i]; return null; }
function cycleMode() {
    // T로 채팅 입력 중 TAB을 누를 때:
    // 전체 → 근접 → 광고 → RP → 시스템(관리자) → 팩션 → 전체
    // 서버에서 권한 없는 모드는 애초에 내려오지 않으므로 자동으로 건너뜁니다.
    modeIdx = (modeIdx + 1) % (modes.length + 1);
    updateModeLabel();
    renderSuggestions();
    saveLastChannel(currentModeName());
}
function currentModeName() { return modeIdx === 0 ? '' : (modes[modeIdx - 1] && modes[modeIdx - 1].name) || ''; }
function updateModeLabel() {
    var label = modeIdx === 0 ? '전체' : ((modes[modeIdx - 1] && modes[modeIdx - 1].displayName) || '전체');
    modeEl.textContent = label;
    var m = modeIdx === 0 ? null : modes[modeIdx - 1];
    modeEl.style.color = (m && m.color) ? m.color : '#FFB800';
}

function addSuggestion(s) {
    if (Array.isArray(s)) { s.forEach(addOneSug); }
    else if (s && s.name) { addOneSug(s); }
    renderSuggestions();
}
function addOneSug(s) { if (s && s.name && !suggestions.find(function (x) { return x.name === s.name; })) suggestions.push({ name: s.name, help: s.help || '' }); }
function removeSuggestion(name) { suggestions = suggestions.filter(function (x) { return x.name !== name; }); renderSuggestions(); }
function renderSuggestions() {
    if (!inputEl || !sugEl) return;
    var v = (inputEl.value || '').trim();
    if (!inputActive || v.charAt(0) !== '/') { sugEl.classList.add('ck-hidden'); sugEl.innerHTML = ''; return; }
    var matches = suggestions.filter(function (s) { return s.name.indexOf(v) === 0; }).slice(0, 6);
    sugEl.innerHTML = '';
    if (matches.length === 0) { sugEl.classList.add('ck-hidden'); return; }
    matches.forEach(function (s) {
        var row = document.createElement('div'); row.className = 'ck-sug';
        var n = document.createElement('span'); n.className = 'ck-sug-name'; n.textContent = s.name; row.appendChild(n);
        if (s.help) { var h = document.createElement('span'); h.className = 'ck-sug-help'; h.textContent = s.help; row.appendChild(h); }
        sugEl.appendChild(row);
    });
    sugEl.classList.remove('ck-hidden');
}

function applyHideState(s) {
    hideState = s;
    if (s === 2) chatEl.classList.add('ck-hidden');
    else chatEl.classList.remove('ck-hidden');
}

var menuEl, payEl, menuTarget = null;

function menuFocus(on) {
    post('menuFocus', JSON.stringify({ on: !!on }));
}

function closeMenu() {
    if (menuEl) menuEl.classList.add('ck-hidden');
    menuTarget = null;
    if (payEl && payEl.classList.contains('ck-hidden')) menuFocus(false);
}

function openMenu(x, y, target) {
    if (!menuEl) return;

    if (inputActive) cancel();

    menuTarget = target;
    document.getElementById('ck-menu-title').textContent = target.nick + ' (' + target.gobun + ')';

    var w = 168, h = 110;
    var left = Math.min(x, window.innerWidth - w - 8);
    var top = Math.min(y, window.innerHeight - h - 8);
    menuEl.style.left = Math.max(8, left) + 'px';
    menuEl.style.top = Math.max(8, top) + 'px';
    menuEl.classList.remove('ck-hidden');
    menuFocus(true);

}

function closePay() {
    if (payEl) payEl.classList.add('ck-hidden');
    menuFocus(false);
}

function openPay(target) {
    if (!payEl) return;
    document.getElementById('ck-pay-title').textContent =
        target.nick + ' (' + target.gobun + ') 님에게 은행송금';
    document.getElementById('ck-pay-sub') && null;
    var amt = document.getElementById('ck-pay-amount');
    amt.value = '';
    document.getElementById('ck-pay-hint').textContent = '';
    document.getElementById('ck-pay-send').disabled = true;
    payEl.classList.remove('ck-hidden');
    menuFocus(true);
    setTimeout(function () { amt.focus(); }, 50);
}

function wirePlayerMenu() {
    menuEl = document.getElementById('ck-menu');
    payEl = document.getElementById('ck-pay');
    if (!menuEl || !payEl) return;

    messagesEl.addEventListener('click', function (e) {
        var row = e.target.closest ? e.target.closest('.ck-wrap') : null;
        if (!row || !row.dataset.src) return;
        openMenu(e.clientX + 2, e.clientY + 2, {
            src: row.dataset.src,
            gobun: row.dataset.gobun,
            nick: row.dataset.nick
        });
    });

    document.getElementById('ck-menu-x').addEventListener('click', closeMenu);

    var items = menuEl.querySelectorAll('.ck-menu-item');
    for (var i = 0; i < items.length; i++) {
        (function (b) {
            b.addEventListener('click', function () {
                var t = menuTarget;
                menuEl.classList.add('ck-hidden');
                if (!t) return;
                if (b.dataset.act === 'profile') {
                    post('menuProfile', JSON.stringify({ src: t.src, nick: t.nick }));
                    menuFocus(false);
                } else if (b.dataset.act === 'pay') {
                    openPay(t);
                    menuTarget = t;
                }
            });
        })(items[i]);
    }

    var amt = document.getElementById('ck-pay-amount');
    amt.addEventListener('input', function () {
        var raw = amt.value.replace(/[^0-9]/g, '').slice(0, 12);
        amt.value = raw ? Number(raw).toLocaleString('ko-KR') : '';
        document.getElementById('ck-pay-send').disabled = !(Number(raw) > 0);
        document.getElementById('ck-pay-hint').textContent = '';
    });
    amt.addEventListener('keydown', function (e) {
        e.stopPropagation();
        if (e.key === 'Enter') doPay();
    });

    document.getElementById('ck-pay-cancel').addEventListener('click', closePay);
    document.getElementById('ck-pay-send').addEventListener('click', doPay);
}

function doPay() {
    if (!menuTarget) return;
    var raw = document.getElementById('ck-pay-amount').value.replace(/[^0-9]/g, '');
    var n = Number(raw);
    if (!(n > 0)) {
        document.getElementById('ck-pay-hint').textContent = '금액을 입력해주세요';
        return;
    }
    document.getElementById('ck-pay-send').disabled = true;
    post('menuPay', JSON.stringify({ src: menuTarget.src, amount: n }));
    closePay();
}

var escMode = false;
var idleBarEl = null;

function syncIdleBar() {
    if (!idleBarEl) return;
    var show = escMode && !inputActive;
    idleBarEl.classList.toggle('ck-hidden', !show);
    if (show) {
        var chEl = document.getElementById('ck-idle-ch');
        if (chEl) chEl.textContent = (modeIdx === 0 ? '전체' : ((modes[modeIdx - 1] && modes[modeIdx - 1].displayName) || '전체'));
    }
}

function setEscMode(on) {
    if (escMode === on) return;
    escMode = on;
    chatEl.classList.toggle('ck-esc', on);
    if (on) {
        chatEl.classList.remove('ck-hidden');
        chatShow();
        if (fadeTimer) { clearTimeout(fadeTimer); fadeTimer = null; }
    } else if (settings.fadeOn) {
        chatScheduleFade();
    }
    syncIdleBar();

}

window.addEventListener('message', function (e) {
    var d = e.data || {};
    switch (d.type) {
        case 'ON_MESSAGE': addMessage(d.message); break;
        case 'ON_OPEN': openInput(); break;

        case 'ESC_MODE': setEscMode(!!d.on); break;
        case 'ON_SCREEN_STATE_CHANGE': applyHideState(d.hideState); break;
        case 'CK_HARD': chatEl.classList.toggle('ck-hard-off', !!d.on); break;
        case 'ON_CLEAR': messagesEl.innerHTML = ''; hideNewBadge(); break;
        case 'ON_MODE_ADD': addMode(d.mode); break;
        case 'ON_MODE_REMOVE': removeMode(d.name); break;
        case 'ON_SUGGESTION_ADD': addSuggestion(d.suggestion); break;
        case 'ON_SUGGESTION_REMOVE': removeSuggestion(d.name); break;
        default: break;
    }
});

function onKey(e) {
    if (!inputActive) return;
    if (e.key === 'Enter') { e.preventDefault(); submit(inputEl.value); }
    else if (e.key === 'Escape') { e.preventDefault(); cancel(); }
    else if (e.key === 'Tab') { e.preventDefault(); cycleMode(); }
}

window.addEventListener('load', function () {
    chatEl = document.getElementById('chat');
    messagesEl = document.getElementById('ck-messages');
    inputLineEl = document.getElementById('ck-inputline');
    modeEl = document.getElementById('ck-mode');
    inputEl = document.getElementById('ck-input');
    sugEl = document.getElementById('ck-suggestions');
    newBadgeEl = document.getElementById('ck-newbadge');
    tabEls = document.querySelectorAll('.ck-tab');

    chatEl.classList.remove('ck-hidden');
    inputLineEl.classList.add('ck-hidden');
    document.addEventListener('keydown', onKey);
    inputEl.addEventListener('input', renderSuggestions);

    idleBarEl = document.getElementById('ck-idlebar');
    if (idleBarEl) {
        idleBarEl.addEventListener('click', function () {
            post('requestOpen', JSON.stringify({}));
        });
    }

    wirePlayerMenu();

    document.addEventListener('keydown', function (e) {
        if (e.key !== 'Escape') return;
        if (payEl && !payEl.classList.contains('ck-hidden')) { closePay(); e.stopPropagation(); return; }
        if (menuEl && !menuEl.classList.contains('ck-hidden')) { closeMenu(); e.stopPropagation(); }
    }, true);

    for (var i = 0; i < tabEls.length; i++) {
        (function (el) { el.addEventListener('click', function () { selectTab(el.getAttribute('data-tab')); }); })(tabEls[i]);
    }

    messagesEl.addEventListener('scroll', function () {
        if (atBottom()) {
            scrollPaused = false;
            hideNewBadge();
            chatScheduleFade();
        } else {
            scrollPaused = true;
            if (fadeTimer) { clearTimeout(fadeTimer); fadeTimer = null; }
            chatShow();
        }
    });

    if (newBadgeEl) newBadgeEl.addEventListener('click', function () {
        scrollToBottom();
        scrollPaused = false;
        hideNewBadge();
        chatScheduleFade();
    });

    settingsEl = document.getElementById('ck-settings');

    var gear = document.querySelector('.ck-gear');
    if (gear) gear.addEventListener('click', toggleSettings);

    var setClose = document.getElementById('ck-set-close');
    if (setClose) setClose.addEventListener('click', function () {
        settingsEl.classList.add('ck-hidden');
    });
    var setReset = document.getElementById('ck-set-reset');
    if (setReset) setReset.addEventListener('click', resetSettings);

    var opts = document.querySelectorAll('.ck-seg .ck-seg-opt');
    for (var s = 0; s < opts.length; s++) {
        (function (opt) {
            opt.addEventListener('click', function () {
                var seg = opt.parentNode;
                setSetting(seg.getAttribute('data-set'), opt.getAttribute('data-val'));
            });
        })(opts[s]);
    }

    renderSettings();
    applySettings();
});

// COOKIE CHAT TAB CHANNELS V13.9.5

// COOKIE CHAT MODE SYNC + CLEAN LABEL V13.9.9
