

'use strict';

var RES = 'cookie_esc';

var root = document.getElementById('esc');
var tabsEl = document.getElementById('tabs');
var brandEl = document.getElementById('brand-en');
var shortcutsEl = document.getElementById('shortcuts');
var newsEl = document.getElementById('news');
var suggestTitle = document.getElementById('suggest-title');
var suggestDesc = document.getElementById('suggest-desc');

var statusInput = document.getElementById('status-input');
var statusLen = document.getElementById('status-len');
var statusMaxEl = document.getElementById('status-max');
var statusHint = document.getElementById('status-hint');
var statusBox = document.getElementById('status-box');

var confirmEl = document.getElementById('confirm');
var confirmTitle = document.getElementById('confirm-title');
var confirmSub = document.getElementById('confirm-sub');
var keysEl = document.getElementById('keys');

var cfg = null;
var activeTab = 'play';
var confirmAction = null;
var statusMax = 20;

function post(name, body) {
    return fetch('https://' + RES + '/' + name, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body || {})
    }).then(function (r) { return r.json(); }).catch(function () { return {}; });
}

function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined && text !== null) n.textContent = String(text);
    return n;
}

function clear(node) {
    while (node.firstChild) node.removeChild(node.firstChild);
}

function won(n) {
    var v = Number(n || 0);
    return v.toLocaleString('ko-KR') + ' 원';
}

function playtime(min) {
    var m = Number(min || 0);
    var h = Math.floor(m / 60);
    var r = m % 60;
    if (h <= 0) return r + '분';
    return h + '시간 ' + r + '분';
}

var VIEWS = {
    play: document.getElementById('tab-play'),
    userlist: document.getElementById('tab-userlist'),
    event: document.getElementById('tab-event'),
    rank: document.getElementById('tab-rank'),
    soon: document.getElementById('tab-soon')
};

function showView(name) {
    Object.keys(VIEWS).forEach(function (k) {
        VIEWS[k].classList.toggle('hidden', k !== name);
    });
}

function selectTab(tab) {

    if (tab.key === 'shop') {
        post('openCookieStore', {});
        return;
    }

    if (tab.key === 'map') {
        post('openMap', {});
        return;
    }

    activeTab = tab.key;

    var btns = tabsEl.querySelectorAll('.tab');
    for (var i = 0; i < btns.length; i++) {
        btns[i].classList.toggle('on', btns[i].dataset.key === tab.key);
    }

    if (!tab.ready) {
        document.getElementById('soon-title').textContent = tab.label + ' 준비 중';
        showView('soon');
        return;
    }

    if (tab.key === 'userlist') {
        showView('userlist');
        loadUserlist();
        return;
    }

    if (tab.key === 'event') {
        // V14: ESC에서도 F3와 동일한 COOKIE 이벤트/출석/퀘스트 HUD를 사용합니다.
        post('openEventHub', {});
        return;
    }

    if (tab.key === 'rank') {
        showView('rank');
        loadRankings();
        return;
    }

    showView('play');
}

function renderTabs(tabs) {
    clear(tabsEl);
    (tabs || []).forEach(function (t) {
        var b = el('button', 'tab' + (t.ready ? '' : ' soon'), t.label);
        b.dataset.key = t.key;
        if (t.badge) b.appendChild(el('span', 'tab-badge', t.badge));
        b.addEventListener('click', function () { selectTab(t); });
        tabsEl.appendChild(b);
    });
    if (tabs && tabs.length) selectTab(tabs[0]);
}

function renderShortcuts(list) {
    clear(shortcutsEl);
    (list || []).forEach(function (s) {
        var b = el('button', 'row-btn');
        var main = el('span', 'row-main');
        main.appendChild(el('span', 'row-title', s.title));
        main.appendChild(el('span', 'row-desc', s.desc || ''));
        b.appendChild(main);
        b.appendChild(el('span', 'row-arrow', '›'));
        b.addEventListener('click', function () {
            if (!s.ready) {
                toast(s.title + ' 준비 중입니다');
                return;
            }
            if (s.tab && cfg && cfg.tabs) {
                for (var i = 0; i < cfg.tabs.length; i++) {
                    if (cfg.tabs[i].key === s.tab) { selectTab(cfg.tabs[i]); return; }
                }
            }
        });
        shortcutsEl.appendChild(b);
    });
}

