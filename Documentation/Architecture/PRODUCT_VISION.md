# Product Vision — Velvet Show

## Pourquoi Velvet Show existe

Velvet Show est un logiciel de **conduite de spectacle** ("show control") pour musiciens live.

**Velvet Show n'est pas un moteur lumière.** Il ne calcule pas de rendu DMX, ne gère pas de fixtures, ne remplace pas un logiciel d'éclairage. Il **pilote** différents moteurs lumière et d'automation existants — il en est le point de contrôle unifié, pas leur substitut.

Cette distinction est fondamentale et structure toute l'architecture du projet : Velvet Show orchestre, il ne fabrique pas la lumière lui-même.

## Vision

Velvet Show devient le **centre du spectacle** — le point unique depuis lequel un artiste ou un régisseur pilote l'ensemble d'un show en direct.

Aujourd'hui, Velvet Show pilote déjà :

- l'**audio** (playback, morceaux, transitions)
- la **timeline** (déroulé du spectacle, cues programmées)
- les **mémos** (repères et notes pendant le show)
- le **prompteur**
- le **remote iPad** (contrôle déporté)
- l'**éclairage** (via MIDI/OSC vers des moteurs tiers)
- l'**automation** au sens large (déclenchements programmés)

Demain, la même logique doit pouvoir s'étendre à :

- des **consoles de mixage**
- la **vidéo**
- des **Stream Deck**
- des **caméras PTZ**
- d'autres **extensions** encore non identifiées

Le principe directeur : chaque nouvelle capacité de pilotage s'ajoute au même centre de contrôle, selon le même modèle, sans jamais créer un second système parallèle.

## Philosophie

- **Simplicité** — un musicien sur scène n'a pas le temps de réfléchir à une interface complexe.
- **Fiabilité** — ce qui est branché et déclaré actif doit fonctionner à chaque fois, sans exception.
- **Rapidité** — de l'intention ("cette cue lumière doit partir ici") à l'exécution, sans latence perceptible.
- **Aucune surprise en concert** — jamais de comportement inattendu, jamais un mapping qui change tout seul, jamais un moteur qui répond différemment de ce qui a été testé.

Ces quatre principes priment sur toute considération d'élégance technique ou d'exhaustivité fonctionnelle. Une fonctionnalité qui introduit le moindre risque de surprise en concert n'a pas sa place dans Velvet Show tant qu'elle n'est pas vérifiée.

## Ce que Velvet Show ne doit jamais devenir

- **Un clone de logiciel DMX.** Velvet Show ne doit jamais chercher à refaire ce que font déjà MaestroDMX, ShowBuddy Active, QLC+ ou Lightkey. Son rôle est de les piloter, pas de les concurrencer sur leur propre terrain.
- **Un logiciel compliqué.** Chaque nouvelle extension ou capacité ajoutée ne doit jamais complexifier l'usage quotidien pour l'utilisateur qui n'en a pas besoin.
- **Un empilement de fonctions.** L'ajout de nouveaux moteurs, transports ou extensions ne doit jamais se faire en empilant des cas particuliers non reliés entre eux. Toute nouvelle capacité doit s'intégrer au modèle conceptuel commun (voir [ARCHITECTURE_DECISIONS.md](ARCHITECTURE_DECISIONS.md)), pas à côté de lui.

## Positionnement

Velvet Show est un logiciel de **conduite de spectacle**.

**Il ne remplace pas les moteurs lumière. Il les pilote.**

Il doit pouvoir fonctionner avec :

- MaestroDMX
- ShowBuddy Active
- DMXIS
- QLC+
- Lightkey
- Generic MIDI
- Generic OSC

**Le produit doit rester indépendant des moteurs.** Aucune décision d'architecture, d'UX ou de communication ne doit jamais présumer qu'un moteur précis restera la seule option. C'est cette indépendance qui rend possible l'ajout de nouveaux moteurs sans remise en cause du produit (voir [ARCHITECTURE_DECISIONS.md](ARCHITECTURE_DECISIONS.md) et [MASTER_ARCHITECTURE.md](MASTER_ARCHITECTURE.md)).

## Philosophie UX

L'utilisateur ne pense pas :

> "Je pilote MaestroDMX."

Il pense :

> "Je pilote mon spectacle."

Toute décision d'interface doit partir de ce cadrage. Le nom du moteur lumière actif est un détail de configuration, pas le sujet de l'expérience utilisateur. L'utilisateur programme des cues, gère un déroulé, déclenche des effets — il ne devrait jamais avoir à raisonner en termes de protocole ou de moteur pour accomplir ces gestes au quotidien, sauf au moment précis où il choisit ou vérifie sa configuration technique.

## Positionnement produit

Velvet Show n'est pas "encore un logiciel de conduite" — c'est **le seul logiciel de conduite qui parle à tous les moteurs lumière d'un musicien**, quel que soit le matériel déjà possédé.

Formulations de référence :

- *"Velvet Show — la conduite de spectacle qui pilote votre lumière, quel que soit votre matériel."*
- *"Un point de contrôle unique pour l'audio, la timeline et la lumière — compatible MaestroDMX, ShowBuddy Active, DMXIS, QLC+, Lightkey, et tout contrôleur MIDI ou OSC."*
- *"Velvet Show unifie la conduite de spectacle en direct : playback, timeline, prompteur et pilotage lumière multi-marques, avec un niveau de fiabilité conçu pour la scène."*

Le mot "universel" doit être employé avec prudence tant que tous les profils lumière ne sont pas vérifiés en conditions réelles (voir `VerificationState` dans [ARCHITECTURE_DECISIONS.md](ARCHITECTURE_DECISIONS.md)) : préférer "multi-moteurs" ou "multi-marques" tant que la [Phase 4](ROADMAP_ARCHITECTURE.md) n'est pas atteinte. Le produit ne doit jamais promettre en communication plus que ce que l'architecture garantit en fiabilité.
