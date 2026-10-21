/* Cookie server inventory display preference only. Original React inventory remains intact. */
(() => {
  let compact = false;
  const attach = () => {
    const wrapper = document.querySelector('.inventory-wrapper');
    if (!wrapper) return;
    document.body.classList.toggle('cookie-inv-compact', compact);
    if (wrapper.querySelector('#cookie-inv-mode-toggle')) return;
    const button = document.createElement('button');
    button.type = 'button';
    button.id = 'cookie-inv-mode-toggle';
    button.textContent = compact ? '▦ 기본 보기' : '≡ 목록 보기';
    button.title = '쿠키서버 인벤토리 표시 방식 전환';
    button.addEventListener('click', (e) => {
      e.preventDefault();e.stopPropagation();
      compact = !compact;
      document.body.classList.toggle('cookie-inv-compact',compact);
      button.textContent = compact ? '▦ 기본 보기' : '≡ 목록 보기';
    });
    wrapper.appendChild(button);
  };
  document.addEventListener('DOMContentLoaded', () => {
    attach();
    const observer = new MutationObserver(() => attach());
    observer.observe(document.getElementById('root')||document.body,{childList:true,subtree:true});
  });
})();
