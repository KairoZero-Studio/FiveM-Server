

const DEBUG = false;

function log() {
    if (!DEBUG) return;

}

const progress = document.querySelector('.progress');
const bgm = document.getElementById('bgm');

if (bgm) {
    bgm.volume = 0.3;
    log('오디오 볼륨 0.3 설정');
}

function setProgress(fraction) {
    let pct = Math.round((fraction || 0) * 100);
    if (pct < 0) pct = 0;
    if (pct > 100) pct = 100;
    progress.style.width = pct + '%';
}

setProgress(0);

window.addEventListener('message', (e) => {
    const data = e.data || {};
    if (data.eventName === 'loadProgress') {
        setProgress(data.loadFraction);
        log('loadProgress', data.loadFraction);
    }
});

log('로드스크린 초기화 완료');

// Music controls; keeps loadProgress unaffected.
const musicToggle = document.getElementById('musicToggle');
const musicVolume = document.getElementById('musicVolume');
const volumeValue = document.getElementById('volumeValue');
if (bgm && musicToggle && musicVolume) {
  const refreshMusicUi = () => {
    musicToggle.textContent = bgm.paused ? '▶ 음악 재생' : '⏸ 음악 멈추기';
    volumeValue.textContent = Math.round(bgm.volume * 100) + '%';
  };
  musicToggle.addEventListener('click', () => {
    if (bgm.paused) bgm.play().catch(() => {}); else bgm.pause();
    refreshMusicUi();
  });
  musicVolume.addEventListener('input', () => {
    bgm.volume = Number(musicVolume.value) / 100;
    refreshMusicUi();
  });
  refreshMusicUi();
}

// Cookie loading media list; edit playlist.js to add new background images/tracks later.
(function () {
  const cfg = window.COOKIE_LOADING_MEDIA || {};
  const pictures = (Array.isArray(cfg.backgrounds) ? cfg.backgrounds : []).filter(Boolean);
  const tracks = (Array.isArray(cfg.tracks) ? cfg.tracks : []).filter(t => t && t.src);
  const bg = document.querySelector('.background');
  let imageIndex = 0, trackIndex = 0;
  if (bg && pictures.length) {
    bg.style.backgroundImage = `url("${pictures[0]}")`;
    if (pictures.length > 1) setInterval(() => {
      imageIndex = (imageIndex + 1) % pictures.length;
      bg.style.backgroundImage = `url("${pictures[imageIndex]}")`;
    }, Math.max(5000, Number(cfg.backgroundIntervalMs) || 12000));
  }
  if (!bgm || !tracks.length) return;
  const title = document.getElementById('cookieTrackTitle');
  const setTrack = i => {
    trackIndex = (i + tracks.length) % tracks.length;
    const shouldPlay = !bgm.paused;
    bgm.src = tracks[trackIndex].src;
    if (title) title.textContent = tracks[trackIndex].title || `트랙 ${trackIndex + 1}`;
    if (shouldPlay) bgm.play().catch(() => {});
  };
  document.getElementById('cookieTrackPrev')?.addEventListener('click', () => setTrack(trackIndex - 1));
  document.getElementById('cookieTrackNext')?.addEventListener('click', () => setTrack(trackIndex + 1));
  bgm.loop = tracks.length === 1;
  bgm.addEventListener('ended', () => { if (tracks.length > 1) setTrack(trackIndex + 1); });
  setTrack(0);
})();
