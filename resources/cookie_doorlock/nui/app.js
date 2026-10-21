(() => {
  const root = document.getElementById('doorIndicators');
  if (!root) return;

  const escapeHtml = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[c]));

  window.addEventListener('message', (event) => {
    const data = event.data || {};
    if (data.action !== 'doorIndicators') return;
    const items = Array.isArray(data.items) ? data.items : [];
    root.innerHTML = items.map((item) => {
      const x = Math.max(0, Math.min(1, Number(item.x) || 0)) * 100;
      const y = Math.max(0, Math.min(1, Number(item.y) || 0)) * 100;
      return `<div class="ck-lock-indicator" style="left:${x}%;top:${y}%">
        <span class="ck-lock-icon">🔒</span>
        <span>잠김</span>
        <span class="ck-lock-label">${escapeHtml(item.label || '')}</span>
      </div>`;
    }).join('');
  });
})();
