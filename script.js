// Velvet Show landing page — small interaction layer.
// No frameworks, no analytics, no dependencies.

// ============================================================
// SINGLE SOURCE OF TRUTH — Download URL
// ============================================================
var VELVET_SHOW_DOWNLOAD_URL = 'https://github.com/Alxsparker/velvetshow/releases/latest/download/VELVET.SHOW.zip';

(function () {
  var downloadLinks = document.querySelectorAll('[data-download-link]');
  downloadLinks.forEach(function (el) {
    el.setAttribute('href', VELVET_SHOW_DOWNLOAD_URL);
  });

  var revealEls = document.querySelectorAll(
    '.feature__grid, .panic__inner, .audience__grid, .beta__inner, .migration__grid, .migration__maestro, .system-intro__flow, .triptych__devices, .roadmap__grid, .remote__modes'
  );

  if ('IntersectionObserver' in window) {
    var observer = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            entry.target.classList.add('is-visible');
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.1, rootMargin: '0px 0px -40px 0px' }
    );
    revealEls.forEach(function (el) { observer.observe(el); });
  } else {
    revealEls.forEach(function (el) { el.classList.add('is-visible'); });
  }
})();
