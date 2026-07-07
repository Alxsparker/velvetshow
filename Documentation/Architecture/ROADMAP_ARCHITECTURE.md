# Roadmap Architecture — Velvet Show

Phases futures pour l'évolution de Velvet Show vers une architecture multi-moteurs lumière/automation. Chaque phase part du principe d'[évolution additive](ARCHITECTURE_DECISIONS.md) : on ne passe à la phase suivante qu'une fois la précédente stable, et on ne casse jamais MaestroDMX (voir [KNOWN_RISKS.md](KNOWN_RISKS.md)).

## Phase 0 — Documentation

Constituer la référence d'architecture (ce dossier `Documentation/Architecture/`). Aucun code touché. Objectif : que toute reprise future (Codex, Claude, humain) parte d'un contexte complet et sans ambiguïté.

## Phase 1 — Clarification UI

Clarifier dans l'interface la distinction entre "quel moteur lumière" (Lighting Profile) et "quel protocole de transport" (MIDI/OSC), aujourd'hui mélangés. Donner un état honnête aux profils déjà présents mais non finalisés dans l'interface.

## Phase 2 — Custom MIDI, Custom OSC

Rendre les profils MIDI générique et OSC générique réellement configurables par l'utilisateur (mapping arbitraire de notes/CC/adresses), cantonnés à la timeline et au mode test — jamais promus automatiquement en contrôles live.

## Phase 3 — Profils expérimentaux

Introduire formellement le modèle Extension / Lighting Profile / Transport / Capability / VerificationState. Migrer MaestroDMX dans ce modèle en enveloppant le code existant, sans le réécrire. Ajouter ShowBuddy Active et DMXIS comme profils visibles mais verrouillés (mapping non vérifié).

## Phase 4 — Profils validés

Vérifier par capture réelle (réseau et/ou MIDI) le mapping de chaque profil expérimental. Promouvoir progressivement chaque profil vers un état vérifié en concert réel, avec tests documentés. Mener les audits QLC+ et Lightkey, encore non réalisés.

## Phase 5 — Architecture Extensions

Généraliser le modèle au-delà de la lumière : mixers, vidéo, Stream Deck, caméras PTZ, et éventuellement un mécanisme d'extensions tierces. Cette phase n'est envisagée qu'une fois les phases précédentes stables.

## Futures études

Études à mener, sans engagement de calendrier, au fur et à mesure de l'avancement des phases ci-dessus — chacune commence à l'état `researchOnly` (voir [ARCHITECTURE_DECISIONS.md](ARCHITECTURE_DECISIONS.md)) :

- **QLC+** — audit dédié à mener, sur le modèle de l'audit ShowBuddy Active déjà réalisé (voir `Documentation/Research/`).
- **Lightkey** — audit dédié à mener.
- **Allen & Heath** — étude à mener en vue d'une future Extension "Mixers" (voir [MASTER_ARCHITECTURE.md](MASTER_ARCHITECTURE.md), section Extensions demain).
- **Autres extensions potentielles** — vidéo, Stream Deck, caméras PTZ, et tout autre système identifié au fil de l'usage réel du produit. Chaque étude suit le même format que l'audit ShowBuddy Active avant toute intégration.

---

Pour le détail des actions concrètes immédiatement suivantes, voir [NEXT_STEPS.md](NEXT_STEPS.md).