function imgSrc(v) {
    if (!v) return '';
    if (/^data:/i.test(v)) return v;
    if (/^https?:\/\//i.test(v)) return v;
    return String(v).replace(/^\/+/, '');
}

function renderBody(text, target) {
    clear(target);
    var lines = String(text || '').split(/\r?\n/);

    lines.forEach(function (raw) {
        var line = raw.trim();
        if (line === '') {
            target.appendChild(el('div', 'body-gap'));
            return;
        }

        var m = line.match(/^[*\-]\s*(.*)$/);
        if (m) {
            var li = el('div', 'body-bullet');
            li.appendChild(el('span', 'body-dot', '●'));
            li.appendChild(el('span', 'body-li', m[1]));
            target.appendChild(li);
        } else {
            target.appendChild(el('div', 'body-line', line));
        }
    });
}

var newsAll = [];

function openUpdateDetail(n) {
    document.getElementById('ud-badge').textContent = n.badge || n.tag || '패치노트';
    document.getElementById('ud-title').textContent = n.title || '';
    renderBody(n.body, document.getElementById('ud-body'));
    document.getElementById('upd-detail').classList.remove('hidden');
}

document.getElementById('ud-close').addEventListener('click', function () {
    document.getElementById('upd-detail').classList.add('hidden');
});

var UPD_PER_PAGE = 8;
var updPage = 1;

function renderUpdPager() {
    var pager = document.getElementById('ua-pager');
    clear(pager);

    var pages = Math.ceil(newsAll.length / UPD_PER_PAGE);
    if (pages <= 1) return;

    for (var i = 1; i <= pages; i++) {
        (function (p) {
            var b = el('button', 'upd-page-btn' + (p === updPage ? ' on' : ''), String(p));
            b.addEventListener('click', function () {
                updPage = p;
                renderUpdateAll();
            });
            pager.appendChild(b);
        })(i);
    }
}

function renderUpdateAll() {
    var box = document.getElementById('ua-list');
    clear(box);

    if (!newsAll.length) {
        box.appendChild(el('div', 'notice-empty', '등록된 업데이트가 없습니다'));
        clear(document.getElementById('ua-pager'));
        return;
    }

    var start = (updPage - 1) * UPD_PER_PAGE;
    newsAll.slice(start, start + UPD_PER_PAGE).forEach(function (n) {
        var row = el('div', 'upd-row');

        var head = el('div', 'upd-row-head');
        head.appendChild(el('span', 'uc-date', n.date || '-'));

        var t = el('span', 'uc-title');
        t.appendChild(el('span', 'uc-badge', n.badge || '패치노트'));
        t.appendChild(el('span', 'uc-title-text', n.title || ''));
        head.appendChild(t);

        head.appendChild(el('span', 'uc-admin', n.author || '운영진'));

        var more = el('button', 'uc-more', '펼치기');
        head.appendChild(more);
        row.appendChild(head);

        var body = el('div', 'upd-row-body hidden');
        renderBody(n.body, body);
        row.appendChild(body);

        more.addEventListener('click', function () {
            var open = body.classList.toggle('hidden');
            more.textContent = open ? '펼치기' : '닫기';
        });

        box.appendChild(row);
    });

    renderUpdPager();
}

document.getElementById('news-more').addEventListener('click', function () {
    updPage = 1;
    renderUpdateAll();
    document.getElementById('upd-all').classList.remove('hidden');
});

document.getElementById('ua-close').addEventListener('click', function () {
    document.getElementById('upd-all').classList.add('hidden');
});

function renderNews(list) {
    clear(newsEl);

    if (!list || !list.length) {
        newsEl.appendChild(el('div', 'notice-empty', '등록된 업데이트가 없습니다'));
        return;
    }

    list.forEach(function (n) {
        var item = el('button', 'news-item');
        item.appendChild(el('span', 'news-tag', n.badge || n.tag || '패치노트'));

        var main = el('div', 'news-main');
        main.appendChild(el('div', 'news-title', n.title || ''));

        item.appendChild(main);

        item.addEventListener('click', function () { openUpdateDetail(n); });
        newsEl.appendChild(item);
    });
}

function renderBanners(banners) {
    var img = document.getElementById('notice-img');
    var box = document.getElementById('notice-banner');
    if (!banners || !banners.length) return;

    var src = imgSrc(banners[0].image);
    if (!src) return;

    img.onerror = function () {
        img.classList.add('hidden');
        box.classList.remove('hidden');
    };
    img.onload = function () {
        img.classList.remove('hidden');
        box.classList.add('hidden');
    };
    img.src = src;
}

function loadNews() {
    post('news', {}).then(function (r) {
        if (!r) return;
        newsAll = r.updates || [];
        if (newsAll.length) renderNews(newsAll.slice(0, 3));
        renderBanners(r.banners);
    });
}

function renderNotice(n) {
    var img = document.getElementById('notice-img');
    var box = document.getElementById('notice-banner');
    if (!n) return;

    document.getElementById('notice-kicker').textContent = n.kicker || '쿠키서버';
    document.getElementById('notice-title').textContent = n.title || '';
    document.getElementById('notice-sub').textContent = n.sub || '';

    if (n.image) {
        img.onerror = function () {
            img.classList.add('hidden');
            box.classList.remove('hidden');
        };
        img.onload = function () {
            img.classList.remove('hidden');
            box.classList.add('hidden');
        };
        img.src = n.image;
    } else {
        img.classList.add('hidden');
        box.classList.remove('hidden');
    }
}

function openNoticeDetail(n) {
    document.getElementById('nd-text').textContent = n.text || '';
    document.getElementById('nd-admin').textContent = n.admin_name || '운영진';
    document.getElementById('nd-at').textContent = n.at || '';
    document.getElementById('notice-detail').classList.remove('hidden');
}

document.getElementById('nd-close').addEventListener('click', function () {
    document.getElementById('notice-detail').classList.add('hidden');
});

function loadNotices() {
    var box = document.getElementById('notice-list');
    clear(box);
    box.appendChild(el('div', 'notice-empty', '불러오는 중...'));

    post('notices', {}).then(function (r) {
        clear(box);
        var list = (r && r.list) || [];

        if (!list.length) {
            box.appendChild(el('div', 'notice-empty', '등록된 공지가 없습니다'));
            return;
        }

        list.slice(0, 4).forEach(function (n) {
            var row = el('button', 'notice-row');
            row.appendChild(el('div', 'notice-row-text', n.text || ''));

            var meta = el('div', 'notice-row-meta');
            meta.appendChild(el('span', 'notice-row-admin', n.admin_name || '운영진'));
            meta.appendChild(el('span', 'notice-row-at', n.at || ''));
            row.appendChild(meta);

            row.addEventListener('click', function () { openNoticeDetail(n); });
            box.appendChild(row);
        });
    });
}

var toastTimer = null;
function toast(msg) {
    statusHint.textContent = msg;
    statusHint.className = 'status-hint';
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { statusHint.textContent = ''; }, 2200);
}

