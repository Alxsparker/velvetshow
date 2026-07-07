# Architecture Decisions — Velvet Show

Ce document résume les décisions d'architecture déjà prises pour permettre à Velvet Show de piloter plusieurs moteurs lumière/automation sans jamais casser le chemin MaestroDMX, qui fonctionne aujourd'hui en concert.

Voir [DECISION_LOG.md](DECISION_LOG.md) pour l'historique chronologique de ces décisions, et [GLOSSARY.md](GLOSSARY.md) pour la définition précise de chaque terme.

## Architecture

- **Évolution additive uniquement.** Toute nouvelle capacité (nouveau moteur, nouveau transport, nouvelle extension) s'ajoute au système existant ; elle ne remplace et ne modifie jamais un chemin qui fonctionne déjà.
- **MaestroDMX reste la référence actuelle.** C'est le seul profil lumière aujourd'hui vérifié en conditions réelles de concert. Tout nouveau profil est comparé à ce niveau d'exigence, jamais l'inverse.
- **Ne jamais casser MaestroDMX.** C'est la contrainte absolue au-dessus de toutes les autres. Aucune refonte, aucun renommage, aucune réorganisation ne justifie un risque sur ce chemin.
- **Scheduler unique.** Le déclenchement des cues (timeline, mémos, événements MIDI/OSC programmés) passe par un seul point d'orchestration, commun à tous les profils lumière. On ne duplique pas la logique de scheduling par moteur.
- **Transports séparés.** MIDI et OSC (et demain Art-Net ou autres) restent des couches de transport génériques, indépendantes de tout moteur lumière particulier. Un transport ne doit jamais contenir de logique propre à un moteur.
- **Profils séparés.** Chaque moteur lumière (MaestroDMX, ShowBuddy Active, DMXIS, QLC+, Lightkey, MIDI générique, OSC générique) est un profil indépendant. Un profil ne doit jamais dépendre du code interne d'un autre profil.
- **Architecture extensible.** Le même modèle qui sépare scheduler / transports / profils pour la lumière doit pouvoir accueillir demain d'autres catégories de pilotage (mixers, vidéo, Stream Deck, caméras PTZ) sans réécriture.

## Concepts du modèle

- **Extension** — unité d'intégration générique (lumière aujourd'hui ; mixers, vidéo, Stream Deck, caméras PTZ demain). C'est le concept technique le plus englobant du modèle.
- **Lighting Profile** — la déclinaison "lumière" d'une Extension : un moteur lumière précis que l'utilisateur peut sélectionner (ex. MaestroDMX, ShowBuddy Active).
- **Transport** — le canal d'envoi générique utilisé par un profil (MIDI, OSC, et demain Art-Net). Un Transport ne connaît jamais le moteur lumière auquel il parle.
- **Capability** — une capacité que déclare un profil (ex. déclencher une cue, régler une intensité, blackout). Sert à savoir ce qu'un profil peut faire sans supposer comment il le fait.
- **VerificationState** — l'état de confiance d'un profil. Détail complet ci-dessous.

## VerificationState

Chaque Lighting Profile porte un `VerificationState`, qui est **le seul** mécanisme déterminant si les contrôles live sont autorisés pour ce profil — ce n'est jamais un réglage manuel indépendant, et il n'y a jamais deux flags à synchroniser à la main.

- **`verifiedLive`** — le profil a été testé en conditions réelles de concert et son mapping est confirmé fiable. Les contrôles live (brightness manuel, cue picker manuel) sont autorisés. Aujourd'hui, seul MaestroDMX est dans cet état.
- **`experimental`** — le profil fonctionne en test (timeline, mode test) mais n'a pas encore été éprouvé en concert réel. Les contrôles live automatiques restent désactivés ; l'usage en timeline/test est autorisé pour permettre la progression vers `verifiedLive`. C'est l'état des profils Generic MIDI et Generic OSC configurés par l'utilisateur.
- **`unverifiedMapping`** — le mapping (MIDI, OSC, ou autre) est documenté sur le papier (audit, lecture de binaire, documentation éditeur) mais n'a jamais été confirmé par une capture réelle sur le matériel. Le profil est visible dans l'interface, pour information, mais rien n'est envoyé au moteur tant que cet état n'a pas progressé. C'est l'état actuel de ShowBuddy Active et DMXIS.
- **`researchOnly`** — le profil n'a pas encore fait l'objet d'un audit suffisant pour même produire un mapping théorique. Il n'existe qu'à titre d'étude ou d'intention (ex. QLC+, Lightkey avant leur audit dédié). Aucune tentative d'envoi, même en test, n'est possible dans cet état.

Rôle de cet état : dériver automatiquement la disponibilité des contrôles live, du mode test, et des avertissements affichés à l'utilisateur — à partir d'une seule source de vérité par profil, plutôt que de multiplier des booléens indépendants qui pourraient devenir incohérents entre eux.

**Progression attendue** : `researchOnly` → `unverifiedMapping` → `experimental` → `verifiedLive`. Un profil ne doit jamais sauter directement de `researchOnly` ou `unverifiedMapping` à `verifiedLive` sans être passé par une phase `experimental` documentée (voir [ROADMAP_ARCHITECTURE.md](ROADMAP_ARCHITECTURE.md)).

## Principe de responsabilité

Chaque couche du modèle ignore délibérément tout des couches qui ne la concernent pas directement :

- **Le scheduler ne connaît jamais le moteur.** Il décide *quand* une cue se déclenche ; il ignore tout de MaestroDMX, ShowBuddy Active ou de n'importe quel autre moteur lumière.
- **Le moteur ne connaît jamais la timeline.** Un profil (ex. MaestroDMXProfile) reçoit un intent à exécuter ; il ne sait rien de la structure du spectacle, des mémos ou de la position de lecture.
- **Le transport ne connaît jamais l'UI.** MIDIEngine et OSCEngine envoient des messages bruts ; ils n'ont aucune connaissance des écrans de réglages, des boutons de test, ou de l'état d'affichage.

Ce principe est ce qui permet à chaque couche d'évoluer indépendamment des autres, et c'est la condition pour que l'ajout d'un nouveau profil ou d'une nouvelle extension n'ait jamais besoin de toucher au scheduler ou aux transports (voir la règle d'or dans [MASTER_ARCHITECTURE.md](MASTER_ARCHITECTURE.md)).

## Vision long terme

Velvet Show pilote plusieurs moteurs lumière au travers du modèle Lighting Profile, notamment :

- MaestroDMX
- ShowBuddy Active
- DMXIS
- QLC+
- Lightkey
- Generic MIDI
- Generic OSC

Chacun de ces profils est indépendant, a son propre `VerificationState`, et n'affecte jamais le fonctionnement des autres. L'ajout d'un profil supplémentaire ne doit jamais nécessiter de modifier le comportement d'un profil existant.
