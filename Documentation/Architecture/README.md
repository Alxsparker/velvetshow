# Documentation/Architecture — Référence d'architecture Velvet Show

Ce dossier est **la référence d'architecture de Velvet Show**, et devient la **source de vérité du projet**. Il centralise la vision produit, les décisions déjà prises et la feuille de route pour tout développement futur (Codex, Claude, ou humain). Toute personne ou tout agent reprenant le projet doit pouvoir repartir de ce dossier sans perdre le contexte des décisions déjà actées.

Ce dossier ne contient **aucun code**. Il n'y a rien à exécuter ici — uniquement de la documentation Markdown.

**Règle absolue : toute évolution importante de Velvet Show doit commencer par une mise à jour de cette documentation avant toute implémentation.** Le code suit la documentation, jamais l'inverse. Si un changement de code ne peut pas se justifier par ce qui est écrit ici, c'est la documentation qu'il faut mettre à jour en premier — pas le code directement.

**Toute décision importante doit être documentée dans un ADR avant son implémentation** — voir le dossier [`ADR/`](ADR/) et [ADR-0008](ADR/ADR-0008-Documentation-before-code.md), qui formalise cette règle.

Les audits de logiciels tiers (ShowBuddy Active, et futurs QLC+/Lightkey/DMXIS/etc.) ne vivent plus dans ce dossier : ils sont dans [`../Research/`](../Research/), qui contient exclusivement de la recherche externe. Ce dossier `Architecture/` ne contient que la documentation propre à Velvet Show lui-même.

## Ordre de lecture conseillé

1. **[MASTER_ARCHITECTURE.md](MASTER_ARCHITECTURE.md)** — la référence absolue du projet, y compris le chapitre "Comment prendre une décision". À lire en tout premier, toujours.
2. **[PRODUCT_VISION.md](PRODUCT_VISION.md)** — pourquoi Velvet Show existe, ce qu'il doit devenir, ce qu'il ne doit jamais devenir.
3. **[PRINCIPLES.md](PRINCIPLES.md)** — les grands principes qui guident le projet sur plusieurs années.
4. **[ARCHITECTURE_DECISIONS.md](ARCHITECTURE_DECISIONS.md)** — les décisions d'architecture déjà prises et pourquoi.
5. **[ADR/](ADR/)** — le détail argumenté (contexte, alternatives, conséquences) de chaque décision structurante. À consulter quand `ARCHITECTURE_DECISIONS.md` ne suffit pas à comprendre le *pourquoi*.
6. **[ANTI_PATTERNS.md](ANTI_PATTERNS.md)** — les erreurs déjà identifiées à ne jamais reproduire.
7. **[ROADMAP_ARCHITECTURE.md](ROADMAP_ARCHITECTURE.md)** — les phases futures, dans l'ordre.
8. **[KNOWN_RISKS.md](KNOWN_RISKS.md)** — ce qu'il ne faut jamais casser, et pourquoi.
9. **[NEXT_STEPS.md](NEXT_STEPS.md)** — ce qu'il reste concrètement à faire après le retour de Codex.
10. **[GLOSSARY.md](GLOSSARY.md)** — définitions des termes utilisés dans le reste du dossier (Extension, Lighting Profile, Transport, Capability, VerificationState...). À consulter dès qu'un terme n'est pas clair.
11. **[DECISION_LOG.md](DECISION_LOG.md)** — journal chronologique, pour retrouver *quand* et *dans quel contexte* une décision a été prise.

**Puis seulement**, les documents du dossier [`Documentation/Research/`](../Research/) (audits de logiciels tiers) — à consulter en dernier, comme matériau de preuve derrière les décisions, jamais comme point de départ.

## Fonction de chaque document

| Document | Type | Rôle |
|---|---|---|
| `MASTER_ARCHITECTURE.md` | Référence absolue | Vision en une phrase, mission, piliers, architecture générale (scheduler/profils/transports/extensions), règles d'or, comment prendre une décision |
| `PRODUCT_VISION.md` | Référence produit | Vision long terme, positionnement, philosophie UX, ce que Velvet Show est et n'est pas |
| `PRINCIPLES.md` | Référence transverse | Grands principes de long terme (fiabilité, simplicité, additivité, UX avant technologie...) |
| `ARCHITECTURE_DECISIONS.md` | Spécification | Décisions d'architecture actées, modèle conceptuel (Extension, Lighting Profile, Transport, Capability, VerificationState), principe de responsabilité |
| `ADR/` (dossier) | Spécification détaillée | Un Architecture Decision Record par décision structurante : contexte, décision, alternatives envisagées, pourquoi, conséquences |
| `ANTI_PATTERNS.md` | Spécification | Erreurs connues à ne jamais reproduire |
| `ROADMAP_ARCHITECTURE.md` | Spécification | Phases 0 à 5, ordre d'implémentation recommandé, études futures |
| `KNOWN_RISKS.md` | Spécification | Risques connus et garde-fous à respecter |
| `NEXT_STEPS.md` | Spécification | Actions concrètes à mener après ce cycle de documentation |
| `GLOSSARY.md` | Référence | Définitions des termes du projet |
| `DECISION_LOG.md` | Référence | Journal chronologique des décisions |

### Classification

- **Référence absolue** : `MASTER_ARCHITECTURE.md` — fait autorité en cas de doute ou de contradiction apparente entre documents.
- **Spécifications** (décisions et plans, à faire évoluer de façon additive) : `ARCHITECTURE_DECISIONS.md`, `ADR/`, `ANTI_PATTERNS.md`, `ROADMAP_ARCHITECTURE.md`, `KNOWN_RISKS.md`, `NEXT_STEPS.md`.
- **Référence produit** : `PRODUCT_VISION.md`.
- **Référence transverse** : `PRINCIPLES.md`, `GLOSSARY.md`, `DECISION_LOG.md`.
- **Audits de logiciels tiers** : déplacés dans [`Documentation/Research/`](../Research/) — voir `RESEARCH_INDEX.md` là-bas pour le statut de chaque logiciel étudié.
  - `LIGHTING_BACKENDS_AUDIT.md` et `LIGHTING_PROFILES_PLAN.md` sont référencés dans la mission d'origine mais **n'ont été trouvés à aucun emplacement connu** au moment de la constitution de ce dossier (ni dans le projet Velvet Show, ni dans `ShowBuddyResearch`, ni ailleurs sous `Documents`). S'ils existent ou sont retrouvés plus tard, les copier dans `Documentation/Research/` sans supprimer l'original — voir [NEXT_STEPS.md](NEXT_STEPS.md).

## Règle de mise à jour

Ce dossier évolue de façon **additive** : on ajoute, on précise, on date — on ne supprime pas l'historique des décisions déjà prises. Toute nouvelle décision d'architecture significative doit être ajoutée à `ARCHITECTURE_DECISIONS.md`, documentée sous forme d'[ADR](ADR/) si elle est structurante, **et** journalisée dans `DECISION_LOG.md`.
