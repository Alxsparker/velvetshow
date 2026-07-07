# ADR-0008 — La documentation précède le code

## Contexte

Velvet Show va être développé par plusieurs intervenants dans le temps (Codex, Claude, humains), potentiellement sans continuité directe de contexte entre les sessions de travail. Sans règle explicite, le risque est qu'une décision d'architecture importante soit prise implicitement dans le code (un choix de structure, un nouveau concept, une nouvelle exception) sans jamais être formalisée, ce qui oblige chaque nouvel intervenant à redécouvrir cette décision en lisant le code, avec le risque de la contredire par erreur.

## Décision

Toute décision d'architecture importante doit être documentée — au minimum dans [ARCHITECTURE_DECISIONS.md](../ARCHITECTURE_DECISIONS.md) et, si elle est structurante, sous forme d'un nouvel ADR dans ce dossier — **avant** son implémentation. Le code suit la documentation ; la documentation ne suit jamais le code.

## Alternatives envisagées

- **Documenter a posteriori, une fois le code stabilisé.** Rejeté : dans la pratique, la documentation a posteriori est reportée indéfiniment, et le code devient la seule source de vérité — ce qui oblige à le relire intégralement pour comprendre une décision, au lieu de lire un document court.
- **Ne documenter que les décisions jugées "majeures" a posteriori, au jugement de chacun.** Rejeté : le seuil de ce qui est "majeur" est subjectif et varie d'un intervenant à l'autre ; sans règle systématique, des décisions structurantes passent entre les mailles.

## Pourquoi cette décision

Cette règle est la condition de possibilité de toutes les autres : elle garantit que ce dossier `Documentation/Architecture/` reste, dans la durée, une source de vérité fiable et à jour, plutôt qu'un instantané qui se périme dès la première décision non documentée.

## Conséquences

- Avant toute nouvelle fonctionnalité structurante, se poser la question "la documentation doit-elle être mise à jour avant le code ?" (voir [MASTER_ARCHITECTURE.md](../MASTER_ARCHITECTURE.md), chapitre "Comment prendre une décision").
- Le [README.md](../README.md) rappelle explicitement cette règle : toute décision importante doit être documentée dans un ADR avant son implémentation.
- Voir [ANTI_PATTERNS.md](../ANTI_PATTERNS.md) : "ne jamais coder avant d'avoir documenté une décision d'architecture".
