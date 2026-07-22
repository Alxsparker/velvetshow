# ADR-0001 — Velvet Show n'est pas un moteur lumière

## Contexte

Velvet Show pilote déjà MaestroDMX via MIDI/OSC, et doit à terme piloter d'autres moteurs lumière (ShowBuddy Active, DMXIS, QLC+, Lightkey) ainsi que du MIDI/OSC générique. Il existe une tentation naturelle, à chaque nouveau besoin lumière, de faire faire à Velvet Show une partie du travail que fait déjà un moteur lumière (calcul de rendu DMX, gestion de fixtures, patch, etc.), surtout quand un moteur tiers a un mapping incomplet ou mal documenté.

## Décision

Velvet Show ne calcule jamais de rendu DMX, ne gère jamais de fixtures, et ne remplace jamais un logiciel d'éclairage. Il **pilote** des moteurs lumière existants — il en est le point de contrôle unifié, jamais leur substitut.

## Alternatives envisagées

- **Intégrer un moteur DMX minimal dans Velvet Show** pour les cas où aucun moteur tiers n'est disponible ou mal supporté. Rejeté : cela ferait de Velvet Show un concurrent direct des moteurs qu'il est censé piloter, doublerait la surface de maintenance, et diluerait la proposition de valeur du produit.
- **Se limiter à un seul moteur (MaestroDMX) et ignorer les autres.** Rejeté : contredit la mission de Velvet Show en tant que couche universelle de pilotage (voir [PRODUCT_VISION.md](../PRODUCT_VISION.md)), et enferme le produit dans la dépendance à un seul fournisseur.

## Pourquoi cette décision

Le rôle de Velvet Show est l'orchestration du spectacle, pas la production de lumière. Cette distinction protège la simplicité du produit (voir [PRINCIPLES.md](../PRINCIPLES.md)) et évite un empilement de fonctions hors de propos avec la mission du logiciel (voir [MASTER_ARCHITECTURE.md](../MASTER_ARCHITECTURE.md), section "Ce qu'il ne doit jamais devenir").

## Conséquences

- Toute demande de fonctionnalité qui ressemble à "faire ce que fait déjà un moteur lumière" doit être refusée ou redirigée vers l'intégration d'un profil pour ce moteur, jamais implémentée en interne.
- Les capacités (`Capability`) exposées par Velvet Show restent au niveau de l'intention (déclencher une cue, régler une intensité, blackout), jamais au niveau du rendu DMX bas niveau.
- Voir aussi [ADR-0002](ADR-0002-MaestroDMX-is-the-reference.md) et [ADR-0004](ADR-0004-Extensions-architecture.md).