var userlistAllRows = [];
var userlistActiveFilter = { kind: 'all', key: 'all', label: '전체' };

function sameFilter(a, b) {
    return a && b && a.kind === b.kind && String(a.key) === String(b.key);
}

function renderPopulation(targetId, list, emptyText) {
    var box = document.getElementById(targetId);
    clear(box);
    list = list || [];

    var all = el('button', 'population-row population-row--filter');
    all.type = 'button';
    all.dataset.kind = 'all';
    all.dataset.key = 'all';
    if (userlistActiveFilter.kind === 'all') all.classList.add('active');
    var allName = el('div', 'population-name');
    allName.appendChild(el('span', '', '전체 보기'));
    all.appendChild(allName);
    var allNum = el('div', 'population-num');
    allNum.appendChild(el('strong', '', String(userlistAllRows.length)));
    all.appendChild(allNum);
    all.addEventListener('click', function () {
        userlistActiveFilter = { kind: 'all', key: 'all', label: '전체' };
        renderUserRows(userlistAllRows);
        renderPopulation(targetId, list, emptyText);
    });
    box.appendChild(all);

    if (!list.length) {
        box.appendChild(el('div', 'population-empty', emptyText));
        return;
    }

    list.forEach(function (it) {
        var row = el('button', 'population-row population-row--filter');
        row.type = 'button';
        row.dataset.kind = it.kind || '';
        row.dataset.key = String(it.key || '');
        if (sameFilter(userlistActiveFilter, it)) row.classList.add('active');
        if (it.color && /^#[0-9a-fA-F]{6}$/.test(it.color)) {
            row.style.borderColor = it.color + '66';
            row.style.boxShadow = 'inset 3px 0 0 ' + it.color;
        }
        var name = el('div', 'population-name');
        if (it.emoji) name.appendChild(el('span', 'population-emoji', it.emoji));
        name.appendChild(el('span', '', it.label || it.key || '-'));
        row.appendChild(name);
        var nums = el('div', 'population-num');
        nums.appendChild(el('strong', '', String(Number(it.count || 0))));
        if (Number(it.duty || 0) > 0) nums.appendChild(el('small', '', '근무 ' + Number(it.duty || 0)));
        row.appendChild(nums);
        row.addEventListener('click', function () {
            userlistActiveFilter = { kind: it.kind, key: String(it.key), label: it.label || it.key || '-' };
            renderUserRows(userlistAllRows);
            renderPopulation(targetId, list, emptyText);
        });
        box.appendChild(row);
    });
}

