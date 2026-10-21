(() => {
  const $ = (id) => document.getElementById(id);
  const state = { open:false, items:[], cash:0, maxQty:20, query:'', buying:false };

  const fmt = (n) => Math.max(0, Number(n)||0).toLocaleString('ko-KR');
  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
  const post = (name, data={}) => fetch(`https://${GetParentResourceName()}/${name}`, {
    method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(data)
  }).then(r => r.json()).catch(() => ({ok:false,message:'요청을 처리하지 못했습니다.'}));

  function toast(message, bad=false) {
    const wrap = $('fshopToastWrap');
    if (!wrap) return;
    const el = document.createElement('div');
    el.className = `ck-fshop-toast${bad?' bad':''}`;
    el.textContent = message || '';
    wrap.appendChild(el);
    requestAnimationFrame(()=>el.classList.add('show'));
    setTimeout(()=>{ el.classList.remove('show'); setTimeout(()=>el.remove(),180); }, 2200);
  }

  function updateCash(v) {
    state.cash = Number(v)||0;
    const el = $('fshopCash');
    if (el) el.textContent = `${fmt(state.cash)}원`;
  }

  function itemIcon(code, label, imageName) {
    const raw = String(imageName || `${code}.png`);
    const src = /^(https?:|data:|nui:)/i.test(raw) ? raw : `https://cfx-nui-ox_inventory/web/images/${encodeURIComponent(raw)}`;
    return `<div class="ck-fshop-icon"><img src="${src}" alt="${esc(label)}" onerror="this.style.display='none';this.nextElementSibling.style.display='grid'"><span style="display:none">📦</span></div>`;
  }

  function filteredItems() {
    const q = state.query.trim().toLowerCase();
    if (!q) return state.items;
    return state.items.filter(it => String(it.label||'').toLowerCase().includes(q) || String(it.item_code||'').toLowerCase().includes(q));
  }

  function renderItems() {
    const grid = $('fshopGrid');
    if (!grid) return;
    const items = filteredItems();
    $('fshopCount').textContent = `${items.length}개 상품`;
    if (!items.length) {
      grid.innerHTML = `<div class="ck-fshop-empty"><b>판매 중인 상품이 없습니다.</b><span>팩션 인트라넷 관리에서 판매 품목과 가격을 등록해 주세요.</span></div>`;
      return;
    }
    grid.innerHTML = items.map((it, idx) => {
      const code = String(it.item_code||'');
      const label = String(it.label||code||'상품');
      const desc = String(it.description||'설명이 등록되지 않은 상품입니다.');
      const price = Math.max(0, Number(it.price)||0);
      return `<article class="ck-fshop-card" data-fshop-index="${idx}" data-code="${esc(code)}">
        <div class="ck-fshop-card-main">
          ${itemIcon(code,label,it.image)}
          <div class="ck-fshop-card-info">
            <div class="ck-fshop-card-name">${esc(label)}</div>
            <div class="ck-fshop-card-code">${esc(code)}</div>
          </div>
          <div class="ck-fshop-price">${price===0?'무료':fmt(price)+'원'}</div>
        </div>
        <p class="ck-fshop-desc">${esc(desc)}</p>
        <div class="ck-fshop-buyrow">
          <div class="ck-fshop-stepper">
            <button type="button" data-step="-1">−</button>
            <input type="number" min="1" max="${state.maxQty}" value="1" aria-label="구매 수량">
            <button type="button" data-step="1">＋</button>
          </div>
          <div class="ck-fshop-total">총 <b>${price===0?'0':fmt(price)}</b>원</div>
          <button type="button" class="ck-fshop-buy">구매</button>
        </div>
      </article>`;
    }).join('');

    grid.querySelectorAll('.ck-fshop-card').forEach(card => {
      const input = card.querySelector('input');
      const item = items[Number(card.dataset.fshopIndex)];
      const price = Math.max(0, Number(item?.price)||0);
      const total = card.querySelector('.ck-fshop-total b');
      const clamp = () => {
        let q = Math.floor(Number(input.value)||1);
        q = Math.max(1, Math.min(state.maxQty, q));
        input.value = q;
        total.textContent = fmt(price*q);
        return q;
      };
      input.addEventListener('input', clamp);
      card.querySelectorAll('[data-step]').forEach(btn => btn.addEventListener('click', () => {
        input.value = (Number(input.value)||1) + Number(btn.dataset.step||0);
        clamp();
      }));
      card.querySelector('.ck-fshop-buy').addEventListener('click', async (e) => {
        if (state.buying) return;
        const qty = clamp();
        state.buying = true;
        const btn = e.currentTarget;
        const old = btn.textContent;
        btn.disabled = true; btn.textContent = '구매 중...';
        const r = await post('factionShopPurchase', {itemCode:String(item.item_code||''),quantity:qty});
        if (typeof r.cash !== 'undefined') updateCash(r.cash);
        toast(r.message || (r.ok?'구매했습니다.':'구매에 실패했습니다.'), !r.ok);
        state.buying = false;
        btn.disabled = false; btn.textContent = old;
      });
    });
  }

  function openShop(d) {
    state.open = true;
    state.items = Array.isArray(d.items) ? d.items : [];
    state.maxQty = Math.max(1, Number(d.maxQuantity)||20);
    state.query = '';
    $('fshopSearch').value = '';
    $('fshopFaction').textContent = `${d.factionEmoji||''} ${d.factionName||'팩션 상점'}`.trim();
    $('fshopNpc').textContent = d.npcLabel || '판매 담당자';
    const color = /^#[0-9a-fA-F]{6}$/.test(String(d.factionColor||'')) ? d.factionColor : '#ffb800';
    $('factionShopOverlay').style.setProperty('--fshop-accent', color);
    updateCash(d.cash);
    renderItems();
    $('factionShopOverlay').classList.remove('hidden');
  }

  function closeVisual() {
    state.open = false;
    state.buying = false;
    $('factionShopOverlay')?.classList.add('hidden');
  }

  window.addEventListener('message', (e) => {
    const d = e.data || {};
    if (d.action === 'factionShopOpen') openShop(d);
    else if (d.action === 'factionShopClose') closeVisual();
    else if (d.action === 'factionNpcPrompt') {
      const p = $('factionNpcPrompt');
      if (!p) return;
      if (!d.show || state.open) { p.classList.add('hidden'); return; }
      const color = /^#[0-9a-fA-F]{6}$/.test(String(d.factionColor||'')) ? d.factionColor : '#ffb800';
      p.style.setProperty('--fshop-accent', color);
      $('fnpFaction').textContent = `${d.factionEmoji||''} ${d.factionName||'팩션'}`.trim();
      $('fnpLabel').textContent = d.label || '판매 담당자';
      p.classList.remove('hidden');
    }
  });

  $('fshopClose')?.addEventListener('click', async () => { closeVisual(); await post('factionShopClose'); });
  $('fshopSearch')?.addEventListener('input', (e) => { state.query = e.target.value || ''; renderItems(); });
  window.addEventListener('keydown', async (e) => {
    if (e.key !== 'Escape' || !state.open) return;
    e.preventDefault(); e.stopPropagation();
    closeVisual(); await post('factionShopClose');
  }, true);
})();
