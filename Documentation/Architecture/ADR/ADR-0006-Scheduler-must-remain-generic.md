# ADR-0006 — Le scheduler doit rester générique

## Contexte

Le scheduler de Velvet Show (déclenchement des cues timeline, mémos, événements MIDI/OSC programmés) est aujourd'hui déjà largement agnostique : il appelle un `dispatch(event:)`/`dispatch(oscCue:)` générique sans connaître le détail MaestroDMX. Le risque, à mesure que de nouveaux profils lumière sont ajoutés, est d'introduire des branchements spécifiques dans le scheduler ("si le profil actif est ShowBuddy Active, faire ceci en plus") pour résoudre un besoin ponctuel plus vite qu'en passant par le modèle Extension.

## Décision

Le scheduler ne connaît jamais le moteur lumière actif. Il décide uniquement *quand* une cue se déclenche et délègue entièrement le *comment* au Lighting Profile actif. Aucune exception spécifique à un moteur (MaestroDMX ou autre) ne doit jamais être introduite dans le scheduler.

## Alternatives envisagées

- **Ajouter des branchements ponctuels dans le scheduler pour des besoins spécifiques à un moteur.** Rejeté : c'est le chemin direct vers un empilement de cas particuliers non maintenable, et cela recrée exactement le couplage que le modèle Extension (voir [ADR-0004](ADR-0004-Extensions-architecture.md)) cherche à éliminer.
- **Dupliquer le scheduler par famille de profils (un scheduler "MIDI-only", un autre "OSC-only", etc.).** Rejeté : viole le principe de scheduler unique, multiplie les points de défaillance possibles pour un même comportement (déclenchement de cue), et complique les tests de non-régression.

## Pourquoi cette décision

Un scheduler générique est plus simple à tester une fois pour toutes les profils, et son comportement en concert (le chemin le plus critique du produit) reste stable indépendamment du nombre de profils ajoutés par la suite. C'est une application directe du principe de responsabilité (voir [ARCHITECTURE_DECISIONS.md](../ARCHITECTURE_DECISIONS.md) : "le scheduler ne connaît jamais le moteur").

## Conséquences

- Toute fonctionnalité qui semble nécessiter de modifier le scheduler pour un moteur particulier doit être remise en question avant d'être codée (voir le chapitre "Comment prendre une décision" dans [MASTER_ARCHITECTURE.md](../MASTER_ARCHITECTURE.md)) — c'est très probablement le signe qu'elle devrait être une capacité de profil, pas une modification du scheduler.
- Les tests de non-régression du scheduler (voir [KNOWN_RISKS.md](../KNOWN_RISKS.md)) restent valables quel que soit le nombre de profils actifs.
- Voir aussi [ANTI_PATTERNS.md](../ANTI_PATTERNS.md) : "ne jamais ajouter une exception spécifique MaestroDMX dans le scheduler".