function userMatchesFilter(u) {
    var f = userlistActiveFilter;
    if (!f || f.kind === 'all') return true;
    if (f.kind === 'faction') return String(u.factionId || '') === String(f.key);
    if (f.kind === 'job') return String(u.jobKey || 'unemployed') === String(f.key);
    return true;
}

function renderUserRows(list) {
    var rows = document.getElementById('userlist-rows');
    clear(rows);
    var filtered = (list || []).filter(userMatchesFilter);
    if (!filtered.length) {
        rows.appendChild(el('div', 'userlist-empty', userlistActiveFilter.kind === 'all'
            ? '접속 중인 플레이어가 없습니다'
            : userlistActiveFilter.label + '에 해당하는 접속자가 없습니다'));
        return;
    }
    filtered.forEach(function (u) {
        var row = el('div', 'user-row');
        row.appendChild(el('span', 'user-gobun', '[' + (u.gobun || '-') + ']'));

        var identity = el('div', 'user-identity');
        identity.appendChild(el('span', 'user-nick', u.nick || '-'));
        identity.appendChild(el('span', 'user-status', u.status || '상태 메시지 없음'));
        row.appendChild(identity);

        var badges = el('div', 'user-badges');
        if (u.afk) badges.appendChild(el('span', 'user-afk', '잠수'));
        badges.appendChild(el('span', 'user-job' + (u.onduty ? ' duty' : ''), u.job || '시민'));
        if (u.faction) {
            var facText = u.faction + (u.factionGrade ? (' ' + u.factionGrade) : '');
            var facBadge = el('span', 'user-faction' + (u.factionDuty ? ' duty' : ''), facText);
            if (u.factionColor && /^#[0-9a-fA-F]{6}$/.test(u.factionColor)) {
                facBadge.style.borderColor = u.factionColor + '88';
                facBadge.style.color = u.factionColor;
                facBadge.style.background = u.factionColor + '18';
            }
            badges.appendChild(facBadge);
        }
        row.appendChild(badges);
        rows.appendChild(row);
    });
}

