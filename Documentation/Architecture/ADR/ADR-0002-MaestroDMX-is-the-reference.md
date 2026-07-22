# ADR-0002 — MaestroDMX reste la référence actuelle

## Contexte

MaestroDMX est aujourd'hui le seul moteur lumière piloté par Velvet Show en conditions réelles de concert (encodage MIDI note=cue+28 sur canal 16, CC14 pour la brightness, chemin OSC `/show/cue/index` et `/show/brightness`). D'autres moteurs (ShowBuddy Active, DMXIS, QLC+, Lightkey) sont à l'étude ou partiellement audités, mais aucun n'a été validé sur scène.

## Décision

MaestroDMX reste la référence de fiabilité du produit. C'est à son niveau d'exigence que tout nouveau profil est comparé, jamais l'inverse. Aucune évolution de l'architecture ne doit dégrader, même marginalement, le chemin MaestroDMX existant.

## Alternatives envisagées

- **Traiter tous les moteurs lumière de façon strictement symétrique dès aujourd'hui**, sans statut particulier pour MaestroDMX. Rejeté : cela reviendrait à accorder la même confiance à un chemin vérifié en concert et à des mappings non encore testés, ce qui contredit le principe de fiabilité en concert (voir [PRINCIPLES.md](../PRINCIPLES.md)).
- **Généraliser immédiatement l'architecture Extensions avant de sécuriser MaestroDMX.** Rejeté : introduirait un risque de régression sur le seul chemin qui fonctionne aujourd'hui, avant même d'avoir de garde-fous en place (voir [KNOWN_RISKS.md](../KNOWN_RISKS.md)).

## Pourquoi cette décision

MaestroDMX est un actif de confiance construit par l'usage réel en concert. Le remplacer conceptuellement par un statut générique ferait perdre cette information de fiabilité et augmenterait le risque qu'un changement d'architecture le régresse sans que cela soit immédiatement visible.

## Conséquences

- MaestroDMX est le seul profil avec le `VerificationState` `verifiedLive` au moment de la rédaction de cet ADR (voir [ADR-0005](ADR-0005-VerificationState.md)).
- Toute migration du code MaestroDMX existant (symboles `maestro*`) vers le modèle Extension doit se faire par encapsulation, jamais par réécriture (voir [KNOWN_RISKS.md](../KNOWN_RISKS.md) : "ne jamais renommer `maestro*` avant migration complète").
- Les tests de non-régression listés dans [KNOWN_RISKS.md](../KNOWN_RISKS.md) doivent être satisfaits avant toute modification touchant, même indirectement, le chemin MaestroDMX.
