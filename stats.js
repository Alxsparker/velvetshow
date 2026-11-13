// Compteur de visites anonyme — aucune donnée personnelle, juste la page et l'heure.
(function () {
  var FN_URL = 'https://pmgqpdjzptryegjfhsry.supabase.co/functions/v1/velvet-stats';
  var ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBtZ3FwZGp6cHRyeWVnamZoc3J5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMyMzg2OTUsImV4cCI6MjA5ODgxNDY5NX0.efAsSxWcpzq6oWX3KfgV-6xcjxppX8Z_3WWi8kmBqqI';

  // Pour ne plus te compter toi-même : ouvre une page du site avec ?notrack=1 (une fois par appareil).
  // ?notrack=0 remet le comptage. Le réglage reste dans le navigateur, rien n'est envoyé.
  var optedOut = false;
  try {
    var flag = new URLSearchParams(location.search).get('notrack');
    if (flag === '1') localStorage.setItem('velvetNoTrack', '1');
    else if (flag === '0') localStorage.removeItem('velvetNoTrack');
    optedOut = localStorage.getItem('velvetNoTrack') === '1';
  } catch (e) { /* stockage indisponible : on compte comme avant */ }

  // Quand le lien n'a pas de repère (?s=…), on devine le site d'origine d'après la page précédente de la personne.
  // On ne garde que le nom du site (« ref-facebook »), jamais l'adresse complète. Beaucoup d'applications (Facebook, Instagram sur
  // téléphone) ne transmettent pas cette information : ces visites restent « sans repère ».
  function sourceFromReferrer(ref, ownHost) {
    if (!ref) return '';
    var host = '';
    try { host = new URL(ref).hostname.toLowerCase(); } catch (e) { return ''; }
    host = host.replace(/^www\./, '');
    ownHost = (ownHost || '').toLowerCase().replace(/^www\./, '');
    if (!host || host === ownHost || /(^|\.)velvetshow\.app$/.test(host)) return '';
    var known = [
      [/(^|\.)facebook\.com$|(^|\.)fb\.com$|^fb\.me$/, 'facebook'],
      [/(^|\.)instagram\.com$/, 'instagram'],
      [/^mail\.google\.com$/, 'gmail'],
      [/(^|\.)google\.[a-z.]+$/, 'google'],
      [/(^|\.)bing\.com$/, 'bing'],
      [/(^|\.)duckduckgo\.com$/, 'duckduckgo'],
      [/(^|\.)youtube\.com$|^youtu\.be$/, 'youtube'],
      [/(^|\.)reddit\.com$/, 'reddit'],
      [/(^|\.)linkedin\.com$|^lnkd\.in$/, 'linkedin'],
      [/^t\.co$|(^|\.)twitter\.com$|^x\.com$/, 'x'],
      [/(^|\.)github\.com$/, 'github']
    ];
    for (var i = 0; i < known.length; i++) {
      if (known[i][0].test(host)) return 'ref-' + known[i][1];
    }
    return ('ref-' + host.replace(/[^a-z0-9]+/g, '-')).slice(0, 30).replace(/-+$/, '');
  }

  function track(path) {
    if (optedOut) return;
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

  // Pas de repère dans le lien et pas de source déjà retenue pour cette visite : on regarde d'où vient la personne.
  var storedSource = '';
  try { storedSource = sessionStorage.getItem('velvetSrc') || ''; } catch (e) { /* stockage indisponible */ }
  if (!source && !storedSource) source = sourceFromReferrer(document.referrer, location.hostname);

  // Le repère est gardé le temps de la visite : si la personne arrive par ?s=soundswitch puis change de page,
  // son clic « Télécharger » est quand même rattaché à cette source.
  var downloadSource = source;
  try {
    if (source) sessionStorage.setItem('velvetSrc', source);
    else downloadSource = sessionStorage.getItem('velvetSrc') || '';
  } catch (e) { /* stockage indisponible : on garde seulement le repère de la page */ }

  track(location.pathname + (source ? '?s=' + source : ''));

  // Début des numéros de page de paiement Lemon Squeezy → produit (les 8 premiers caractères suffisent).
  var BUY_PRODUCTS = { 'dc45e379': 'show', '9d48e0fc': 'visualizer', '39998983': 'duo', '2772dc45': 'light-dj' };

  // Clic sur un bouton de téléchargement (essai gratuit) : on compte le clic, rien d'autre.
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (!a) return;
    var href = a.getAttribute('href') || '';
    var suffix = downloadSource ? '?s=' + downloadSource : '';
    if (href.indexOf('velvetshow/releases/latest/download/VELVET.SHOW.zip') !== -1) track('/download/show' + suffix);
    else if (href.indexOf('VELVET-VISUALIZER-releases') !== -1) track('/download/visualizer' + suffix);
    else if (href.indexOf('VELVET-LIGHT-DJ-releases') !== -1) track('/download/light-dj' + suffix);
    else {
      // Clic sur un bouton « Acheter » : on compte le clic et le produit, rien d'autre. Le lien n'est pas modifié et la personne
      // part tout de suite vers la page de paiement (le comptage ne peut jamais empêcher d'acheter).
      var m = href.match(/lemonsqueezy\.com\/checkout\/buy\/([0-9a-f]{8})/i);
      var product = m && BUY_PRODUCTS[m[1].toLowerCase()];
      if (product) track('/buy-click/' + product + suffix);
    }
  });
})();