function loadUserlist() {
    var rows = document.getElementById('userlist-rows');
    var count = document.getElementById('userlist-count');
    clear(rows);
    rows.appendChild(el('div', 'userlist-empty', '불러오는 중...'));
    userlistAllRows = [];
    userlistActiveFilter = { kind: 'all', key: 'all', label: '전체' };
    renderPopulation('user-population-summary', [], '접속 현황을 불러오는 중...');

    post('userlist', {}).then(function (r) {
        var list = (r && r.list) || [];
        var summary = (r && r.summary) || {};
        userlistAllRows = list;
        count.textContent = (Number(summary.total) || list.length) + '명';

        var jobs = (summary.jobs || []).map(function (x) { return Object.assign({}, x, { kind: 'job' }); });
        var factions = (summary.factions || []).map(function (x) { return Object.assign({}, x, { kind: 'faction' }); });
        var population = jobs.concat(factions);
        renderPopulation('user-population-summary', population, '표시할 접속 현황이 없습니다');

        if (!r || !r.ok) {
            clear(rows);
            rows.appendChild(el('div', 'userlist-empty', '접속자 목록을 불러오지 못했습니다'));
            return;
        }
        renderUserRows(list);
    });
}

function eventTime(min) {
    return playtime(Number(min || 0));
}

function eventActivityTime(sec) {
    var s = Math.max(0, Math.floor(Number(sec || 0)));
    var h = Math.floor(s / 3600);
    var m = Math.floor((s % 3600) / 60);
    var r = s % 60;
    if (h > 0) return h + '시간 ' + m + '분';
    if (m > 0) return m + '분 ' + r + '초';
    return r + '초';
}

function renderEventRanking(box, ranking, metric) {
    clear(box);
    ranking = ranking || [];
    if (!ranking.length) {
        box.appendChild(el('div', 'event-empty', '아직 기록이 없습니다'));
        return;
    }
    ranking.slice(0, 3).forEach(function (r) {
        var row = el('div', 'event-rank-row rank-' + r.rank);
        row.appendChild(el('span', 'event-rank-no', String(r.rank)));
        var who = el('div', 'event-rank-who');
        who.appendChild(el('strong', '', r.nickname || '알 수 없음'));
        var sub = r.gobun ? ('[' + r.gobun + ']') : '';
        if (metric === 'crime') sub += ' · 전과 ' + Number(r.offenseCount || 0) + '건';
        who.appendChild(el('small', '', sub));
        row.appendChild(who);
        var eventValue = metric === 'activity'
            ? eventActivityTime(r.seconds)
            : (metric === 'crime'
                ? (Number(r.score || 0).toLocaleString('ko-KR') + '점')
                : eventTime(r.minute));
        row.appendChild(el('span', 'event-rank-value', eventValue));
        box.appendChild(row);
    });
}

function loadEvents() {
    var box = document.getElementById('event-rows');
    var state = document.getElementById('event-state');
    var meta = document.getElementById('event-meta');
    clear(box);
    box.appendChild(el('div', 'event-loading', '이벤트 정보를 불러오는 중...'));
    state.textContent = '불러오는 중';
    state.className = 'state-pill';

    post('events', {}).then(function (r) {
        clear(box);
        if (!r || !r.ok) {
            state.textContent = '연결 실패';
            state.className = 'state-pill off';
            meta.textContent = '이벤트 데이터를 불러오지 못했습니다.';
            box.appendChild(el('div', 'event-loading', '잠시 후 다시 시도해주세요.'));
            return;
        }

        state.textContent = r.enabled ? '진행 중' : '일시정지';
        state.className = 'state-pill' + (r.enabled ? ' on' : ' off');
        meta.textContent = '집계 시작 · ' + (r.startedAt || '-');

        (r.events || []).forEach(function (ev) {
            var card = el('div', 'event-card');
            var head = el('div', 'event-card-head');
            var titleWrap = el('div', 'event-title-wrap');
            titleWrap.appendChild(el('span', 'event-badge', ev.badge || 'EVENT'));
            titleWrap.appendChild(el('div', 'event-title', ev.title || '이벤트'));
            head.appendChild(titleWrap);

            var mine = ev.my || {};
            var metric = ev.metric || ev.key || '';
            var myValue = metric === 'activity'
                ? eventActivityTime(mine.seconds)
                : (metric === 'crime'
                    ? (Number(mine.score || 0).toLocaleString('ko-KR') + '점')
                    : eventTime(mine.minute));
            var myText = mine.rank ? ('내 순위 ' + mine.rank + '위 · ' + myValue) : '내 기록 없음';
            head.appendChild(el('div', 'event-my', myText));
            card.appendChild(head);
            card.appendChild(el('div', 'event-desc', ev.description || ''));

            var rewards = el('div', 'event-rewards');
            (ev.rewards || []).forEach(function (rw) { rewards.appendChild(el('span', 'reward-chip', rw)); });
            card.appendChild(rewards);

            var rankBox = el('div', 'event-ranking');
            renderEventRanking(rankBox, ev.ranking || [], metric);
            card.appendChild(rankBox);
            box.appendChild(card);
        });
    });
}

