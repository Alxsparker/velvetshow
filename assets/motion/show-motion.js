/* Pages Velvet Show — onglets Music / Lights de la télécommande iPhone (en plus de visualizer-motion.js).
   Décoratif : sans ce fichier, la capture « Music » reste affichée. Rien ne change tout seul en mode « mouvement réduit ». */
(function () {
  'use strict';
  document.documentElement.classList.add('mo-js');
  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var canObserve = 'IntersectionObserver' in window;

  // Les onglets changent seuls quand le cadre est visible, et s'arrêtent dès qu'on clique.
  document.querySelectorAll('[data-switch]').forEach(function (box) {
    var imgs = box.querySelectorAll('.ps'), tabs = box.querySelectorAll('.ps-tabs button'), label = box.querySelector('[data-switch-label]');
    var labels = []; try { labels = JSON.parse(box.getAttribute('data-labels') || '[]'); } catch (e) {}
    var time = 4500, current = 0, timer = null, visible = false, stopped = reduce;
    box.style.setProperty('--ps-time', time + 'ms');
    function show(i, auto) {
      current = i;
      imgs.forEach(function (im, k) { im.classList.toggle('on', k === i); });
      tabs.forEach(function (t, k) { t.classList.toggle('on', k === i); t.classList.toggle('auto', k === i && !!auto); t.setAttribute('aria-selected', k === i ? 'true' : 'false'); });
      if (label && labels[i]) label.textContent = labels[i];
    }
    function schedule() {
      clearTimeout(timer);
      if (stopped || !visible || document.hidden) return;
      show(current, true);
      timer = setTimeout(function () { show((current + 1) % imgs.length, true); schedule(); }, time);
    }
    tabs.forEach(function (t, k) {
      t.addEventListener('click', function () { stopped = true; clearTimeout(timer); show(k, false); });
    });
    if (!reduce && canObserve) {
      new IntersectionObserver(function (entries) { visible = entries[0].isIntersecting; schedule(); }, { threshold: 0.15 }).observe(box);
      document.addEventListener('visibilitychange', schedule);
    }
    show(0, false);
  });
})();
