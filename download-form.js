/* Velvet (Visualizer, Show, Light DJ) — petit formulaire « e-mail » avant le téléchargement de l'essai.
 *
 * Ce que ça fait : quand quelqu'un clique sur « Télécharger l'essai » d'une des trois apps, une fenêtre demande son e-mail
 * (+ une case, décochée, pour recevoir les nouveautés). L'adresse est envoyée au petit programme « velvet-signup »
 * (Cloudflare), qui la range dans Resend et envoie un e-mail de confirmation si la case est cochée.
 *
 * Règle d'or : ÉCHEC OUVERT. Si le programme ne répond pas (panne, réseau coupé, bloqueur de pub), le téléchargement
 * démarre quand même, au bout de quelques secondes au plus. Rien ne peut empêcher quelqu'un de télécharger.
 *
 * Le comptage des clics (stats.js) continue de fonctionner : ici on ne bloque pas la propagation du clic.
 */
(function () {
  'use strict';

  var ENDPOINT = 'https://velvet-signup.alexandre-chalon.workers.dev/subscribe';
  // Les trois liens de téléchargement de l'essai et l'app qu'ils désignent (même nom de produit que le programme velvet-signup).
  var PRODUCTS = [
    { id: 'visualizer', name: 'Velvet Visualizer', re: /VELVET-VISUALIZER-releases\/releases\/latest\/download\/VELVET-VISUALIZER\.zip/ },
    { id: 'show', name: 'Velvet Show', re: /Alxsparker\/velvetshow\/releases\/latest\/download\/VELVET\.SHOW\.zip/ },
    { id: 'light-dj', name: 'Velvet Light DJ', re: /VELVET-LIGHT-DJ-releases\/releases\/latest\/download\/VELVET-LIGHT-DJ\.zip/ }
  ];
  function productOf(url) {
    for (var i = 0; i < PRODUCTS.length; i++) if (PRODUCTS[i].re.test(url)) return PRODUCTS[i];
    return null;
  }
  var MIN_FORM_MS = 1400;   // le programme ignore les envois faits en moins de 1,2 s (robots) : on attend un peu
  var TIMEOUT_MS = 6000;    // au-delà, le téléchargement part quand même
  var DONE_KEY = 'velvetDlFormDone';

  var NBSP = ' ';
  var TEXT = {
    fr: {
      title: 'Télécharger l’essai gratuit',
      intro: 'Entrez votre e-mail : le téléchargement démarre tout de suite, et je peux vous répondre si vous avez une question.',
      label: 'Votre e-mail',
      consent: 'Oui, je veux recevoir quelques e-mails d’Alex sur {app} et les autres apps Velvet (3 e-mails pendant l’essai). Je peux me désinscrire à tout moment.',
      button: 'Télécharger',
      wait: 'Un instant…',
      done: 'Le téléchargement démarre.',
      doneConfirm: 'Le téléchargement démarre. Si vous avez coché la case, ouvrez l’e-mail de confirmation que je viens de vous envoyer (pensez aux courriers indésirables).',
      invalid: 'Cette adresse e-mail ne semble pas correcte.',
      privacy: 'Comment votre e-mail est utilisé',
      privacyUrl: '/fr/confidentialite-du-site.html#formulaire',
      close: 'Fermer',
      nbsp: true
    },
    en: {
      title: 'Download the free trial',
      intro: 'Enter your email: the download starts right away, and I can answer you if you have a question.',
      label: 'Your email',
      consent: 'Yes, I would like to receive a few emails from Alex about {app} and the other Velvet apps (3 emails during the trial). I can unsubscribe at any time.',
      button: 'Download',
      wait: 'One moment…',
      done: 'The download is starting.',
      doneConfirm: 'The download is starting. If you ticked the box, open the confirmation email I just sent you (check your spam folder).',
      invalid: 'This email address does not look right.',
      privacy: 'How your email is used',
      privacyUrl: '/website-privacy.html#formulaire',
      close: 'Close'
    },
    de: {
      title: 'Kostenlose Testversion herunterladen',
      intro: 'Geben Sie Ihre E-Mail-Adresse ein: Der Download startet sofort, und ich kann Ihnen bei Fragen antworten.',
      label: 'Ihre E-Mail-Adresse',
      consent: 'Ja, ich möchte einige E-Mails von Alex zu {app} und den anderen Velvet-Apps erhalten (3 E-Mails während der Testphase). Ich kann mich jederzeit abmelden.',
      button: 'Herunterladen',
      wait: 'Einen Moment…',
      done: 'Der Download startet.',
      doneConfirm: 'Der Download startet. Wenn Sie das Kästchen angekreuzt haben, öffnen Sie die Bestätigungs-E-Mail, die ich Ihnen gerade geschickt habe (prüfen Sie auch den Spam-Ordner).',
      invalid: 'Diese E-Mail-Adresse scheint nicht korrekt zu sein.',
      privacy: 'Wie Ihre E-Mail-Adresse verwendet wird',
      privacyUrl: '/de/datenschutz-website.html#formulaire',
      close: 'Schließen'
    },
    es: {
      title: 'Descargar la prueba gratuita',
      intro: 'Escriba su correo: la descarga empieza enseguida, y puedo responderle si tiene alguna pregunta.',
      label: 'Su correo electrónico',
      consent: 'Sí, quiero recibir algunos correos de Alex sobre {app} y las demás apps Velvet (3 correos durante la prueba). Puedo darme de baja en cualquier momento.',
      button: 'Descargar',
      wait: 'Un momento…',
      done: 'La descarga está empezando.',
      doneConfirm: 'La descarga está empezando. Si marcó la casilla, abra el correo de confirmación que acabo de enviarle (revise también el correo no deseado).',
      invalid: 'Esta dirección de correo no parece correcta.',
      privacy: 'Cómo se usa su correo',
      privacyUrl: '/es/privacidad-del-sitio.html#formulaire',
      close: 'Cerrar'
    },
    it: {
      title: 'Scarica la prova gratuita',
      intro: 'Inserisci la tua e-mail: il download parte subito, e posso risponderti se hai una domanda.',
      label: 'La tua e-mail',
      consent: 'Sì, voglio ricevere alcune e-mail di Alex su {app} e sulle altre app Velvet (3 e-mail durante la prova). Posso annullare l’iscrizione in qualsiasi momento.',
      button: 'Scarica',
      wait: 'Un attimo…',
      done: 'Il download sta per iniziare.',
      doneConfirm: 'Il download sta per iniziare. Se hai spuntato la casella, apri l’e-mail di conferma che ti ho appena inviato (controlla anche lo spam).',
      invalid: 'Questo indirizzo e-mail non sembra corretto.',
      privacy: 'Come viene usata la tua e-mail',
      privacyUrl: '/it/privacy-del-sito.html#formulaire',
      close: 'Chiudi'
    }
  };

  var lang = ((document.documentElement.getAttribute('lang') || 'en').slice(0, 2) || 'en').toLowerCase();
  if (!TEXT[lang]) lang = 'en';
  var T = TEXT[lang];

  // Typographie française : espace insécable devant ? ! : ; et après les mots courts (pas de mot orphelin en bout de ligne).
  function typo(s) {
    if (lang !== 'fr') return s;
    var short = /(^|[ \u00a0])(à|a|y|et|ou|de|du|le|la|les|un|une|des|en|je|ne|se|si|au|aux|ce|sa|son|ses|mon|ma|mes|vos|vous|sur|par|pour|dans|avec|sans|que|qui|est|pas|tout) /gi;
    s = s.replace(/ ([?!:;])/g, NBSP + '$1');
    s = s.replace(short, '$1$2' + NBSP).replace(short, '$1$2' + NBSP);   // deux passes : mots courts qui se suivent
    return s;
  }

  var STYLE = [
    '.vdf-ov{position:fixed;inset:0;background:rgba(5,6,9,.72);z-index:10000;display:flex;align-items:center;justify-content:center;padding:16px;overscroll-behavior:contain}',
    '.vdf-box{position:relative;background:#15171d;color:#eceef3;border:1px solid #262a33;border-radius:14px;max-width:440px;width:100%;padding:26px 24px 22px;box-shadow:0 20px 60px rgba(0,0,0,.5);font:15px/1.55 Inter,-apple-system,Helvetica,Arial,sans-serif}',
    '.vdf-box h2{margin:0 28px 8px 0;font-size:19px;line-height:1.3;color:#fff}',
    '.vdf-box p{margin:0 0 14px;color:#9aa1b0;font-size:14px}',
    '.vdf-box label.vdf-l{display:block;font-weight:600;font-size:13px;margin:0 0 6px;color:#eceef3}',
    '.vdf-box input[type=email]{width:100%;box-sizing:border-box;background:#0d0e12;color:#eceef3;border:1px solid #3a3f4b;border-radius:8px;padding:11px 12px;font:inherit;font-size:16px}',
    '.vdf-box input[type=email]:focus{outline:2px solid #ff6b35;outline-offset:1px;border-color:#ff6b35}',
    '.vdf-c{display:flex;gap:10px;align-items:flex-start;margin:14px 0 4px;font-size:13px;color:#9aa1b0;cursor:pointer}',
    '.vdf-c input{margin-top:3px;flex:none;width:16px;height:16px;accent-color:#ff6b35}',
    '.vdf-btn{display:block;width:100%;margin-top:16px;background:#ff6b35;color:#fff;border:0;border-radius:9px;padding:12px 16px;font:inherit;font-weight:700;cursor:pointer}',
    '.vdf-btn:disabled{opacity:.7;cursor:progress}',
    '.vdf-err{color:#ff8a8a;font-size:13px;margin:8px 0 0;min-height:1em}',
    '.vdf-msg{color:#34d17a;margin:0}',
    '.vdf-x{position:absolute;top:10px;right:10px;background:none;border:0;color:#9aa1b0;font-size:24px;line-height:1;width:36px;height:36px;cursor:pointer;border-radius:8px}',
    '.vdf-x:hover{color:#fff;background:rgba(255,255,255,.06)}',
    '.vdf-pv{display:block;margin-top:14px;font-size:12px;color:#9aa1b0;text-decoration:underline}',
    '.vdf-hp{position:absolute!important;left:-9999px!important;top:auto!important;width:1px;height:1px;overflow:hidden}'
  ].join('');

  var overlay = null, lastFocus = null, openedAt = 0, busy = false, href = '', product = PRODUCTS[0];

  function el(tag, attrs, text) {
    var n = document.createElement(tag);
    if (attrs) for (var k in attrs) if (Object.prototype.hasOwnProperty.call(attrs, k)) n.setAttribute(k, attrs[k]);
    if (text != null) n.textContent = text;
    return n;
  }

  function startDownload(url) {
    // Téléchargement d'un fichier : la page reste affichée.
    window.location.href = url;
  }

  function close() {
    if (!overlay) return;
    document.removeEventListener('keydown', onKey, true);
    overlay.parentNode && overlay.parentNode.removeChild(overlay);
    overlay = null;
    busy = false;
    if (lastFocus && lastFocus.focus) { try { lastFocus.focus(); } catch (e) {} }
  }

  function onKey(e) {
    if (!overlay) return;
    if (e.key === 'Escape') { e.preventDefault(); close(); return; }
    if (e.key === 'Tab') {            // on garde le clavier dans la fenêtre
      var items = overlay.querySelectorAll('input,button,a[href]');
      var f = [];
      for (var i = 0; i < items.length; i++) if (!items[i].disabled && items[i].tabIndex >= 0 && items[i].offsetParent !== null) f.push(items[i]);
      if (!f.length) return;
      var first = f[0], last = f[f.length - 1];
      if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
      else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
    }
  }

  function open(url, prod) {
    if (overlay) return;
    href = url;
    product = prod;
    lastFocus = document.activeElement;
    openedAt = Date.now();

    if (!document.getElementById('vdf-style')) {
      var st = el('style', { id: 'vdf-style' });
      st.textContent = STYLE;
      document.head.appendChild(st);
    }

    overlay = el('div', { 'class': 'vdf-ov' });
    var box = el('div', { 'class': 'vdf-box', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'vdf-title' });
    var x = el('button', { type: 'button', 'class': 'vdf-x', 'aria-label': T.close }, '×');
    x.addEventListener('click', close);
    var h = el('h2', { id: 'vdf-title' }, typo(T.title));
    var p = el('p', null, typo(T.intro));

    var form = el('form', { novalidate: 'novalidate' });
    var lab = el('label', { 'class': 'vdf-l', 'for': 'vdf-email' }, typo(T.label));
    var email = el('input', { type: 'email', id: 'vdf-email', name: 'email', required: 'required', autocomplete: 'email', inputmode: 'email', autocapitalize: 'none', spellcheck: 'false', maxlength: '254' });
    var hpWrap = el('div', { 'class': 'vdf-hp', 'aria-hidden': 'true' });
    var hp = el('input', { type: 'text', name: 'website', tabindex: '-1', autocomplete: 'off' });
    hpWrap.appendChild(hp);
    var cWrap = el('label', { 'class': 'vdf-c' });
    var cb = el('input', { type: 'checkbox', name: 'consent' });   // volontairement décochée
    cWrap.appendChild(cb);
    cWrap.appendChild(el('span', null, typo(T.consent.replace('{app}', product.name))));
    var err = el('p', { 'class': 'vdf-err', role: 'alert' });
    var btn = el('button', { type: 'submit', 'class': 'vdf-btn' }, typo(T.button));
    var pv = el('a', { href: T.privacyUrl, 'class': 'vdf-pv', target: '_blank', rel: 'noopener' }, typo(T.privacy));

    form.appendChild(lab); form.appendChild(email); form.appendChild(hpWrap); form.appendChild(cWrap);
    form.appendChild(err); form.appendChild(btn);
    box.appendChild(x); box.appendChild(h); box.appendChild(p); box.appendChild(form); box.appendChild(pv);
    overlay.appendChild(box);
    overlay.addEventListener('mousedown', function (e) { if (e.target === overlay) close(); });
    document.body.appendChild(overlay);
    document.addEventListener('keydown', onKey, true);
    setTimeout(function () { try { email.focus(); } catch (e) {} }, 30);

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      if (busy) return;
      var value = (email.value || '').trim();
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value)) { err.textContent = typo(T.invalid); email.focus(); return; }
      err.textContent = '';
      busy = true;
      btn.disabled = true;
      btn.textContent = T.wait;
      submit(value, cb.checked, hp.value, function (consentSent) {
        // Quoi qu'il arrive (succès, panne, délai dépassé), le téléchargement démarre.
        try { sessionStorage.setItem(DONE_KEY + ':' + product.id, '1'); } catch (e2) {}
        if (!overlay) { startDownload(href); return; }
        var m = el('p', { 'class': 'vdf-msg', role: 'status' }, typo(consentSent ? T.doneConfirm : T.done));
        form.parentNode.replaceChild(m, form);
        p.parentNode && p.parentNode.removeChild(p);
        startDownload(href);
        setTimeout(close, consentSent ? 9000 : 3500);
      });
    });
  }

  function submit(email, consent, honeypot, done) {
    var finished = false;
    function end(consentSent) { if (finished) return; finished = true; done(consentSent); }
    var wait = Math.max(0, MIN_FORM_MS - (Date.now() - openedAt));
    var timer = setTimeout(function () { end(false); }, TIMEOUT_MS + wait);
    setTimeout(function () {
      var ctrl = (typeof AbortController === 'function') ? new AbortController() : null;
      var killer = ctrl ? setTimeout(function () { ctrl.abort(); }, TIMEOUT_MS) : null;
      try {
        fetch(ENDPOINT, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email: email, consent: consent, lang: lang, product: product.id, website: honeypot, t: Date.now() - openedAt }),
          signal: ctrl ? ctrl.signal : undefined,
          keepalive: true
        }).then(function (r) { return r.json().catch(function () { return {}; }); })
          .then(function (j) { clearTimeout(timer); if (killer) clearTimeout(killer); end(Boolean(j && j.confirmationSent)); })
          .catch(function () { clearTimeout(timer); if (killer) clearTimeout(killer); end(false); });
      } catch (e) { clearTimeout(timer); end(false); }
    }, wait);
  }

  // Un clic sur le bouton de téléchargement de l'essai → la fenêtre. En phase de capture, sans bloquer la propagation :
  // le comptage de stats.js reçoit toujours le clic.
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (!a) return;
    var url = a.getAttribute('href') || '';
    var prod = productOf(url);
    if (!prod) return;
    var already = false;
    try { already = sessionStorage.getItem(DONE_KEY + ':' + prod.id) === '1'; } catch (err) {}
    if (already) return;               // déjà passé par la fenêtre dans cette visite : lien direct
    e.preventDefault();
    open(url, prod);
  }, true);
})();
