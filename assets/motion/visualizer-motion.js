/* Velvet Visualizer — mouvement de la page produit. Sans ce fichier, la page reste complète. */
(function () {
  'use strict';
  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var hero = document.querySelector('.hero');

  // 1) Faisceaux de scène derrière le titre
  if (hero) {
    var beams = document.createElement('div');
    beams.className = 'mo-beams';
    beams.setAttribute('aria-hidden', 'true');
    beams.innerHTML = '<span class="mo-glow"></span><span class="mo-beam"></span><span class="mo-beam"></span><span class="mo-beam"></span><span class="mo-beam"></span>';
    hero.insertBefore(beams, hero.firstChild);

    // Entrée en cascade du contenu du hero
    if (!reduce) {
      var kids = hero.querySelectorAll('.hero__inner > *');
      Array.prototype.forEach.call(kids, function (el, i) {
        el.classList.add('mo-hero-in');
        el.style.animationDelay = (0.08 + i * 0.09) + 's';
      });
    }

    // Pause des faisceaux quand le hero n'est plus visible (économie de batterie)
    if ('IntersectionObserver' in window && !reduce) {
      new IntersectionObserver(function (entries) {
        beams.classList.toggle('mo-paused', !entries[0].isIntersecting);
      }, { threshold: 0 }).observe(hero);
      document.addEventListener('visibilitychange', function () {
        beams.classList.toggle('mo-paused', document.hidden);
      });
    }

    // Léger décalage des faisceaux avec la souris (écrans à pointeur seulement)
    if (!reduce && window.matchMedia('(hover: hover)').matches) {
      var raf = 0, tx = 0, ty = 0;
      hero.addEventListener('mousemove', function (e) {
        var r = hero.getBoundingClientRect();
        tx = ((e.clientX - r.left) / r.width - 0.5) * 36;
        ty = ((e.clientY - r.top) / r.height - 0.5) * 14;
        if (!raf) raf = requestAnimationFrame(function () {
          raf = 0;
          beams.style.setProperty('--mx', tx.toFixed(1) + 'px');
          beams.style.setProperty('--my', ty.toFixed(1) + 'px');
        });
      }, { passive: true });
      hero.addEventListener('mouseleave', function () {
        beams.style.setProperty('--mx', '0px');
        beams.style.setProperty('--my', '0px');
      });
    }
  }

  // 2) Barre de progression de lecture
  if (!reduce) {
    var bar = document.createElement('div');
    bar.className = 'mo-progress';
    bar.setAttribute('aria-hidden', 'true');
    document.body.appendChild(bar);
    var ticking = false;
    function update() {
      ticking = false;
      var h = document.documentElement.scrollHeight - window.innerHeight;
      bar.style.transform = 'scaleX(' + (h > 0 ? Math.min(1, window.scrollY / h) : 0).toFixed(4) + ')';
    }
    window.addEventListener('scroll', function () {
      if (!ticking) { ticking = true; requestAnimationFrame(update); }
    }, { passive: true });
    update();
  }

  // 3) Impulsion de signal : numérote les étapes de la chaîne
  Array.prototype.forEach.call(document.querySelectorAll('.prow'), function (row) {
    var i = 0;
    Array.prototype.forEach.call(row.querySelectorAll('.pc'), function (pc) {
      pc.style.setProperty('--i', String(i++));
    });
  });

  // 4) Inclinaison douce des captures vers la souris
  if (!reduce && window.matchMedia('(hover: hover)').matches) {
    Array.prototype.forEach.call(document.querySelectorAll('.frame'), function (f) {
      f.addEventListener('mousemove', function (e) {
        var r = f.getBoundingClientRect();
        var x = (e.clientX - r.left) / r.width - 0.5;
        var y = (e.clientY - r.top) / r.height - 0.5;
        f.classList.add('mo-tilting');
        f.style.transform = 'perspective(900px) rotateX(' + (-y * 4).toFixed(2) + 'deg) rotateY(' + (x * 5).toFixed(2) + 'deg) translateY(-4px) scale(1.015)';
      }, { passive: true });
      f.addEventListener('mouseleave', function () {
        f.classList.remove('mo-tilting');
        f.style.transform = '';
      });
    });
  }
})();