var rankCategories = [];
var activeRankKey = null;

function rankValue(row, unit) {
    var value = Number((row && row.value) || 0);
    if (unit === 'kg') return value.toFixed(2) + ' kg';
    if (unit === 'minute') return playtime(value);
    if (unit === 'point') return value.toLocaleString('ko-KR') + '점';
    if (unit === 'count') return value.toLocaleString('ko-KR') + '건';
    if (unit === 'purity') return value.toFixed(0) + '%';
    return String(value);
}

function renderRankCategory(category) {
    if (!category) return;
    activeRankKey = category.key;
    var buttons = document.querySelectorAll('#rank-tabs .rank-tab');
    for (var i = 0; i < buttons.length; i++) buttons[i].classList.toggle('on', buttons[i].dataset.key === category.key);

    document.getElementById('rank-desc').textContent = category.description || '';
    var rows = document.getElementById('rank-rows');
    clear(rows);
    var list = category.rows || [];
    if (!list.length) {
        rows.appendChild(el('div', 'rank-empty', '아직 등록된 기록이 없습니다'));
        return;
    }

    list.forEach(function (r) {
        var row = el('div', 'rank-row rank-' + r.rank);
        var no = el('div', 'rank-no', String(r.rank));
        row.appendChild(no);

        var who = el('div', 'rank-who');
        who.appendChild(el('strong', '', r.nickname || '알 수 없음'));
        var sub = r.gobun ? '[' + r.gobun + ']' : '';
        if (r.fish) sub += (sub ? ' · ' : '') + r.fish;
        if (r.mineralLabel || r.mineral) sub += (sub ? ' · ' : '') + (r.mineralLabel || r.mineral);
        if (r.rarityLabel) sub += (sub ? ' · ' : '') + r.rarityLabel;
        if (r.at) sub += (sub ? ' · ' : '') + r.at;
        who.appendChild(el('small', '', sub));
        row.appendChild(who);
        row.appendChild(el('div', 'rank-value', rankValue(r, category.unit)));
        rows.appendChild(row);
    });
}

function loadRankings() {
    var tabs = document.getElementById('rank-tabs');
    var rows = document.getElementById('rank-rows');
    var note = document.getElementById('rank-note');
    clear(tabs); clear(rows);
    rows.appendChild(el('div', 'rank-empty', '순위 데이터를 불러오는 중...'));
    note.textContent = '';

    post('rankings', {}).then(function (r) {
        clear(tabs);
        rankCategories = (r && r.categories) || [];
        if (!r || !r.ok || !rankCategories.length) {
            clear(rows);
            rows.appendChild(el('div', 'rank-empty', '순위 데이터를 불러오지 못했습니다'));
            return;
        }

        rankCategories.forEach(function (category) {
            var b = el('button', 'rank-tab');
            b.dataset.key = category.key;
            b.appendChild(el('span', 'rank-tab-icon', category.icon || '★'));
            b.appendChild(el('span', '', category.label || category.key));
            b.addEventListener('click', function () { renderRankCategory(category); });
            tabs.appendChild(b);
        });

        note.textContent = r.note || '';
        var first = rankCategories[0];
        if (activeRankKey) {
            for (var i = 0; i < rankCategories.length; i++) {
                if (rankCategories[i].key === activeRankKey) { first = rankCategories[i]; break; }
            }
        }
        renderRankCategory(first);
    });
}

