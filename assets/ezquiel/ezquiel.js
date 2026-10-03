// Pages EzQuiel : apparition au défilement et légère inclinaison des écrans.
(function () {
  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var items = document.querySelectorAll('.ez-reveal');
  if (reduce || !('IntersectionObserver' in window)) {
    items.forEach(function (el) { el.classList.add('is-in'); });
    return;
  }
  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (e.isIntersecting) { e.target.classList.add('is-in'); io.unobserve(e.target); }
    });
  }, { threshold: 0.15, rootMargin: '0px 0px -40px 0px' });
  items.forEach(function (el) { io.observe(el); });

  var phones = document.querySelectorAll('.feature .phone');
  var ticking = false;
  function tilt() {
    var vh = window.innerHeight;
    phones.forEach(function (p, i) {
      var r = p.getBoundingClientRect();
      var t = ((r.top + r.height / 2) - vh / 2) / vh; // -1 … 1 autour du centre de l'écran
      var dir = i % 2 ? -1 : 1;
      p.style.transform = 'perspective(900px) rotateY(' + (dir * t * 10).toFixed(2) + 'deg) translateY(' + (t * 18).toFixed(1) + 'px)';
    });
    ticking = false;
  }
  window.addEventListener('scroll', function () {
    if (!ticking) { ticking = true; requestAnimationFrame(tilt); }
  }, { passive: true });
  tilt();
})();
