# Anti-Patterns — Velvet Show

Erreurs connues à ne jamais reproduire dans l'évolution de Velvet Show. Cette liste est **additive** : on y ajoute de nouveaux anti-patterns identifiés au fil du temps, on n'en retire jamais un déjà listé.

- **Ne jamais ajouter une exception spécifique MaestroDMX (ou tout autre moteur) dans le scheduler.** Le scheduler décide *quand*, jamais *pour quel moteur*. Voir [ADR-0006](ADR/ADR-0006-Scheduler-must-remain-generic.md).
- **Ne jamais mélanger UI et logique métier.** Un écran de réglages ne doit jamais contenir l'encodage d'un message MIDI/OSC ou la logique de décision d'un profil ; il ne fait qu'afficher un état et déclencher des intents.
- **Ne jamais modifier MIDIEngine pour supporter un moteur particulier.** MIDIEngine reste un transport générique. Toute spécificité de moteur se code au niveau du profil, jamais du transport. Voir [ADR-0007](ADR/ADR-0007-Transport-layer-separation.md).
- **Ne jamais modifier OSCEngine pour un backend précis.** Même règle que pour MIDIEngine, appliquée à OSC.
- **Ne jamais activer un profil non validé en live.** Un profil dont le `VerificationState` n'est pas `verifiedLive` ne doit jamais être sélectionnable pour un usage en concert réel. Voir [KNOWN_RISKS.md](KNOWN_RISKS.md).
- **Ne jamais contourner VerificationState.** Ne jamais introduire un flag ou un réglage parallèle (ex. un bouton caché, un mode debug) qui permettrait d'activer des contrôles live pour un profil non vérifié en dehors du mécanisme `VerificationState` lui-même. Voir [ADR-0005](ADR/ADR-0005-VerificationState.md).
- **Ne jamais coder avant d'avoir documenté une décision d'architecture.** Toute décision structurante se documente d'abord (ADR ou mise à jour d'`ARCHITECTURE_DECISIONS.md`), le code vient ensuite. Voir [ADR-0008](ADR/ADR-0008-Documentation-before-code.md).
- **Ne jamais créer de dépendance entre deux Extensions.** Une Extension (lighting, et demain mixers/vidéo/Stream Deck/caméras PTZ) ne doit jamais importer ou dépendre du code interne d'une autre Extension. Toute coordination entre deux Extensions passe par le scheduler ou par l'état central de l'application, jamais par un appel direct de l'une vers l'autre.
- **Ne jamais renommer un symbole `maestro*` avant la fin de la migration vers le modèle Extension.** Un renommage prématuré introduit un risque de régression sans bénéfice immédiat. Voir [KNOWN_RISKS.md](KNOWN_RISKS.md).
- **Ne jamais dupliquer la logique de scheduling par type de cue ou par moteur.** Le scheduler reste unique ; un nouveau type de cue s'ajoute au modèle existant, il ne crée pas une seconde boucle de dispatch parallèle.
- **Ne jamais faire dépendre le comportement d'un profil de l'ordre dans lequel les profils sont énumérés ou chargés.** Chaque profil doit être indépendant et fonctionner quelle que soit la présence ou l'absence des autres.
- **Ne jamais promouvoir un profil directement d'un `VerificationState` peu fiable à `verifiedLive` sans étape `experimental` documentée.** Voir [ADR-0005](ADR/ADR-0005-VerificationState.md) pour la progression attendue.
- **Ne jamais laisser la documentation en retard sur une décision déjà prise dans le code.** Si un écart est constaté, la documentation doit être corrigée immédiatement, pas laissée en l'état "pour plus tard".
- **Ne jamais promettre en communication produit plus que ce que l'architecture garantit en fiabilité** (ex. employer "universel" avant que les profils correspondants soient `verifiedLive`). Voir [PRODUCT_VISION.md](PRODUCT_VISION.md).

Voir aussi [PRINCIPLES.md](PRINCIPLES.md) pour les principes positifs qui sous-tendent cette liste, et [KNOWN_RISKS.md](KNOWN_RISKS.md) pour les garde-fous concrets à mettre en œuvre.