function setText(id, v) {
    document.getElementById(id).textContent = (v === null || v === undefined || v === '') ? '-' : String(v);
}

function fill(d) {
    setText('me-nick', d.nick || '플레이어');
    setText('me-gobun', d.gobun ? '[' + d.gobun + ']' : '[-]');

    setText('me-emoji', d.emoji || '');
    setText('me-job', d.job || '시민');

    setText('me-cash', won(d.cash));
    setText('me-bank', won(d.bank));
    setText('me-phone', d.phone);
    setText('me-jumin', d.jumin);
    setText('me-driver-license', d.driverLicenseNo);
    setText('me-age', d.age ? (d.age + '세') : null);
    setText('me-org', d.org || '없음');
    setText('me-grade', d.grade);
    setText('me-play', playtime(d.rpMin));
    setText('me-job-time', playtime(d.jobMin));

    statusInput.value = d.status || '';
    statusLen.textContent = String((d.status || '').length);
}

function fillFail() {
    toast('서버에서 내 정보를 받지 못했습니다');
}

statusInput.addEventListener('input', function () {
    statusLen.textContent = String(statusInput.value.length);
});

function applyStatus(text) {
    post('setStatus', { text: text }).then(function (r) {
        if (r && r.ok) {
            statusInput.value = r.status || '';
            statusLen.textContent = String((r.status || '').length);
            statusHint.textContent = (r.status ? '상태 메시지를 적용했습니다' : '상태 메시지를 해제했습니다');
            statusHint.className = 'status-hint ok';
        } else {
            statusHint.textContent = (r && r.reason) || '적용에 실패했습니다';
            statusHint.className = 'status-hint bad';
        }
    });
}

document.getElementById('status-apply').addEventListener('click', function () {
    applyStatus(statusInput.value.trim());
});

document.getElementById('status-clear').addEventListener('click', function () {
    applyStatus('');
});

statusInput.addEventListener('keydown', function (e) {
    if (e.key === 'Enter') applyStatus(statusInput.value.trim());
    e.stopPropagation();
});

function askConfirm(title, sub, yesLabel, fn) {
    confirmTitle.textContent = title;
    confirmSub.textContent = sub;
    document.getElementById('confirm-yes').textContent = yesLabel;
    confirmAction = fn;
    confirmEl.classList.remove('hidden');
}

document.getElementById('confirm-no').addEventListener('click', function () {
    confirmEl.classList.add('hidden');
    confirmAction = null;
});

document.getElementById('confirm-yes').addEventListener('click', function () {
    confirmEl.classList.add('hidden');
    if (confirmAction) confirmAction();
    confirmAction = null;
});

document.getElementById('keys-close').addEventListener('click', function () {
    keysEl.classList.add('hidden');
});

var suggestModal=document.getElementById('suggest-modal');
document.getElementById('suggest-btn').addEventListener('click', function () {
    if(cfg && cfg.suggest && cfg.suggest.ready===false){toast('건의함 준비 중입니다');return;}
    suggestModal.classList.remove('hidden');
    document.getElementById('suggest-input-title').focus();
});
document.getElementById('suggest-close').addEventListener('click',function(){suggestModal.classList.add('hidden');});
suggestModal.addEventListener('mousedown',function(e){if(e.target===suggestModal)suggestModal.classList.add('hidden');});
document.getElementById('suggest-submit').addEventListener('click',async function(){
    var btn=this;
    var payload={
      category:document.getElementById('suggest-category').value,
      title:document.getElementById('suggest-input-title').value.trim(),
      body:document.getElementById('suggest-input-body').value.trim()
    };
    if(payload.title.length<2){toast('제목을 2자 이상 입력해주세요');return;}
    if(payload.body.length<5){toast('내용을 5자 이상 입력해주세요');return;}
    btn.disabled=true;
    var r=await post('submitSuggestion',payload);
    btn.disabled=false;
    if(r&&r.ok){
      suggestModal.classList.add('hidden');
      document.getElementById('suggest-input-title').value='';
      document.getElementById('suggest-input-body').value='';
      toast('건의가 정상적으로 접수되었습니다');
    }else toast((r&&r.reason)||'건의 제출에 실패했습니다');
});

