# Master Architecture — Velvet Show

Ce document est la **référence absolue** du projet Velvet Show. En cas de doute ou de contradiction apparente entre documents, c'est celui-ci qui fait autorité. Toute évolution du logiciel doit être cohérente avec ce qui est décrit ici avant d'être entreprise.

## Velvet Show en une phrase

**Velvet Show est le cerveau du spectacle.**

Il pilote les différents systèmes utilisés en concert, mais **n'est pas lui-même un moteur lumière**.

## Mission

Velvet Show centralise :

- **playback** (audio)
- **timeline**
- **scheduler**
- **mémos**
- **prompteur**
- **remote**
- **automation**

Chacun de ces domaines reste distinct dans le code (voir [ARCHITECTURE_DECISIONS.md](ARCHITECTURE_DECISIONS.md)), mais tous sont orchestrés depuis le même centre : Velvet Show.

## Ce qu'il ne doit jamais devenir

- Un **clone de logiciel DMX** — Velvet Show ne recalcule pas de rendu lumière, il ne remplace pas MaestroDMX, ShowBuddy Active, QLC+ ou Lightkey sur leur propre terrain.
- Un **logiciel compliqué** — chaque ajout doit rester invisible pour l'utilisateur qui n'en a pas besoin.
- Un **empilement de fonctions** — toute nouvelle capacité s'intègre au modèle commun (scheduler / profils / transports / extensions), jamais à côté de lui.
- Un **logiciel dépendant d'un seul moteur lumière** — même si MaestroDMX reste la référence actuelle vérifiée en concert (voir [KNOWN_RISKS.md](KNOWN_RISKS.md)), l'architecture ne doit jamais supposer qu'un seul moteur existera pour toujours.

## Les piliers

- **Audio** — playback, morceaux, transitions.
- **Timeline** — déroulé du spectacle, cues programmées, mémos.
- **Scheduler** — point d'orchestration unique qui déclenche les cues au bon moment.
- **Automation** — déclenchements MIDI/OSC/futurs protocoles vers des systèmes externes.
- **Extensions** — catégories de pilotage externe (lumière aujourd'hui ; mixers, vidéo, Stream Deck, caméras PTZ demain).

## Architecture générale

La répartition des responsabilités suit une règle simple, à ne jamais transgresser :

> **Le scheduler décide QUAND.**
> **Les profils décident COMMENT.**
> **Les transports décident PAR QUEL PROTOCOLE.**
> **Les moteurs exécutent.**

Chaque couche ignore tout des couches situées au-dessus ou en dessous d'elle, sauf de son interface directe. Le détail de cette séparation (scheduler unique, transports séparés, profils séparés) est développé dans [ARCHITECTURE_DECISIONS.md](ARCHITECTURE_DECISIONS.md).

### Les transports

- **MIDI**
- **OSC**
- **Art-Net** (futur — non encore implémenté dans Velvet Show)

Un transport ne connaît jamais le moteur lumière ou l'extension à laquelle il parle : il ne fait qu'envoyer un message selon son propre protocole.

### Les Extensions

**Aujourd'hui :**
- Lighting

**Demain :**
- Mixers
- Vidéo
- Stream Deck
- Caméras PTZ
- autres

Le modèle Extension est conçu dès aujourd'hui pour accueillir ces catégories futures sans réécriture (voir [ROADMAP_ARCHITECTURE.md](ROADMAP_ARCHITECTURE.md) Phase 5).

## Règles d'or

**Si une nouvelle fonctionnalité nécessite de modifier :**
- MIDIEngine
- OSCEngine
- le scheduler

**alors il faut d'abord remettre en question l'architecture**, avant de coder quoi que ce soit. Un besoin qui pousse à toucher ces trois éléments est un signal que la fonctionnalité a été mal positionnée dans le modèle (probablement traitée comme un cas spécial de transport/scheduler plutôt que comme un nouveau profil ou une nouvelle extension).

**Toujours privilégier une évolution additive.** On ajoute un profil, une extension, une capacité — on ne modifie jamais un comportement existant pour en faire de la place à un nouveau.

## Comment prendre une décision

Avant toute nouvelle fonctionnalité, se poser systématiquement les questions suivantes, dans l'ordre :

1. **Est-ce compatible avec les principes ?** — voir [PRINCIPLES.md](PRINCIPLES.md). Si la fonctionnalité contredit un principe (fiabilité en concert, simplicité, évolution additive...), elle doit être repensée avant toute autre considération.
2. **Est-ce compatible avec MaestroDMX ?** — voir [ADR-0002](ADR/ADR-0002-MaestroDMX-is-the-reference.md). Le chemin MaestroDMX ne doit jamais être dégradé, même indirectement.
3. **Peut-on l'ajouter sans casser le scheduler ?** — voir [ADR-0006](ADR/ADR-0006-Scheduler-must-remain-generic.md). Si la réponse nécessite de modifier le scheduler pour un cas particulier, la fonctionnalité est mal positionnée.
4. **Est-ce une Extension plutôt qu'un cas particulier ?** — voir [ADR-0004](ADR/ADR-0004-Extensions-architecture.md). Un nouveau besoin de pilotage externe doit presque toujours se modéliser comme un profil ou une Extension, jamais comme une branche conditionnelle ad hoc.
5. **La documentation doit-elle être mise à jour avant le code ?** — voir [ADR-0008](ADR/ADR-0008-Documentation-before-code.md). Si la réponse est oui (ce qui est le cas dès qu'une décision structurante est en jeu), documenter d'abord — dans [ARCHITECTURE_DECISIONS.md](ARCHITECTURE_DECISIONS.md) et, si nécessaire, via un nouvel [ADR](ADR/) — puis seulement implémenter.

Si une de ces cinq questions ne trouve pas de réponse satisfaisante, la fonctionnalité ne doit pas être codée en l'état : elle doit d'abord faire l'objet d'une clarification d'architecture, quitte à consulter [ANTI_PATTERNS.md](ANTI_PATTERNS.md) pour vérifier qu'elle ne reproduit pas une erreur déjà identifiée.

---

Voir aussi : [PRODUCT_VISION.md](PRODUCT_VISION.md) pour la vision produit et le positionnement, [ARCHITECTURE_DECISIONS.md](ARCHITECTURE_DECISIONS.md) pour le détail du modèle conceptuel, [KNOWN_RISKS.md](KNOWN_RISKS.md) pour les garde-fous concrets, [PRINCIPLES.md](PRINCIPLES.md) pour les principes de long terme, [ANTI_PATTERNS.md](ANTI_PATTERNS.md) pour les erreurs à ne pas reproduire, et [ADR/](ADR/) pour l'historique détaillé des décisions structurantes.
