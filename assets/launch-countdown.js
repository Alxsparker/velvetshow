// Compteur de la remise de lancement du Velvet Visualizer.
// Date de fin : le code de réduction EXMZU0OA expire le 26/11/2026 à 00:00 UTC (lu dans Lemon Squeezy le 18/10/2026).
// Une date fixe, jamais remise à zéro : le compteur dit la vérité. Après cette date, les prix de la page reprennent
// automatiquement leur valeur normale (99 €), pour ne jamais afficher un prix que la boutique n'applique plus.
(function () {
  var END = Date.parse('2026-11-26T00:00:00Z');
  var lang = (document.documentElement.lang || 'en').slice(0, 2);
  var expired = Date.now() >= END;

  // Après la fin : on retire ce qui parle du lancement, et on remet le vrai prix.
  if (expired) {
    document.querySelectorAll('[data-launch-hide]').forEach(function (el) { el.hidden = true; });
    document.querySelectorAll('[data-launch-after]').forEach(function (el) { el.innerHTML = el.getAttribute('data-launch-after'); });
    document.querySelectorAll('[data-launch-countdown]').forEach(function (el) { el.hidden = true; });
    return;
  }

  // Avant la fin : « il reste N jours » (le dernier jour d'achat à ce prix est le 25 novembre).
  var days = Math.ceil((END - Date.now()) / 86400000);
  var text;
  if (lang === 'fr') {
    text = days <= 1 ? 'Dernier jour au prix de lancement (fin le 25 novembre).'
                     : 'Prix de lancement jusqu’au 25 novembre : plus que ' + days + ' jours.';
  } else {
    text = days <= 1 ? 'Last day at the launch price (ends 25 November).'
                     : 'Launch price until 25 November: ' + days + ' days left.';
  }
  document.querySelectorAll('[data-launch-countdown]').forEach(function (el) {
    el.textContent = text;
    el.hidden = false;
  });
})();
