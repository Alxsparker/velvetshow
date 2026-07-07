# Glossary — Velvet Show

Définitions des termes utilisés dans la documentation d'architecture de Velvet Show.

- **Extension** — Unité d'intégration générique dans le modèle Velvet Show. La lumière est la première catégorie d'Extension ; mixers, vidéo, Stream Deck et caméras PTZ en seront d'autres à terme. C'est le concept technique le plus englobant.

- **Lighting Profile** — Déclinaison "lumière" d'une Extension : un moteur lumière précis que l'utilisateur peut sélectionner dans les réglages (ex. MaestroDMX, ShowBuddy Active, DMXIS, QLC+, Lightkey, MIDI générique, OSC générique). C'est le terme employé côté produit/utilisateur.

- **Transport** — Canal d'envoi générique utilisé par un profil pour communiquer avec un moteur externe (MIDI, OSC, et demain Art-Net). Un Transport ne connaît jamais le moteur lumière particulier auquel il parle ; il ne fait qu'envoyer des messages selon son propre protocole.

- **Backend** — Terme technique parfois utilisé de façon interchangeable avec "Lighting Profile" ou "Extension" dans les échanges informels. Dans la documentation, préférer "Lighting Profile" (côté produit) ou "Extension" (côté architecture) pour éviter l'ambiguïté.

- **Capability** — Une capacité déclarée par un profil, indépendamment de la façon dont elle est réalisée (ex. déclencher une cue, régler une intensité, blackout, strobe). Permet de savoir ce qu'un profil sait faire sans présumer de son encodage interne.

- **VerificationState** — État de confiance d'un profil lumière. Détermine seul si les contrôles live sont autorisés pour ce profil. Valeurs (voir détail dans [ARCHITECTURE_DECISIONS.md](ARCHITECTURE_DECISIONS.md)) :
  - **`verifiedLive`** — testé en conditions réelles de concert.
  - **`experimental`** — fonctionne en test (timeline/mode test) mais non encore éprouvé en concert.
  - **`unverifiedMapping`** — documenté sur le papier mais jamais confirmé par capture réelle.
  - **`researchOnly`** — pas encore assez d'information pour produire un mapping théorique ; à l'état d'étude uniquement.

- **Timeline Cue** — Événement programmé dans la timeline du spectacle (déclenchement MIDI, OSC, ou mémo) qui se déclenche automatiquement pendant la lecture, au moment prévu.

- **Scheduler** — Point d'orchestration unique qui déclenche les Timeline Cues au bon moment pendant la lecture. Commun à tous les profils lumière ; ne contient aucune logique propre à un moteur particulier.

- **Live Controls** — Contrôles manuels utilisés pendant un concert (ex. curseur de brightness, sélecteur de cue manuel), par opposition aux cues programmées à l'avance dans la timeline. Leur disponibilité pour un profil dépend uniquement de son `VerificationState`.

- **Custom MIDI** — Profil MIDI générique permettant à l'utilisateur de définir lui-même un mapping (notes, canaux, CC) vers un moteur non prévu nativement par Velvet Show. Limité à la timeline et au mode test tant qu'il n'est pas vérifié.

- **Custom OSC** — Équivalent de Custom MIDI pour le protocole OSC : adresses et valeurs définies librement par l'utilisateur.
