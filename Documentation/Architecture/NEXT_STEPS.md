# Next Steps — Velvet Show

Prochaines étapes concrètes après ce cycle de documentation, à reprendre au retour de Codex ou par toute personne poursuivant le projet.

- **Clarification UI** — séparer visuellement, dans les réglages, le choix du moteur lumière (Lighting Profile) du choix du protocole de transport (MIDI/OSC), aujourd'hui mélangés dans l'interface existante. Voir [ROADMAP_ARCHITECTURE.md](ROADMAP_ARCHITECTURE.md) Phase 1.
- **Architecture Extensions** — formaliser le modèle Extension / Lighting Profile / Transport / Capability / VerificationState décrit dans [ARCHITECTURE_DECISIONS.md](ARCHITECTURE_DECISIONS.md), en enveloppant le code MaestroDMX existant sans le réécrire.
- **Profils Lighting** — définir et documenter, pour chaque profil (MaestroDMX, ShowBuddy Active, DMXIS, QLC+, Lightkey, MIDI générique, OSC générique), ses capacités déclarées et son `VerificationState` actuel.
- **Audit complet QLC+** — mener un audit dédié, sur le même modèle que l'audit ShowBuddy Active déjà réalisé (voir `Documentation/Research/SHOWBUDDY_ACTIVE_FOR_VELVET.md`). Statut de départ : `researchOnly`.
- **Audit complet Lightkey** — idem, audit dédié encore à réaliser. Statut de départ : `researchOnly`.
- **Validation runtime ShowBuddy Active** — capturer réellement (réseau et/ou MIDI) le mapping OSC de ShowBuddy Active, aujourd'hui non confirmé malgré la présence documentée d'OSC/Art-Net dans le binaire. Tant que non vérifié, ce profil reste à l'état `unverifiedMapping` (voir [ARCHITECTURE_DECISIONS.md](ARCHITECTURE_DECISIONS.md)).
- **Validation runtime DMXIS** — documenter et vérifier le mapping MIDI de DMXIS, à traiter comme un profil MIDI distinct de MaestroDMX, jamais fusionné avec lui. Même état de départ : `unverifiedMapping`.
- **Étude Art-Net** — évaluer l'implémentation d'un transport Art-Net générique, non encore implémenté dans Velvet Show aujourd'hui, en suivant le même principe que MIDIEngine/OSCEngine : un transport générique, indépendant de tout profil lumière particulier.
- **Documents d'audit manquants** — `LIGHTING_BACKENDS_AUDIT.md` et `LIGHTING_PROFILES_PLAN.md`, mentionnés dans la mission d'origine, n'ont été retrouvés à aucun emplacement connu au moment de la constitution de ce dossier. S'ils sont retrouvés ou rédigés plus tard, les ajouter à `Documentation/Research/` et mettre à jour [README.md](README.md) et `Documentation/Research/RESEARCH_INDEX.md`.

Chaque étape franchie doit être ajoutée à [DECISION_LOG.md](DECISION_LOG.md) au moment où elle est actée, pas après coup.