var settingsEl = document.getElementById('settings');

document.getElementById('settings-close').addEventListener('click', function () {
    settingsEl.classList.add('hidden');
});

var setBtns = settingsEl.querySelectorAll('[data-set]');
for (var s = 0; s < setBtns.length; s++) {
    (function (b) {
        b.addEventListener('click', function () {
            settingsEl.classList.add('hidden');

            post('openGtaSettings', { which: b.dataset.set });
        });
    })(setBtns[s]);
}

function openUrl(url, label) {
    if (!url) {
        toast(label + ' 주소가 설정되지 않았습니다');
        return;
    }
    try {
        if (typeof window.invokeNative === 'function') {
            window.invokeNative('openUrl', url);
            toast(label + '를 열었습니다');
            return;
        }
    } catch (err) {  }
    toast(label + ': ' + url);
}

function onSys(kind) {
    if (kind === 'keys') {
        keysEl.classList.remove('hidden');
    } else if (kind === 'settings') {
        settingsEl.classList.remove('hidden');
    } else if (kind === 'quit' || kind === 'disconnect') {
        askConfirm('서버에서 나갈까요?', '쿠키서버 접속을 종료합니다.', '나가기', function () {
            post('quitGame', {});
        });
    } else if (kind === 'discord') {
        openUrl((cfg && cfg.discordUrl) || '', '디스코드');
    } else if (kind === 'home') {
        if (cfg && cfg.homepage) openUrl(cfg.homepage, '홈페이지');
        else toast('홈페이지 준비 중입니다');
    }
}

var sysBtns = document.querySelectorAll('[data-sys]');
for (var i = 0; i < sysBtns.length; i++) {
    (function (b) {
        b.addEventListener('click', function () { onSys(b.dataset.sys); });
    })(sysBtns[i]);
}

document.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape') return;
    e.preventDefault();
    if (suggestModal && !suggestModal.classList.contains('hidden')) {
        suggestModal.classList.add('hidden');
        return;
    }
    if (!confirmEl.classList.contains('hidden')) {
        confirmEl.classList.add('hidden');
        confirmAction = null;
        return;
    }
    if (!settingsEl.classList.contains('hidden')) {
        settingsEl.classList.add('hidden');
        return;
    }
    if (!keysEl.classList.contains('hidden')) {
        keysEl.classList.add('hidden');
        return;
    }
    post('close', {});
});

window.addEventListener('message', function (e) {
    var d = e.data || {};

    if (d.action === 'open') {
        cfg = d.config || {};
        statusMax = cfg.statusMax || 20;
        statusMaxEl.textContent = String(statusMax);
        statusInput.maxLength = statusMax;
        statusBox.classList.toggle('hidden', cfg.statusOn === false);

        brandEl.textContent = cfg.brandEn || 'COOKIE KR';
        suggestTitle.textContent = (cfg.suggest && cfg.suggest.title) || '건의함';
        suggestDesc.textContent = (cfg.suggest && cfg.suggest.desc) || '';

        renderTabs(cfg.tabs);
        renderShortcuts(cfg.shortcuts);
        renderNews(cfg.news);
        renderNotice(cfg.notice);
        loadNotices();
        loadNews();
        document.getElementById('notice-detail').classList.add('hidden');
        document.getElementById('upd-detail').classList.add('hidden');

        statusHint.textContent = '';
        confirmEl.classList.add('hidden');
        keysEl.classList.add('hidden');
        settingsEl.classList.add('hidden');
        root.classList.remove('hidden');

    } else if (d.action === 'fill') {
        fill(d.data || {});

    } else if (d.action === 'fillFail') {
        fillFail();

    } else if (d.action === 'close') {
        root.classList.add('hidden');
    }
});

// COOKIE ESC SHARED EVENT HUB V14.0.0
