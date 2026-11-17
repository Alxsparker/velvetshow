// Compteur de la remise de lancement (Velvet Visualizer, Velvet Show et Velvet Duo).
// Date de fin : les codes de réduction EXMZU0OA (Visualizer), G4NDC3MQ (Show) et GXMJU1MG (Duo) expirent tous le 26/11/2026 à 00:00 UTC
// (Visualizer lu dans Lemon Squeezy le 18/10/2026 ; Show et Duo lus le 30/10/2026).
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
  var MSG = {
    fr: ['Dernier jour au prix de lancement (fin le 25 novembre).', 'Prix de lancement\u00a0: plus\u00a0que\u00a0', '\u00a0jours.'],
    de: ['Letzter Tag zum Einführungspreis (endet am 25. November).', 'Einführungspreis:\u00a0noch\u00a0', '\u00a0Tage.'],
    es: ['Último día al precio de lanzamiento (termina el 25 de noviembre).', 'Precio de lanzamiento:\u00a0quedan\u00a0', '\u00a0días.'],
    it: ['Ultimo giorno al prezzo di lancio (termina il 25 novembre).', 'Prezzo di lancio:\u00a0ancora\u00a0', '\u00a0giorni.'],
    en: ['Last day at the launch price (ends 25 November).', 'Launch price: ', '\u00a0days\u00a0left.']
  };
  var m = MSG[lang] || MSG.en;
  text = days <= 1 ? m[0] : m[1] + days + m[2];
  document.querySelectorAll('[data-launch-countdown]').forEach(function (el) {
    el.textContent = text;
    el.hidden = false;
  });
})();
