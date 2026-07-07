# ADR-0004 — Architecture orientée Extensions

## Contexte

Velvet Show doit piloter aujourd'hui plusieurs moteurs lumière (MaestroDMX, ShowBuddy Active, DMXIS, QLC+, Lightkey, MIDI générique, OSC générique), et demain d'autres catégories de systèmes externes (mixers, vidéo, Stream Deck, caméras PTZ). Sans modèle commun, chaque nouvelle intégration risque d'être traitée comme un cas particulier isolé, ce qui mène à un empilement de fonctions non reliées entre elles.

## Décision

Adopter un modèle conceptuel commun à toute intégration externe : **Extension** (unité d'intégration générique) → **Lighting Profile** (déclinaison lumière d'une Extension, ex. MaestroDMX) → **Transport** (canal d'envoi générique : MIDI, OSC, futur Art-Net) → **Capability** (ce qu'un profil déclare savoir faire). La lumière est la première catégorie d'Extension ; les catégories futures (mixers, vidéo, Stream Deck, caméras PTZ) suivent le même modèle sans réécriture.

## Alternatives envisagées

- **Traiter chaque nouveau moteur comme un cas spécial ad hoc** (ce qui est la situation actuelle avec MaestroDMX fortement couplé à `AppState`/`MidiSettingsView`). Rejeté : c'est exactement le problème que cette décision cherche à corriger — non additif, non extensible, fort couplage UI/logique.
- **Créer un système de plugins dynamiques/chargeables dès maintenant** (manifeste externe, chargement runtime). Rejeté à ce stade : prématuré tant qu'il n'y a que sept profils connus et statiques ; pertinent seulement en Phase 5 (voir [ROADMAP_ARCHITECTURE.md](../ROADMAP_ARCHITECTURE.md)).
- **Un seul niveau de vocabulaire ("Backend" pour tout).** Rejeté : ne distingue pas le concept produit (Lighting Profile, ce que choisit l'utilisateur) du concept technique englobant (Extension, qui couvrira demain d'autres catégories que la lumière).

## Pourquoi cette décision

Ce modèle permet d'ajouter un moteur ou une catégorie d'Extension sans jamais toucher au scheduler ni aux transports (voir [ADR-0006](ADR-0006-Scheduler-must-remain-generic.md) et [ADR-0007](ADR-0007-Transport-layer-separation.md)), ce qui garantit l'évolution additive (voir [ADR-0003](ADR-0003-Evolution-must-be-additive.md)) et protège MaestroDMX (voir [ADR-0002](ADR-0002-MaestroDMX-is-the-reference.md)).

## Conséquences

- Tout nouveau moteur lumière s'implémente comme un nouveau Lighting Profile, jamais comme une branche supplémentaire dans le code existant de MaestroDMX.
- Toute nouvelle catégorie future (Mixers, Vidéo, Stream Deck, Caméras PTZ) doit être modélisée comme une nouvelle famille d'Extension suivant la même structure Profile/Transport/Capability, jamais comme un système parallèle.
- Voir [ARCHITECTURE_DECISIONS.md](../ARCHITECTURE_DECISIONS.md) pour le détail complet du modèle et [GLOSSARY.md](../GLOSSARY.md) pour les définitions précises de chaque terme.
