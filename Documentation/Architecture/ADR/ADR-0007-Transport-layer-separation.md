# ADR-0007 — Séparation de la couche Transport

## Contexte

`MIDIEngine.swift` et `OSCEngine.swift` sont aujourd'hui déjà génériques : ni l'un ni l'autre ne connaît MaestroDMX ou un quelconque moteur lumière particulier. C'est un atout à préserver explicitement, car chaque nouveau profil lumière (ShowBuddy Active, DMXIS, etc.) pourrait être tenté d'ajouter une spécificité dans ces moteurs de transport (ex. un mode d'envoi particulier, un formatage de message dédié) plutôt que de l'encoder au niveau du profil.

## Décision

MIDI, OSC et le futur transport Art-Net restent des couches de transport strictement génériques. Un transport ne contient jamais de logique propre à un moteur lumière particulier : il reçoit des messages déjà encodés (notes, CC, adresses OSC, valeurs) et les envoie selon son propre protocole, sans interprétation métier.

## Alternatives envisagées

- **Spécialiser MIDIEngine avec des méthodes dédiées par moteur** (ex. `sendMaestroNote()`, `sendDMXISNote()`). Rejeté : recrée un couplage fort entre transport et moteur, empêche la réutilisation du transport pour un profil non prévu à l'avance, et complexifie les tests du transport lui-même.
- **Un transport par famille de moteurs** (un `MIDIEngine` pour MaestroDMX, un autre pour DMXIS). Rejeté : duplique une couche qui n'a aucune raison de différer d'un moteur à l'autre — le protocole MIDI est le même quel que soit le récepteur.

## Pourquoi cette décision

Séparer strictement l'encodage (responsabilité du profil) de l'envoi (responsabilité du transport) permet à un transport d'être testé une seule fois, indépendamment du nombre de profils qui l'utilisent, et garantit qu'ajouter un profil n'implique jamais de modifier `MIDIEngine.swift` ou `OSCEngine.swift`.

## Conséquences

- Toute demande d'évolution qui implique de modifier `MIDIEngine.swift` ou `OSCEngine.swift` pour supporter un moteur particulier doit être refusée ou repensée comme une évolution du profil, pas du transport (voir [ANTI_PATTERNS.md](../ANTI_PATTERNS.md)).
- Le futur transport Art-Net (voir [NEXT_STEPS.md](../NEXT_STEPS.md)) doit suivre le même principe dès sa conception : générique, sans connaissance d'un profil particulier.
- Voir [ADR-0006](ADR-0006-Scheduler-must-remain-generic.md) pour le principe symétrique appliqué au scheduler.
