/* Guide « La lumière de scène » — installation construite brique par brique : onglets, briques, légende, boutons.
   Se met en pause quand elle sort de l'écran. Sans JavaScript, les trois installations restent affichées en entier,
   avec leur liste de briques. Contrôle au clavier : Tab, Entrée/Espace, flèches gauche/droite sur les onglets. */
(function () {
  'use strict';
  var fig = document.querySelector('[data-story]');
  if (!fig) return;
  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var setups = fig.querySelectorAll('.setup'), tabs = fig.querySelectorAll('[data-tab]');
  var box = fig.querySelector('.demo-caption'), ctrl = fig.querySelector('.story-ctrl'), dotsBox = fig.querySelector('.story-dots');
  var bPrev = fig.querySelector('[data-prev]'), bNext = fig.querySelector('[data-next]'), bPlay = fig.querySelector('[data-play]'), count = fig.querySelector('.story-count');
  var word = fig.getAttribute('data-word');
  var s = 0, k = 0, playing = !reduce, visible = false, timer = null, DELAY = 6500, dots = [];
  document.documentElement.classList.add('mo-story');
  fig.querySelector('.story-tabs').hidden = false; box.hidden = false; var shared = fig.querySelector('.story-note.shared'); ctrl.hidden = false; dotsBox.hidden = false;

  function caps() { return setups[s].querySelectorAll('.story-caps li'); }
  function buildDots() {
    dotsBox.innerHTML = ''; dots = [];
    caps().forEach(function (li, i) {
      var b = document.createElement('button'); b.type = 'button'; b.setAttribute('aria-label', word + ' ' + (i + 1));
      b.addEventListener('click', function () { k = i; render(); schedule(); });
      dotsBox.appendChild(b); dots.push(b);
    });
  }
  function render(swap) {
    var n = caps().length;
    setups.forEach(function (el, i) { el.classList.toggle('cur', i === s); });
    tabs.forEach(function (t, i) { var on = i === s; t.setAttribute('aria-selected', on ? 'true' : 'false'); t.tabIndex = on ? 0 : -1; });
    var svg = setups[s].querySelector('svg');
    svg.querySelectorAll('[data-b]').forEach(function (el) {
      var b = +el.getAttribute('data-b');
      el.classList.toggle('on', k >= b); el.classList.toggle('now', k === b && k > 0);
    });
    svg.querySelectorAll('.dev').forEach(function (el) { el.classList.toggle('now', k === +el.getAttribute('data-b') && k > 0); });
    box.innerHTML = caps()[k].innerHTML;
    var nt = setups[s].getAttribute('data-note') || ''; shared.hidden = !nt; shared.textContent = nt;
    if (swap && !reduce) { box.classList.remove('swap'); void box.offsetWidth; box.classList.add('swap'); }
    count.textContent = word + ' ' + (k + 1) + ' / ' + n;
    dots.forEach(function (d, i) { d.classList.toggle('on', i === k); d.setAttribute('aria-current', i === k ? 'step' : 'false'); });
    bPrev.disabled = k === 0;
    bNext.textContent = bNext.getAttribute(k === n - 1 ? 'data-l-again' : 'data-l-next');
    bPlay.textContent = playing ? bPlay.getAttribute('data-l-pause') : bPlay.getAttribute('data-l-play');
    bPlay.setAttribute('aria-pressed', playing ? 'true' : 'false');
    fig.classList.toggle('paused', !visible || document.hidden);
  }
  function schedule() {
    clearTimeout(timer);
    if (!playing || !visible || document.hidden) return;
    timer = setTimeout(function () { k = (k + 1) % caps().length; render(true); schedule(); }, DELAY);
  }
  function selectTab(i) { s = i; k = 0; buildDots(); render(true); schedule(); }
  tabs.forEach(function (t, i) {
    t.addEventListener('click', function () { selectTab(i); });
    t.addEventListener('keydown', function (e) {
      var j = e.key === 'ArrowRight' ? (i + 1) % tabs.length : e.key === 'ArrowLeft' ? (i + tabs.length - 1) % tabs.length : -1;
      if (j > -1) { e.preventDefault(); tabs[j].focus(); selectTab(j); }
    });
  });
  bPrev.addEventListener('click', function () { if (k > 0) { k--; render(true); schedule(); } });
  bNext.addEventListener('click', function () { k = (k + 1) % caps().length; render(true); schedule(); });
  bPlay.addEventListener('click', function () { playing = !playing; render(); schedule(); });
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(function (en) { visible = en[0].isIntersecting; render(); schedule(); }, { threshold: 0.3 }).observe(fig);
  } else { visible = true; }
  document.addEventListener('visibilitychange', function () { render(); schedule(); });
  buildDots(); render();
})();
