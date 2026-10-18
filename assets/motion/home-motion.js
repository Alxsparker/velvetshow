/* Accueil velvetshow.app — barre de progression, et pause de l'animation de scène quand elle n'est pas à l'écran. */
(function () {
  'use strict';
  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  if (!reduce) {
    var bar = document.createElement('div');
    bar.className = 'mo-progress';
    bar.setAttribute('aria-hidden', 'true');
    document.body.appendChild(bar);
    var ticking = false;
    var update = function () {
      ticking = false;
      var h = document.documentElement.scrollHeight - window.innerHeight;
      bar.style.transform = 'scaleX(' + (h > 0 ? Math.min(1, window.scrollY / h) : 0).toFixed(4) + ')';
    };
    window.addEventListener('scroll', function () {
      if (!ticking) { ticking = true; requestAnimationFrame(update); }
    }, { passive: true });
    update();
  }

  // La démo du Visualizer ne tourne que lorsqu'elle est visible (et jamais en mode « mouvement réduit »).
  var demo = document.querySelector('video.mo-demo');
  if (demo) {
    if (reduce || !('IntersectionObserver' in window)) {
      demo.controls = true;
    } else {
      new IntersectionObserver(function (entries) {
        var on = entries[0].isIntersecting && !document.hidden;
        if (on) { var p = demo.play(); if (p && p.catch) p.catch(function () {}); } else { demo.pause(); }
      }, { threshold: 0.25 }).observe(demo);
      document.addEventListener('visibilitychange', function () { if (document.hidden) demo.pause(); });
    }
  }

  // Lueur qui suit le pointeur sur les cartes produits.
  if (!reduce && window.matchMedia && window.matchMedia('(hover: hover)').matches) {
    document.querySelectorAll('.card').forEach(function (card) {
      card.addEventListener('pointermove', function (e) {
        var r = card.getBoundingClientRect();
        card.style.setProperty('--mx', (e.clientX - r.left) + 'px');
        card.style.setProperty('--my', (e.clientY - r.top) + 'px');
      }, { passive: true });
    });
  }
})();
