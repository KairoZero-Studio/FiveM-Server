

var BANNER = {
  enter: { title: '안전지대에 진입했습니다', hold: 3500 },
  exit: { title: '안전지대를 벗어났습니다', hold: 2000 },
};

var hideTimer = null;

function showBanner(kind) {
  var spec = BANNER[kind] || BANNER.enter;
  var el = document.getElementById('banner');

  document.getElementById('szTitle').textContent = spec.title;
  el.classList.toggle('exit', kind === 'exit');
  el.classList.add('show');

  if (hideTimer) clearTimeout(hideTimer);
  hideTimer = setTimeout(function () {
    el.classList.remove('show');
    hideTimer = null;
  }, spec.hold);
}

function setGarageBadge(d) {
  var el = document.getElementById('ckGarageBadge');
  if (!el) return;
  if (!d.show) { el.classList.add('hidden'); return; }
  var t = document.getElementById('ckGarageBadgeText');
  if (t) t.textContent = d.text || '차고 열기';
  el.style.left = (d.x * 100) + 'vw';
  el.style.top = (d.y * 100) + 'vh';
  el.classList.remove('hidden');
}

function post(path, body) {
  return fetch('https://cookie_safezone/' + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body || {}),
  }).catch(function () {});
}

function escapeHtml(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function closeGarageMenu() {
  var el = document.getElementById('ckGMenu');
  if (el) el.classList.add('hidden');
}

function showGarageMenu(d) {
  var el = document.getElementById('ckGMenu');
  var list = document.getElementById('ckGMenuList');
  if (!el || !list) return;

  document.getElementById('ckGMenuTitle').textContent = d.title || '차고';

  var opts = d.options || [];
  var action = d.actionLabel;

  list.innerHTML = '';
  if (!opts.length) {
    list.innerHTML = '<div class="ck-gm-empty">현재 차고에 보관된 차량이 없습니다</div>';
    el.classList.remove('hidden');
    return;
  }

  function pickOf(i) {
    return function () {
      var o = opts[i] || {};
      if (!o.submenu) closeGarageMenu();
      post('garagePick', { index: i + 1 });
    };
  }

  function makeCard(o, i, no) {
    var card = document.createElement('div');
    card.className = 'ck-gm-card' + (o.locked ? ' locked' : '');

    var btn = o.locked
      ? '<button class="ck-gm-take locked" disabled>출고 불가</button>'
      : '<button class="ck-gm-take">' + escapeHtml(action) + '</button>';

    card.innerHTML =
      '<span class="ck-gm-no">' + no + '</span>' +
      '<div class="ck-gm-img">' +
        (o.image ? '<img src="' + o.image + '" alt="" onerror="this.parentNode.classList.add(\'noimg\');this.remove();">' : '') +
      '</div>' +
      '<div class="ck-gm-cbody">' +
        '<p class="ck-gm-cname">' + escapeHtml(o.title) + '</p>' +
        btn +
      '</div>';

    if (!o.image) card.querySelector('.ck-gm-img').classList.add('noimg');
    if (!o.locked) card.querySelector('.ck-gm-take').addEventListener('click', pickOf(i));
    return card;
  }

  if (action) {
    var ranks = d.ranks;

    if (!ranks || !ranks.length) {

      opts.forEach(function (o, i) { list.appendChild(makeCard(o, i, i + 1)); });
      el.classList.remove('hidden');
      return;
    }

    ranks.forEach(function (r) {
      var sec = document.createElement('div');
      sec.className = 'ck-gm-sec';

      var head = document.createElement('div');
      head.className = 'ck-gm-sechead';
      head.textContent = (r.name || '-') + ' 전용';
      sec.appendChild(head);

      var track = document.createElement('div');
      track.className = 'ck-gm-track';

      var no = 0;
      opts.forEach(function (o, i) {
        if ((o.grade || 0) !== (r.grade || 0)) return;
        no += 1;
        track.appendChild(makeCard(o, i, no));
      });
      if (!no) track.classList.add('empty');

      var body = document.createElement('div');
      body.className = 'ck-gm-secbody';
      body.appendChild(track);

      var more = document.createElement('button');
      more.className = 'ck-gm-more hidden';
      more.textContent = '더보기';
      more.addEventListener('click', function () {
        track.scrollBy({ left: track.clientWidth, behavior: 'smooth' });
      });
      body.appendChild(more);

      var sync = function () {
        var over = track.scrollWidth - track.clientWidth > 4;
        more.classList.toggle('hidden', !over);
        if (over && track.scrollLeft + track.clientWidth >= track.scrollWidth - 4) {
          more.textContent = '처음으로';
          more.onclick = function () { track.scrollTo({ left: 0, behavior: 'smooth' }); };
        } else {
          more.textContent = '더보기';
          more.onclick = function () { track.scrollBy({ left: track.clientWidth, behavior: 'smooth' }); };
        }
      };
      track.addEventListener('scroll', sync);
      requestAnimationFrame(sync);

      sec.appendChild(body);
      list.appendChild(sec);
    });

    el.classList.remove('hidden');
    return;
  }

  opts.forEach(function (o, i) {
    var row = document.createElement('button');
    row.className = 'ck-gm-row';
    row.innerHTML =
      '<span class="ck-gm-info">' +
        '<span class="ck-gm-name">' + escapeHtml(o.title) + '</span>' +
        (o.description ? '<span class="ck-gm-desc">' + escapeHtml(o.description) + '</span>' : '') +
      '</span>' +
      '<span class="ck-gm-arrow">›</span>';
    row.addEventListener('click', pickOf(i));
    list.appendChild(row);
  });

  el.classList.remove('hidden');
}


function money(n) {
  n = Number(n || 0) || 0;
  return n.toLocaleString('ko-KR');
}

function escapeAttr(s) {
  return escapeHtml(s).replace(/'/g, '&#39;');
}

function storeImageUrl(name) {
  if (!name) return '';
  if (/^https?:\/\//i.test(name) || name.indexOf('nui://') === 0 || name.indexOf('data:') === 0) return name;
  return 'https://cfx-nui-ox_inventory/web/images/' + name;
}

function closeStore() {
  var el = document.getElementById('ckStore');
  if (el) el.classList.add('hidden');
}

function bindStoreCard(card, item, shopType) {
  var input = card.querySelector('.ck-store-qty-input');
  var minus = card.querySelector('.ck-store-qty-btn.minus');
  var plus = card.querySelector('.ck-store-qty-btn.plus');
  var buy = card.querySelector('.ck-store-buy');

  function clamp(v) {
    v = Number(v || 1) || 1;
    if (v < 1) v = 1;
    if (v > 20) v = 20;
    input.value = String(v);
    return v;
  }

  if (minus) minus.addEventListener('click', function () { clamp((Number(input.value) || 1) - 1); });
  if (plus) plus.addEventListener('click', function () { clamp((Number(input.value) || 1) + 1); });
  if (input) input.addEventListener('change', function () { clamp(input.value); });
  if (buy) buy.addEventListener('click', function () {
    var payload = { quantity: clamp(input && input.value) };
    if (shopType === 'jobshop') payload.itemName = item.itemName || item.item_name || '';
    else payload.rowId = Number(item.rowId || item.id || 0) || 0;
    post('storeBuy', payload);
  });
}

function showStore(d) {
  var el = document.getElementById('ckStore');
  var grid = document.getElementById('ckStoreGrid');
  if (!el || !grid) return;

  document.getElementById('ckStoreKicker').textContent = d.kicker || 'COOKIE MART';
  document.getElementById('ckStoreTitle').textContent = d.title || '상점';
  document.getElementById('ckStoreSub').textContent = d.subtitle || '';

  var items = Array.isArray(d.items) ? d.items : [];
  grid.innerHTML = '';

  if (!items.length) {
    grid.innerHTML = '<div class="ck-gm-empty">표시할 상품이 없습니다.</div>';
    el.classList.remove('hidden');
    return;
  }

  items.forEach(function (item) {
    var card = document.createElement('div');
    card.className = 'ck-store-card';
    var img = storeImageUrl(item.image || ((item.itemName || item.item_name || 'unknown') + '.png'));
    card.innerHTML =
      '<div class="ck-store-img' + (img ? '' : ' noimg') + '">' +
        (img ? '<img src="' + escapeAttr(img) + '" alt="" onerror="this.parentNode.classList.add(\'noimg\');this.remove();">' : '') +
      '</div>' +
      '<div class="ck-store-body">' +
        '<div class="ck-store-name">' + escapeHtml(item.label || item.itemName || item.item_name || '상품') + '</div>' +
        '<div class="ck-store-code">' + escapeHtml(item.itemName || item.item_name || '') + '</div>' +
        '<div class="ck-store-price">₩ ' + money(item.price || 0) + '</div>' +
      '</div>' +
      '<div class="ck-store-foot">' +
        '<div class="ck-store-qty">' +
          '<button type="button" class="ck-store-qty-btn minus">－</button>' +
          '<input class="ck-store-qty-input" type="number" min="1" max="20" value="1">' +
          '<button type="button" class="ck-store-qty-btn plus">＋</button>' +
        '</div>' +
        '<button type="button" class="ck-store-buy">구매</button>' +
      '</div>';
    grid.appendChild(card);
    bindStoreCard(card, item, d.shopType || 'convenience');
  });

  el.classList.remove('hidden');
}

document.addEventListener('keydown', function (e) {
  if (e.key !== 'Escape') return;

  var store = document.getElementById('ckStore');
  if (store && !store.classList.contains('hidden')) {
    closeStore();
    post('storeClose', {});
    return;
  }

  var el = document.getElementById('ckGMenu');
  if (!el || el.classList.contains('hidden')) return;
  closeGarageMenu();
  post('garageClose', {});
});

window.addEventListener('message', function (e) {
  var d = e.data;
  if (!d) return;
  if (d.action === 'banner') showBanner(d.kind);
  else if (d.action === 'garageBadge') setGarageBadge(d);
  else if (d.action === 'garageMenu') showGarageMenu(d);
  else if (d.action === 'garageMenuLoading') {
    var gm = document.getElementById('ckGMenu');
    var list = document.getElementById('ckGMenuList');
    var title = document.getElementById('ckGMenuTitle');
    if (title) title.textContent = d.title || '차고';
    if (list) list.innerHTML = '<div class="ck-gm-empty">' + escapeHtml(d.message || '불러오는 중...') + '</div>';
    if (gm) gm.classList.remove('hidden');
  }
  else if (d.action === 'garageMenuClose') closeGarageMenu();
  else if (d.action === 'storeOpen') showStore(d);
  else if (d.action === 'storeClose') closeStore();
});

(function () {
  var btn = document.getElementById('ckGMenuClose');
  if (btn) {
    btn.addEventListener('click', function () {
      closeGarageMenu();
      post('garageClose', {});
    });
  }

  var storeBtn = document.getElementById('ckStoreCloseBtn');
  if (storeBtn) {
    storeBtn.addEventListener('click', function () {
      closeStore();
      post('storeClose', {});
    });
  }
})();
