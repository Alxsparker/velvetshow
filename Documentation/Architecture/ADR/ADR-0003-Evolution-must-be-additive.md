# ADR-0003 — L'évolution doit être additive

## Contexte

Velvet Show va devoir accueillir progressivement de nouveaux moteurs lumière, de nouveaux transports (Art-Net), et à terme de nouvelles catégories d'Extensions (mixers, vidéo, Stream Deck, caméras PTZ). Chacun de ces ajouts est une occasion de vouloir "profiter du passage" pour réorganiser, renommer ou simplifier du code existant qui fonctionne déjà en concert.

## Décision

Toute nouvelle capacité — nouveau moteur, nouveau transport, nouvelle Extension — s'ajoute au système existant. Elle ne remplace et ne modifie jamais un chemin qui fonctionne déjà. Un changement qui nécessiterait de modifier un comportement déjà en production doit être signalé et discuté séparément, jamais fait en silence dans le cadre d'un ajout de fonctionnalité.

## Alternatives envisagées

- **Autoriser des refactorings ponctuels "propres" à l'occasion de chaque nouvelle fonctionnalité.** Rejeté : c'est précisément le mécanisme par lequel un chemin fiable (MaestroDMX) se retrouve cassé sans intention malveillante — un refactoring "de bon sens" touche un chemin qui n'était pas dans le périmètre annoncé de la tâche.
- **Réserver des fenêtres de refactoring dédiées, séparées des livraisons de fonctionnalités.** Non rejeté en soi, mais hors périmètre de cette décision : si un refactoring s'avère nécessaire, il doit être proposé, documenté et validé comme une décision d'architecture à part entière (via un nouvel ADR), jamais mêlé à une fonctionnalité.

## Pourquoi cette décision

En contexte de conduite de spectacle, la fiabilité prime sur l'élégance du code (voir [PRINCIPLES.md](../PRINCIPLES.md)). Un ajout additif a un rayon d'impact borné et vérifiable ; un refactoring mêlé à une fonctionnalité a un rayon d'impact difficile à circonscrire et à tester exhaustivement.

## Conséquences

- Chaque Pull Request ou changement doit pouvoir s'expliquer comme "j'ajoute X" plutôt que "j'ajoute X et j'en profite pour changer Y".
- Le modèle Extension / Lighting Profile / Transport (voir [ADR-0004](ADR-0004-Extensions-architecture.md)) est conçu explicitement pour permettre cette additivité : un nouveau profil n'implique jamais de modifier un profil existant.
- Voir [ROADMAP_ARCHITECTURE.md](../ROADMAP_ARCHITECTURE.md) pour l'ordre des phases, qui applique ce principe : chaque phase construit sur la précédente sans la remettre en cause.
