# Research Index — Velvet Show

Index des logiciels tiers étudiés en vue d'un pilotage depuis Velvet Show. Ce dossier contient exclusivement de la **recherche externe** — pour la documentation propre à Velvet Show, voir [`../Architecture/`](../Architecture/), et en particulier [MASTER_ARCHITECTURE.md](../Architecture/MASTER_ARCHITECTURE.md).

Pour chaque logiciel : objectif de l'étude, intérêt pour Velvet Show, et statut actuel (voir `VerificationState` dans [ARCHITECTURE_DECISIONS.md](../Architecture/ARCHITECTURE_DECISIONS.md) pour la définition précise des statuts).

## MaestroDMX

- **Objectif** — moteur lumière déjà piloté par Velvet Show en production.
- **Intérêt pour Velvet** — c'est la référence actuelle : seul profil lumière vérifié en conditions réelles de concert.
- **Statut : intégré** (`verifiedLive`).

## ShowBuddy Active

- **Objectif** — évaluer le pilotage de ShowBuddy Active (MIDI/OSC/Art-Net) depuis Velvet Show comme profil lumière additionnel.
- **Intérêt pour Velvet** — MIDI, OSC et sortie Art-Net confirmés présents dans le binaire ; formats de show/preset lisibles en XML (`DmxConfig.xml`, `bank.xml`, `.prt`).
- **Statut : audit terminé** (`unverifiedMapping`) — le mapping OSC exact (adresses, ports) n'a pas été capturé en conditions réelles ; voir `SHOWBUDDY_ACTIVE_FOR_VELVET.md` et `SHOWBUDDY_ACTIVE_FINDINGS.json` dans ce dossier. Validation runtime à mener (voir [NEXT_STEPS.md](../Architecture/NEXT_STEPS.md)).

## QLC+

- **Objectif** — évaluer un pilotage MIDI/OSC/Art-Net depuis Velvet Show.
- **Intérêt pour Velvet** — logiciel de contrôle lumière libre largement répandu chez les utilisateurs indépendants ; profil candidat naturel pour élargir la compatibilité de Velvet Show.
- **Statut : à étudier** (`researchOnly`) — aucun audit mené à ce stade.

## Lightkey

- **Objectif** — évaluer un pilotage MIDI/OSC depuis Velvet Show.
- **Intérêt pour Velvet** — logiciel de contrôle lumière macOS répandu dans l'écosystème visé par Velvet Show.
- **Statut : à étudier** (`researchOnly`) — aucun audit mené à ce stade.

## DMXIS

- **Objectif** — évaluer un pilotage MIDI depuis Velvet Show, en tant que profil distinct de MaestroDMX.
- **Intérêt pour Velvet** — matériel/logiciel utilisé par une partie des musiciens ciblés ; mapping MIDI à documenter précisément pour ne jamais le confondre avec la convention MaestroDMX.
- **Statut : à compléter** (`unverifiedMapping` dès qu'un premier mapping théorique sera documenté ; `researchOnly` en l'état actuel).

## Allen & Heath

- **Objectif** — évaluer une future Extension "Mixers" (hors lumière) pilotée depuis Velvet Show.
- **Intérêt pour Velvet** — console de mixage répandue chez les musiciens live ; premier candidat identifié pour l'Extension Mixers évoquée dans [MASTER_ARCHITECTURE.md](../Architecture/MASTER_ARCHITECTURE.md).
- **Statut : à étudier** (`researchOnly`) — aucun audit mené à ce stade.

---

Toute mise à jour de statut doit être répercutée dans [DECISION_LOG.md](../Architecture/DECISION_LOG.md) au moment où elle est actée.
