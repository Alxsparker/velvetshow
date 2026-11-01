/* Guide « La lumière de scène » — apparition au défilement, barre de progression, schémas qui s'animent.
   Décoratif : sans JavaScript ou en mode « mouvement réduit », tout reste affiché, immobile. */
(function () {
  'use strict';
  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (reduce || !('IntersectionObserver' in window)) return;
  var root = document.documentElement;
  root.classList.add('mo-js');

  // Barre de progression de lecture
  var bar = document.createElement('div');
  bar.className = 'mo-progress'; bar.setAttribute('aria-hidden', 'true');
  document.body.appendChild(bar);
  var ticking = false;
  function update() {
    ticking = false;
    var h = root.scrollHeight - window.innerHeight;
    bar.style.transform = 'scaleX(' + (h > 0 ? Math.min(1, window.scrollY / h) : 0).toFixed(4) + ')';
  }
  window.addEventListener('scroll', function () { if (!ticking) { ticking = true; requestAnimationFrame(update); } }, { passive: true });
  update();

  // Éléments qui apparaissent quand on arrive dessus
  var sel = '.lbl,.sec-title,.sec-sub,.step,.term,.box,.cause,.skeleton,.pipeline,.fig,.olist li,.pager,.need,.story-note';
  var list = document.querySelectorAll('.hero ~ section ' + sel.split(',').join(',.hero ~ section '));
  var seen = new Set();
  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      var el = e.target;
      if (e.isIntersecting) { el.classList.add('on', 'vis'); if (!el.classList.contains('fig')) io.unobserve(el); }
      else if (el.classList.contains('fig')) el.classList.remove('vis');
    });
  }, { threshold: 0.12, rootMargin: '0px 0px -6% 0px' });
  list.forEach(function (el) {
    if (seen.has(el)) return; seen.add(el);
    el.classList.add('rv');
    var sibs = el.parentNode ? Array.prototype.indexOf.call(el.parentNode.children, el) : 0;
    el.style.transitionDelay = Math.min(sibs, 6) * 70 + 'ms';
    if (el.classList.contains('fig') && !el.classList.contains('story')) {
      var k = 0;
      Array.prototype.forEach.call(el.querySelectorAll('svg>*'), function (c) {
        if (/^(defs|title|desc)$/i.test(c.tagName)) return;
        c.style.transitionDelay = (150 + Math.min(k++, 14) * 55) + 'ms';
      });
    }
    io.observe(el);
  });
})();
