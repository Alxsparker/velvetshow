# ADR-0005 — VerificationState

## Contexte

Les profils lumière n'ont pas tous le même niveau de confiance : MaestroDMX est vérifié en concert réel, ShowBuddy Active et DMXIS ont un mapping documenté mais non confirmé en runtime, QLC+ et Lightkey n'ont pas encore été audités. Sans mécanisme explicite, le risque est qu'un profil non fiable soit activable en contrôle live au même titre qu'un profil éprouvé, via un simple oubli ou une incohérence entre plusieurs réglages indépendants (ex. un flag "live controls" qui ne serait pas resynchronisé avec l'état réel du mapping).

## Décision

Chaque Lighting Profile porte un `VerificationState`, seule source de vérité déterminant la disponibilité des contrôles live pour ce profil :

- `verifiedLive` — vérifié en conditions réelles de concert.
- `experimental` — fonctionne en test/timeline, non encore éprouvé en concert.
- `unverifiedMapping` — mapping documenté sur le papier, jamais confirmé par capture réelle.
- `researchOnly` — pas encore assez audité pour produire même un mapping théorique.

## Alternatives envisagées

- **Un simple booléen `isLive` par profil.** Rejeté : ne distingue pas "jamais testé" de "testé mais pas en concert", ce qui empêche de guider une progression claire d'un profil vers la fiabilité.
- **Plusieurs flags indépendants (`liveControlsEnabled`, `mappingVerified`, `testModeOnly`...).** Rejeté : source d'incohérence si ces flags ne sont pas mis à jour ensemble — c'est exactement le problème identifié dans le code actuel (`lightingControlProfile` vs `maestroControlProtocol` mélangés). Un seul état, dont tout le reste dérive, élimine cette classe d'erreurs.
- **Un état continu (score de confiance numérique).** Rejeté : trop de subtilité pour une décision qui doit rester binaire en pratique ("live controls autorisés ou non") ; un enum à 4 valeurs discrètes est plus simple à auditer et à expliquer à l'utilisateur.

## Pourquoi cette décision

Un seul champ de vérité par profil rend impossible la classe d'erreurs "un profil non fiable a des contrôles live actifs par incohérence de configuration". Il rend aussi explicite, pour l'utilisateur comme pour les développeurs futurs, le chemin de progression d'un profil (voir [ARCHITECTURE_DECISIONS.md](../ARCHITECTURE_DECISIONS.md), section VerificationState).

## Conséquences

- Un profil ne peut jamais sauter directement de `researchOnly` ou `unverifiedMapping` à `verifiedLive` sans passer par un `experimental` documenté.
- L'UI (Settings, timeline, live controls) doit toujours dériver son affichage depuis ce seul champ, jamais depuis un état parallèle (voir [ANTI_PATTERNS.md](../ANTI_PATTERNS.md) : "ne jamais contourner VerificationState").
- Tout changement de statut d'un profil doit être journalisé dans [DECISION_LOG.md](../DECISION_LOG.md).
