// Compteur de visites anonyme — aucune donnée personnelle, juste la page et l'heure.
(function () {
  var FN_URL = 'https://pmgqpdjzptryegjfhsry.supabase.co/functions/v1/velvet-stats';
  var ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBtZ3FwZGp6cHRyeWVnamZoc3J5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMyMzg2OTUsImV4cCI6MjA5ODgxNDY5NX0.efAsSxWcpzq6oWX3KfgV-6xcjxppX8Z_3WWi8kmBqqI';

  function track(path) {
    fetch(FN_URL, {
      method: 'POST',
      keepalive: true,
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + ANON_KEY, 'apikey': ANON_KEY },
      body: JSON.stringify({ action: 'track', path: path })
    }).catch(function () { /* une visite ratée n'est pas grave */ });
  }

  // Repère de source facultatif dans le lien (?s=soundswitch) : on l'ajoute à la page pour savoir d'où vient la visite.
  var source = '';
  try {
    source = (new URLSearchParams(location.search).get('s') || '').toLowerCase().replace(/[^a-z0-9_-]/g, '').slice(0, 30);
  } catch (e) { /* navigateur ancien : pas de repère */ }

  track(location.pathname + (source ? '?s=' + source : ''));

  // Clic sur un bouton de téléchargement (essai gratuit) : on compte le clic, rien d'autre.
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (!a) return;
    var href = a.getAttribute('href') || '';
    if (href.indexOf('velvetshow/releases/latest/download/VELVET.SHOW.zip') !== -1) track('/download/show');
    else if (href.indexOf('VELVET-VISUALIZER-releases') !== -1) track('/download/visualizer');
  });
})();
