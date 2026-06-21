// Velvet Show landing page — small interaction layer.
// No frameworks, no analytics, no dependencies.

// ============================================================
// SINGLE SOURCE OF TRUTH — Beta download URL
// ------------------------------------------------------------
// Every "Download Beta" button on the site reads this URL.
// GitHub "latest" always points to the latest published release.
// Keep the release asset name exactly: VELVET.SHOW.zip
// ============================================================
var VELVET_SHOW_DOWNLOAD_URL =
  'https://github.com/Alxsparker/velvetshow/releases/latest/download/VELVET.SHOW.zip';

(function () {
  var downloadLinks = document.querySelectorAll('[data-download-link]');
  downloadLinks.forEach(function (el) {
    el.setAttribute('href', VELVET_SHOW_DOWNLOAD_URL);
  });

  var revealEls = document.querySelectorAll(
    '.feature__grid, .panic__inner, .audience__grid, .audience__title, .audience__migrate, .beta__inner, .concept'
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

    revealEls.forEach(function (el) {
      observer.observe(el);
    });
  } else {
    revealEls.forEach(function (el) {
      el.classList.add('is-visible');
    });
  }

  var form = document.getElementById('betaform');
  if (form) {
    form.addEventListener('submit', function (e) {
      e.preventDefault();

      var name = document.getElementById('bf-name').value.trim();
      var email = document.getElementById('bf-email').value.trim();
      var software = document.getElementById('bf-software').value.trim();
      var mac = document.getElementById('bf-mac').value.trim();

      var subject = encodeURIComponent('Velvet Show Beta Request');
      var bodyLines = [
        'Name: ' + name,
        'Email: ' + email,
        'Current software: ' + (software || '\u2014'),
        'Mac model: ' + (mac || '\u2014')
      ];
      var body = encodeURIComponent(bodyLines.join('\n'));

      window.location.href =
        'mailto:alexandre.chalon@gmail.com?subject=' + subject + '&body=' + body;
    });
  }
})();
