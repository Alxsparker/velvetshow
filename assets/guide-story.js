/* Guide « La lumière de scène » — animation « qui parle à qui » : étapes, légende, boutons.
   Se met en pause quand elle sort de l'écran. Sans JavaScript, la liste des six étapes reste affichée sous le dessin. */
(function () {
  'use strict';
  var fig = document.querySelector('[data-story]');
  if (!fig) return;
  var svg = fig.querySelector('.story-svg');
  var caps = fig.querySelectorAll('.story-caps li');
  var box = fig.querySelector('.demo-caption');
  var btnPrev = fig.querySelector('[data-prev]'), btnNext = fig.querySelector('[data-next]'), btnPlay = fig.querySelector('[data-play]');
  var count = fig.querySelector('.story-count'), dotsBox = fig.querySelector('.story-dots');
  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var N = caps.length, step = 0, playing = !reduce, visible = false, timer = null, DELAY = 6500;
  var labelPlay = btnPlay.getAttribute('data-l-play'), labelPause = btnPlay.getAttribute('data-l-pause'), stepWord = fig.getAttribute('data-step-word');
  document.documentElement.classList.add('mo-story');
  fig.querySelectorAll('[hidden]').forEach(function (e) { e.hidden = false; });

  var dots = [];
  for (var i = 0; i < N; i++) (function (i) {
    var b = document.createElement('button');
    b.type = 'button'; b.setAttribute('aria-label', stepWord + ' ' + (i + 1));
    b.addEventListener('click', function () { userGo(i); });
    dotsBox.appendChild(b); dots.push(b);
  })(i);

  function nowList(el) { return (el.getAttribute('data-now') || '').split(' '); }
  function render(first) {
    svg.setAttribute('data-step', step);
    svg.querySelectorAll('[data-a]').forEach(function (el) {
      var a = +el.getAttribute('data-a');
      el.classList.toggle('on', step >= a);
      el.classList.toggle('now', step === a);
    });
    svg.querySelectorAll('.dev').forEach(function (el) { el.classList.toggle('now', nowList(el).indexOf(String(step)) > -1); });
    svg.querySelectorAll('.lamp').forEach(function (el) { el.classList.toggle('on', step >= 4); });
    box.innerHTML = caps[step].innerHTML;
    if (!first && !reduce) { box.classList.remove('swap'); void box.offsetWidth; box.classList.add('swap'); }
    count.textContent = stepWord + ' ' + (step + 1) + ' / ' + N;
    dots.forEach(function (d, k) { d.classList.toggle('on', k === step); d.setAttribute('aria-current', k === step ? 'step' : 'false'); });
    btnPrev.disabled = step === 0;
    btnNext.textContent = btnNext.getAttribute(step === N - 1 ? 'data-l-again' : 'data-l-next');
    btnPlay.textContent = playing ? labelPause : labelPlay;
    btnPlay.setAttribute('aria-pressed', playing ? 'true' : 'false');
    fig.classList.toggle('paused', !visible || document.hidden);
  }
  function schedule() {
    clearTimeout(timer);
    if (!playing || !visible || document.hidden) return;
    timer = setTimeout(function () { step = (step + 1) % N; render(); schedule(); }, DELAY);
  }
  function userGo(i) { step = i; render(); schedule(); }
  btnPrev.addEventListener('click', function () { if (step > 0) userGo(step - 1); });
  btnNext.addEventListener('click', function () { userGo((step + 1) % N); });
  btnPlay.addEventListener('click', function () { playing = !playing; render(); schedule(); });

  if ('IntersectionObserver' in window) {
    new IntersectionObserver(function (en) { visible = en[0].isIntersecting; render(); schedule(); }, { threshold: 0.3 }).observe(fig);
  } else { visible = true; }
  document.addEventListener('visibilitychange', function () { render(); schedule(); });
  render(true);
})();
