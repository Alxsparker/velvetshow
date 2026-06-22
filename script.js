// Velvet Show landing page — small interaction layer.
// No frameworks, no analytics, no dependencies.

// ============================================================
// SINGLE SOURCE OF TRUTH — Download URL
// ------------------------------------------------------------
// Every "Download" button on the site (menu bar, hero,
// download section) reads its href from this one constant.
// To point the site at a new build, change this one value.
// ============================================================
var VELVET_SHOW_DOWNLOAD_URL = 'https://github.com/Alxsparker/velvetshow/releases/download/v0.12/VELVET.SHOW.zip';

(function () {
  var downloadLinks = document.querySelectorAll('[data-download-link]');
  downloadLinks.forEach(function (el) {
    el.setAttribute('href', VELVET_SHOW_DOWNLOAD_URL);
  });

  var revealEls = document.querySelectorAll(
    '.feature__grid, .panic__inner, .audience__grid, .audience__title, .audience__migrate, .beta__inner, .concept, .features__grid, .remote__modes, .roadmap__grid, .arch'
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
      { threshold: 0.15, rootMargin: '0px 0px -40px 0px' }
    );
    revealEls.forEach(function (el) { observer.observe(el); });
  } else {
    revealEls.forEach(function (el) { el.classList.add('is-visible'); });
  }

  var form = document.getElementById('betaform');
  if (form) {
    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var name = document.getElementById('bf-name').value.trim();
      var email = document.getElementById('bf-email').value.trim();
      var software = document.getElementById('bf-software').value.trim();
      var mac = document.getElementById('bf-mac').value.trim();
      var subject = encodeURIComponent('Velvet Show Request');
      var bodyLines = [
        'Name: ' + name,
        'Email: ' + email,
        'Current software: ' + (software || '—'),
        'Mac model: ' + (mac || '—')
      ];
      var body = encodeURIComponent(bodyLines.join('\n'));
      window.location.href = 'mailto:alexandre.chalon@gmail.com?subject=' + subject + '&body=' + body;
    });
  }
})();
