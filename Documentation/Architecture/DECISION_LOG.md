# Decision Log — Velvet Show

Journal chronologique des grandes décisions d'architecture prises pour Velvet Show. Objectif : conserver la mémoire du projet, pour que personne n'ait à redécouvrir pourquoi une décision a été prise.

Chaque entrée : date, décision, contexte/raison.

---

**2026-07-04 — MaestroDMX désigné comme référence non négociable**
Décision : MaestroDMX reste le seul profil lumière vérifié en concert et ne doit jamais être cassé par l'ajout de nouveaux moteurs.
Contexte : MaestroDMX est le seul chemin lumière actuellement en usage réel sur scène. Toute évolution future est jugée à l'aune de cette contrainte.

**2026-07-04 — Choix du vocabulaire "Extension" / "Lighting Profile"**
Décision : adopter deux niveaux de vocabulaire — "Extension" comme terme technique englobant (lumière aujourd'hui, mixers/vidéo/Stream Deck/caméras PTZ demain), et "Lighting Profile" comme terme produit pour la sélection d'un moteur lumière précis.
Contexte : le brief initial proposait "Lighting Profiles", "Extensions" ou "Automation Backends" sans trancher. "Automation Backends" jugé trop technique pour l'utilisateur final ; "Extensions" seul jugé trop générique et évocateur d'un marketplace tiers prématuré.

**2026-07-04 — Introduction du concept VerificationState**
Décision : chaque Lighting Profile porte un état de vérification (vérifié en live / expérimental / mapping non vérifié / verrouillé) qui détermine seul si les contrôles live sont disponibles.
Contexte : identifié comme la pièce manquante du modèle initial (Extension / Lighting Profile / Transport / Capability), qui ne prévoyait pas de mécanisme unique pour dériver la confiance accordée à un profil. Remplace l'idée d'un simple booléen "verified" isolé.

**2026-07-04 — Statut des profils lumière connus**
Décision :
- MaestroDMX → vérifié en live, contrôles complets.
- MIDI générique / OSC générique → expérimental, timeline et test uniquement.
- ShowBuddy Active → mapping non vérifié, verrouillé (MIDI/OSC/Art-Net confirmés présents dans le binaire, mais adresses OSC exactes non capturées en runtime).
- DMXIS → mapping non vérifié, verrouillé, à traiter comme profil MIDI séparé de MaestroDMX.
- QLC+ et Lightkey → à étudier, aucun audit mené à ce stade.
Contexte : issu de la lecture du code existant (`MIDIEngine.swift`, `OSCEngine.swift`, `AppState.swift`, `Models.swift`, `MidiSettingsView.swift`) et de l'audit ShowBuddy Active déjà réalisé.

**2026-07-04 — Constitution de la documentation d'architecture**
Décision : créer `Documentation/Architecture/` comme référence d'architecture durable du projet, avec copie des audits existants (sans suppression des originaux) et rédaction des documents de vision, décisions, risques, feuille de route, prochaines étapes, glossaire et journal de décisions.
Contexte : nécessité que tout développement futur (Codex, Claude, ou humain) puisse repartir de cette documentation sans perdre les décisions déjà prises. `LIGHTING_BACKENDS_AUDIT.md` et `LIGHTING_PROFILES_PLAN.md`, mentionnés dans la mission d'origine, n'ont été retrouvés à aucun emplacement au moment de cette constitution — voir [NEXT_STEPS.md](NEXT_STEPS.md).

**2026-07-04 — Séparation Architecture / Research et création de MASTER_ARCHITECTURE.md**
Décision : créer `Documentation/Research/` pour isoler les audits de logiciels tiers (déplacés depuis `Documentation/Architecture/`, originaux conservés dans `ShowBuddyResearch`), et créer `MASTER_ARCHITECTURE.md` comme référence absolue faisant autorité en cas de contradiction entre documents.
Contexte : besoin de séparer clairement ce qui est propre à Velvet Show (`Architecture/`) de ce qui est recherche externe sur des logiciels tiers (`Research/`), et de disposer d'un document unique et court résumant la mission, les piliers et les règles d'or, sans avoir à recomposer cette synthèse à partir de plusieurs documents.

**2026-07-04 — Formalisation du quatrième VerificationState en `researchOnly`**
Décision : le quatrième état de `VerificationState`, jusque-là décrit de façon informelle comme "verrouillé", est formalisé sous le nom `researchOnly` — profil pas encore assez audité pour produire même un mapping théorique. Les trois autres états (`verifiedLive`, `experimental`, `unverifiedMapping`) sont inchangés.
Contexte : nécessité d'un nom stable et non ambigu pour ce quatrième état avant que le modèle `VerificationState` ne soit implémenté. Les mentions passées de "verrouillé"/"locked" dans les entrées antérieures de ce journal restent telles quelles (le journal ne réécrit pas l'historique) ; `ARCHITECTURE_DECISIONS.md` et `GLOSSARY.md` utilisent désormais le nom formalisé.

**2026-07-04 — Clôture de la phase d'architecture : ADR, principes, anti-patterns**
Décision : créer `Documentation/Architecture/ADR/` avec un Architecture Decision Record par décision structurante (ADR-0001 à ADR-0008 : Velvet n'est pas un moteur lumière, MaestroDMX référence, évolution additive, architecture Extensions, VerificationState, scheduler générique, séparation des transports, documentation avant code). Créer `PRINCIPLES.md` (principes de long terme) et `ANTI_PATTERNS.md` (erreurs à ne jamais reproduire). Ajouter à `MASTER_ARCHITECTURE.md` le chapitre "Comment prendre une décision" (5 questions systématiques avant toute nouvelle fonctionnalité).
Contexte : besoin de clôturer la phase de réflexion d'architecture pour que le développement (Codex ou autre) puisse reprendre sans nouvelle réflexion de fond, avec une justification tracée (pas seulement la décision, mais le contexte, les alternatives rejetées et pourquoi) pour chaque choix structurant déjà pris dans les sessions précédentes.
