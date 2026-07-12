# Velvet Show — État des lieux fonctionnel complet

**Date de l'audit :** 12 juillet 2026
**Branche analysée :** `feature/lighting-profiles-phase1`
**Dernier commit :** `0fdeeb8` — "Refine glass toolbar and resizable columns" (12 juillet 2026, 15:54)
**Fichiers non committés inclus dans l'analyse :** `VELVET SHOW/AppState.swift`, `VELVET SHOW/ConcertViews.swift`
**Méthode :** lecture intégrale du code source (≈29 600 lignes app macOS + ≈1 160 lignes Velvet Remote), de la documentation d'architecture (`Documentation/Architecture/`, `Documentation/Research/`), des deux guides utilisateur, et vérification croisée du site public velvetshow.app et de la fiche App Store Velvet Remote.
**Mission :** strictement en lecture seule. Aucun fichier modifié, aucun commit créé, aucune commande Git destructive utilisée (vérification finale en section 9).

Ce document répond au brief "Mission : état des lieux fonctionnel complet de Velvet Show". Trois documents complémentaires, dans le même dossier, approfondissent des sujets transverses trop volumineux pour être des sous-sections ici :

- [VELVET_SHOW_I18N_AUDIT_2026-07-12.md](VELVET_SHOW_I18N_AUDIT_2026-07-12.md) — audit internationalisation
- [VELVET_SHOW_TERMINOLOGY_GLOSSARY_2026-07-12.md](VELVET_SHOW_TERMINOLOGY_GLOSSARY_2026-07-12.md) — glossaire produit officiel
- [VELVET_SHOW_ECOSYSTEM_COHERENCE_2026-07-12.md](VELVET_SHOW_ECOSYSTEM_COHERENCE_2026-07-12.md) — cohérence app / Remote / site / documentation

---

## 1. Résumé exécutif

### Qu'est-ce que Velvet Show aujourd'hui ?

Velvet Show est une application macOS SwiftUI native (Swift 5, macOS 26.5, zéro dépendance externe hors frameworks Apple) qui fait déjà, en usage réel, sensiblement plus que ce que son ancien positionnement "lecteur de backing tracks" suggère. Le code confirme que le produit fonctionne aujourd'hui comme une véritable petite plateforme de conduite de spectacle pour un artiste seul ou un petit groupe : bibliothèque et setlists, lecture audio robuste avec crossfade et reprise après interruption système, timeline de mémos/cues MIDI/OSC avec scheduler générique, pilotage MaestroDMX vérifié en conditions réelles (MIDI et OSC), prompteur avec vidéo, télécommande iPhone/iPad fonctionnelle en réseau local, système de licence/trial, handoff DJ vers djay Pro, et import legacy ShowBuddy.

Le trait le plus frappant de cet audit : **l'écart entre le sérieux technique du cœur produit (audio, MIDI, OSC, persistance, architecture lumière) et l'état encore artisanal de tout ce qui touche à la présentation commerciale** (internationalisation quasi inexistante hors d'un seul écran, guide utilisateur en double version contradictoire, promesses marketing du site public largement en avance sur le code réel). Ce n'est pas un produit inachevé sur le fond ; c'est un produit dont la façade (i18n, doc, site) n'a pas suivi la vitesse du moteur.

### Niveau de maturité

**Bêta avancée à usage personnel/professionnel restreint**, pas encore prête pour une commercialisation internationale sans travail correctif ciblé. Le moteur audio/MIDI/lumière MaestroDMX est de qualité "prêt pour la scène" (gestion d'interruption système, reprise, verrouillage strict des profils lumière non vérifiés). Ce qui manque n'est pas de la robustesse technique mais de la finition produit : sécurité réseau du Remote, solidité du système de licence, cohérence documentaire, et couverture linguistique.

### Cinq fonctionnalités les plus fortes

1. **Le pipeline audio et son mécanisme de reprise après interruption système.** `AudioEngine.swift` reconstruit tout le graphe AVAudioEngine sur notification `.AVAudioEngineConfigurationChange`, annule proprement un crossfade en cours et reprend à la position exacte — un niveau de robustesse rarement observé dans une V1.
2. **Le pilotage MaestroDMX (MIDI + OSC).** Seul profil `verifiedLive`, l'encodage (note = cue+28 canal 16, CC14 brightness, `/show/cue/index`, `/show/brightness`) est vérifié bit à bit conforme à la documentation d'architecture, avec import automatique de show MaestroDMX et déduplication intelligente des événements.
3. **Le modèle `VerificationState` pour la lumière.** Mécanisme à source de vérité unique, correctement implémenté et respecté partout dans le code (aucun flag parallèle trouvé), qui verrouille honnêtement les profils non éprouvés (ShowBuddy Active, DMXIS = `unverifiedMapping`, QLC+/Lightkey = `researchOnly`) plutôt que de laisser l'utilisateur s'exposer à un risque de scène.
4. **Le scheduler timeline générique et le comportement seek/rearm.** Un point d'orchestration unique, sans branche spécifique à un moteur, avec un mécanisme "déjà tiré / réarmé" qui empêche exactement le rejouage rétroactif de MIDI en cas de scrub arrière — comportement documenté et vérifié conforme.
5. **La persistance et la sécurité des données utilisateur.** `VelvetShowStore` (debounce 0,4 s, fichier `.bak`, migrations de schéma idempotentes v1→v3), séparation stricte lecture-seule de `ShowBuddy.db` (confirmée par absence totale d'écriture SQL dans tout le code), Velvet Trash avec restauration — aucune perte de données destructrice trouvée dans les chemins normaux.

### Cinq zones les plus fragiles

1. **Sécurité réseau de Velvet Remote.** Protocole TCP en clair, sans TLS, sans authentification, sur un port fixe (7777) annoncé publiquement par Bonjour. N'importe quel appareil sur le même réseau (Wi-Fi de festival, de salle non maîtrisée) peut envoyer des commandes de lecture à l'app. Critique avant toute commercialisation dans des lieux à réseau partagé.
2. **Système de licence.** L'API LemonSqueezy est appelée sur l'endpoint `/validate` plutôt que `/activate` — probable absence de limite d'activations réelle côté serveur, aucune re-vérification périodique, contournement trivial du trial par suppression d'une entrée Keychain.
3. **Internationalisation quasi inexistante.** Sur l'application macOS entière, seul l'écran `MidiSettingsView` (un seul fichier sur trente-deux) bénéficie d'une vraie localisation FR/EN — et même là, 9 messages d'erreur sont cassés par une incohérence de clé. Partout ailleurs (bibliothèque, concert, prompteur, licence, update, onboarding, tooltips), le texte est figé, dans un mélange d'anglais et de français en dur. Voir le document dédié.
4. **Deux guides utilisateur contradictoires et une documentation technique (`CLAUDE.md`) obsolète.** Le vocabulaire, les raccourcis affichés, et même le comportement du raccourci panic (⌘⇧P) divergent entre les deux guides ; `CLAUDE.md` sous-estime `AppState.swift` d'un facteur 3 et surestime `ContentView.swift` d'un facteur 3 par rapport à la réalité actuelle du code.
5. **Écart marketing/réalité sur le site public.** Le site annonce une compatibilité avec myDMX, Zero 88, Resolume, Companion, OBS et QLab qui n'existe dans aucune ligne de code, décrit un "Apple Continuity" pour le prompteur iPad qui n'est pas le mécanisme réellement implémenté (Bonjour/TCP), et affirme que PANIC coupe l'audio alors que le code et le guide utilisateur confirment explicitement que non. Voir [VELVET_SHOW_ECOSYSTEM_COHERENCE_2026-07-12.md](VELVET_SHOW_ECOSYSTEM_COHERENCE_2026-07-12.md).

### Ce qui distingue réellement Velvet Show de ShowBuddy Setlist

- **Une seule app au lieu de deux** (ShowBuddy Setlist + ShowBuddy Active séparés, $318 à eux deux) pour le cœur setlist + pilotage lumière MaestroDMX.
- **OSC natif** en plus du MIDI, avec bibliothèque d'événements réutilisables et test manuel intégré — absent de ShowBuddy Setlist.
- **Télécommande iPhone/iPad native, gratuite, avec découverte automatique**, à comparer à l'écosystème ShowBuddy qui n'a pas d'équivalent direct documenté dans cet audit.
- **Import direct des shows MaestroDMX** avec déduplication intelligente — une fonctionnalité de confort absente des outils legacy.
- **Un modèle de confiance explicite (`VerificationState`)** pour la lumière, qui n'a pas d'équivalent connu chez la concurrence : le produit refuse activement d'activer un contrôle live non vérifié plutôt que de laisser l'utilisateur découvrir le problème sur scène.

Le vrai différenciateur n'est donc pas une fonctionnalité isolée, mais la **combinaison audio + MIDI + OSC + lumière + remote dans un seul programme avec un mécanisme de fiabilité explicite** — à condition que la sécurité réseau et la licence soient corrigées avant d'exposer cela à des acheteurs inconnus.

---

## 2. Inventaire fonctionnel complet

Statuts utilisés : **Fonctionnel** · **Fonctionnel mais non testé** · **Partiel** · **Expérimental** · **Présent mais non branché** · **Obsolète** · **À vérifier**.

### 2.1 Bibliothèque et shows

| Fonctionnalité | Statut | UI disponible | Runtime branché | Persistance | Confiance | Fichiers principaux |
|---|---|---|---|---|---|---|
| Import audio (MP3/WAV/AIFF/M4A) | Fonctionnel | Oui | Oui | JSON | Élevée | `AudioFileOperations.swift:31-313`, `AppState.swift:4245-4308` |
| Import Velvet autonome (1er lancement, sans ShowBuddy) | Fonctionnel | Oui (`VelvetWelcomeView`) | Oui | JSON | Élevée | `ShowLibraryViews.swift:451-457`, `AppState.swift:4150-4169` |
| Suppression audio — Velvet Trash (soft delete) | Fonctionnel | Oui | Oui | Snapshot restaurable | Élevée | `VelvetTrashView.swift`, `AppState.swift:6619-6689` |
| `deleteVelvetTrack` (suppression physique immédiate, sans confirmation) | **Présent mais non branché — dette dangereuse** | Aucune (0 appelant) | Non | Détruirait le fichier sans snapshot si jamais branché | Élevée | `AppState.swift:4188-4199` |
| ShowBuddy.db jamais modifiée | Fonctionnel | — | Oui (`SQLITE_OPEN_READONLY` exclusif, 0 écriture SQL trouvée) | — | Élevée | `ShowBuddyDatabase.swift:63-96` |
| Organisation des shows (créer/renommer/couleur/notes/dupliquer/supprimer) | Fonctionnel | Oui | Oui | JSON | Élevée | `ShowLibraryViews.swift:106-339`, `AppState.swift:6297-6382` |
| Réorganisation des morceaux (drag & drop setlist + Quick Library) | Fonctionnel | Oui | Oui | JSON | Élevée | `ConcertViews.swift:3188-3223`, `AppState.swift:6441-6490` |
| Recherche (Track Library, Show Library, Quick Library) | Fonctionnel | Oui (⌘F) | Oui | — | Élevée | `ContentView.swift:1174-1246`, `ConcertViews.swift:1880-1918` |
| Navigation (catégories, sidebar shows fusionnée ShowBuddy+Velvet) | Fonctionnel | Oui | Oui | — | Élevée | `ShowLibraryViews.swift:60-252` |
| Persistance (debounce 0,4 s, `.bak`, migrations v1→v3) | Fonctionnel | Statut visible (pastille save) | Oui | `VelvetShowState.json` | Élevée | `VelvetShowStore.swift:117-131,299-411,586-633` |
| Perte silencieuse si JSON **et** `.bak` corrompus tous les deux | Partiel — angle mort | Aucun avertissement dédié | Oui (réinitialise silencieusement) | — | Élevée | `VelvetShowStore.swift:379-391` |
| Gestion des métadonnées (titre, genre, couleurs) | Fonctionnel | Oui | Oui | JSON | Élevée | `AppState.swift:4171-4186,4627-4630`, `ShowLibraryViews.swift:519-644` |
| Import vidéo associé au morceau (API) | **Présent mais non branché** | Non (aucun bouton d'import) | API complète, 0 appelant UI | JSON si appelée | Élevée | `AppState.swift:1856-1905` |
| Remap dossier MediaFiles + sécurité bookmark | Fonctionnel | Oui (sheet 3 phases) | Oui | Backup daté + bookmark security-scoped | Élevée | `MediaLibraryRemapView.swift`, `AppState.swift:2790-2961` |
| Remplacement physique de fichier audio + backup auto | Fonctionnel | Oui | Oui | `AudioBackups/` horodaté | Élevée | `AudioFileOperations.swift:325-598` |

### 2.2 Playback

| Fonctionnalité | Statut | UI disponible | Runtime branché | Persistance | Confiance | Fichiers principaux |
|---|---|---|---|---|---|---|
| Play / Pause / Stop | Fonctionnel | Oui (Espace, ⌘., boutons, remote) | Oui | — | Élevée | `AudioEngine.swift:457-674`, `AppState.swift:3420-3725` |
| Morceau suivant / précédent | Fonctionnel | Oui (⌘→/⌘←) | Oui | — | Élevée | `AppState.swift:3919-3923` |
| Seek (scrub waveform, 3 modes) | Fonctionnel | Oui | Oui | — | Élevée | `AudioEngine.swift:530-596` |
| Crossfade FADE (1,2 s) / SLOW FADE (3,0 s) | **Présent mais non branché à l'UI** — moteur complet mais exclu du picker utilisateur | Non | Oui si atteint par code | UserDefaults (compat) | Élevée | `AppState.swift:61-95` (`isAvailable`), `AudioEngine.swift:807-904` |
| Crossfade FILTER (2,0 s, sweep passe-bas 20kHz→800Hz) | Fonctionnel | Oui, seul avec AUTOMIX dans le picker | Oui | idem | Élevée | `AudioEngine.swift:1109-1133` |
| AUTOMIX (crossfade BPM-aware, **non committé**) | Fonctionnel mais non testé | Oui, mais accessible uniquement en remplacement manuel (pas AUTO SHOW, pas ⌘→/←, pas remote) | Oui | idem | Moyenne | `AppState.swift:3744-3765` (diff non committé) |
| ECHO | Expérimental — moteur complet, exclu de l'UI | Non | Oui si atteint | idem | Élevée | `AudioEngine.swift:736-784` |
| BACKSPIN | **Obsolète / jamais implémenté** — tombe dans un stop+reload générique | Non | Non (placeholder "bientôt") | — | Élevée | `AppState.swift:3614-3632` |
| AUTO SHOW (enchaînement auto) | Partiel | Oui (toggle) | Oui pour `.autoStop/.smart/.autoNextFilter` ; **no-op silencieux pour `.autoNextFade/.autoNextSlowFade`** | UserDefaults | Élevée | `AppState.swift:5257-5271` |
| `TrackEndBehavior` par morceau | **Présent mais non branché** — lu, jamais écrit par une UI | Non | Lecture seule | JSON (`endBehaviorBySetElementID`) | Élevée | `AppState.swift:5223` |
| Lecture FOH | **Absent** — aucune référence trouvée dans tout le dépôt | — | — | — | Élevée (recherche exhaustive) | — |
| Gestion des erreurs audio | Fonctionnel | Oui (`lastError`) | Oui | — | Élevée | `AudioEngine.swift:55-69` |
| Panic (audio) | **Absent** — seul un "Panic Prompter" existe, sans effet sur l'audio | — | — | — | Élevée | Voir section Prompteur |
| Reprise après interruption système | Fonctionnel | Automatique | Oui (`.AVAudioEngineConfigurationChange`) | — | Élevée | `AudioEngine.swift:320-328,1141-1206` |
| Détection BPM automatique | Fonctionnel | Oui (bouton batch) | Oui (autocorrélation, correction d'octave) | JSON (`tempo`) | Élevée (algo), Moyenne (précision non mesurable en lecture seule) | `BPMDetector.swift` |
| Volume par morceau (pas 1 dB, plage [-12,+12] dB) | Fonctionnel | Oui | Oui | JSON | Élevée | `ConcertViews.swift:339-359`, `Models.swift:536-537` |
| Trim (in/out) | Fonctionnel | Oui | Oui | JSON, fallback ShowBuddy | Élevée | `AudioEngine.swift:97-153,411-423` |
| Normalisation loudness (LUFS, EBU R128/BS.1770-4) | Fonctionnel | Oui | Oui | JSON | Élevée | `LoudnessAnalyzer.swift` |

### 2.3 Timeline / MIDI / OSC

| Fonctionnalité | Statut | UI disponible | Runtime branché | Persistance | Confiance | Fichiers principaux |
|---|---|---|---|---|---|---|
| Mémos (édition, position, durée) | Fonctionnel | Oui | Oui | JSON | Élevée | `TimelineEditor.swift:1078-1153,2067-2171` |
| Mémo court remote (max 28 car., fallback auto) | Fonctionnel | Oui, mais aucune limite imposée sur le champ `shortName` lui-même | Oui | JSON | Élevée | `AppState.swift:477`, `TimelineEditor.swift:2100` |
| Cues MIDI (Note On/Off, PC, CC) | Fonctionnel | Oui | Oui | JSON | Élevée | `MidiSettingsView.swift:678-724,2056-2267` |
| Cues OSC | Fonctionnel | Oui, avec test manuel | Oui | JSON | Élevée | `TimelineEditor.swift:2483-2660` |
| Seek/rearm — pas de rejouage MIDI en arrière | Fonctionnel | — | Oui (`realignFiredTriggers`) | — | Élevée | `AppState.swift:5465-5501` |
| Rest Cue (délai configurable, 4 déclencheurs) | Fonctionnel | Oui | Oui | UserDefaults | Élevée | `AppState.swift:2366-2444` |
| Import fichier MIDI standard (.mid) | Fonctionnel | Oui | Oui (AudioToolbox) | JSON | Élevée | `MidiSettingsView.swift:928-1197` |
| Import MaestroDMX (→ MIDI et → OSC) | Fonctionnel | Oui, 2 sheets dédiées | Oui, dédup par empreinte | JSON | Élevée | `MidiSettingsView.swift:1201-1900` |
| Import tiers Wolfmix / QLab / Lightkey | **Présent mais non branché** — boutons visibles, désactivés "(soon)" | Oui (visible, désactivé) | Non | — | Élevée | `MidiSettingsView.swift:811-822` |
| Sortie MIDI (sélection destination) | Fonctionnel | Oui | Oui | UserDefaults | Élevée | `MidiSettingsView.swift:132-152` |
| MIDI input / footswitch / MIDI Learn / bindings | Fonctionnel | Oui | Oui, générique (Note On/CC/PC/Aftertouch/Pitch Bend) | JSON | Élevée | `MidiSettingsView.swift:3350-3471`, `AppState.swift:3927-3985` |
| Journal MIDI (`midiLog`) | **Présent mais non branché** — alimenté, jamais affiché | Non | Écriture oui, lecture UI non | Non persisté | Élevée | `AppState.swift:5525` et alentours |
| Filtrage Note Off | Fonctionnel | — | Oui | — | Élevée | `MIDIEngine.swift:266-268` |
| Avance d'envoi (compensation latence, ex. -50 à -300 ms) | Fonctionnel | Oui | Oui | UserDefaults | Élevée | `AppState.swift:907-913` |
| Émission OSC (host/port, types int/float/string/bool) | Fonctionnel | Oui | Oui | — | Élevée | `OSCEngine.swift` |
| Réception OSC | **Absent, assumé volontairement** ("sender-only en V1") | — | Non | — | Élevée | `OSCEngine.swift:16-17` |
| Scheduler générique (point d'orchestration unique) | Fonctionnel, avec réserve mineure de nommage | — | Oui | — | Élevée | `AppState.swift:5279-5463` — voir §5 |

### 2.4 Lumière (voir aussi le chapitre dédié dans le document Écosystème)

| Profil / Fonctionnalité | Statut | `VerificationState` réel | UI | Live-ready | Fichiers principaux |
|---|---|---|---|---|---|
| MaestroDMX MIDI (note=cue+28 ch16, CC14 brightness) | Fonctionnel | `verifiedLive` | Oui | Oui | `AppState.swift:958-1019,1190-1202` |
| MaestroDMX OSC (`/show/cue/index`, `/show/brightness`) | Fonctionnel | `verifiedLive` | Oui | Oui | `AppState.swift:1151-1221` |
| Master Brightness (curseur live) | Fonctionnel | dépend du profil | Oui, libellé exact "MASTER BRIGHTNESS" | Oui pour `verifiedLive` seulement | `ConcertViews.swift:651-778` |
| Manual cue picker | Fonctionnel | idem | Oui | Oui pour `verifiedLive` seulement | `ConcertViews.swift:848-961` |
| `VerificationState` (enum à 4 valeurs, source de vérité unique) | Fonctionnel | — | Badge coloré partout | — | `AppState.swift:958-989` |
| Generic MIDI ("Custom MIDI") | Présent mais non branché — pas de mapping arbitraire réel | `experimental` | Sélectionnable, sans UI de mapping | Non | `AppState.swift:999,1011,1020,1033-1034` |
| Generic OSC ("Custom OSC") | Présent mais non branché — idem | `experimental` | idem | Non | `AppState.swift:1000,1012,1020,1035-1036` |
| ShowBuddy Active | Présent mais non branché — verrouillé, aucun code d'envoi | `unverifiedMapping` | Oui, badge "Mapping Unverified" | Non | `AppState.swift:995,1007,1022,1037-1038` |
| DMXIS | Présent mais non branché — idem | `unverifiedMapping` | Oui, verrouillé | Non | `AppState.swift:996,1008,1022,1039-1040` |
| QLC+ | Présent mais non branché — aucun code | `researchOnly` | Sélectionnable, aucun envoi possible | Non | `AppState.swift:997,1009,1024,1041-1042` |
| Lightkey | Présent mais non branché — idem | `researchOnly` | idem | Non | `AppState.swift:998,1010,1024,1043-1044` |
| Art-Net | Absent, conforme à la doc ("futur") | n/a | Absent | n/a | Recherche exhaustive négative |
| Modèle Extension/Transport/Capability (abstraction polymorphe) | **N'existe pas encore dans le code — attendu, conforme à la roadmap Phase 3** | — | — | — | Tout le pilotage réel reste codé en dur pour MaestroDMX |

**Point capital vérifié** : le problème historique documenté par ADR-0005 (deux flags concurrents `lightingControlProfile`/`maestroControlProtocol`) **a été corrigé** — aucun flag parallèle n'a été retrouvé dans le code actuel, `VerificationState` est bien l'unique source de vérité de la disponibilité des contrôles live. Le scheduler et les transports (`MIDIEngine.swift`, `OSCEngine.swift`) restent strictement génériques, sans référence à un moteur lumière particulier — conforme à ADR-0006/0007.

**Diff non committé** : contrairement à ce que suggérait le contexte de mission, les modifications non committées sur `AppState.swift`/`ConcertViews.swift` ne touchent **pas** le domaine lumière. Elles portent exclusivement sur l'ajout du mode de transition **AUTOMIX** (crossfade BPM-aware), voir §2.2. Le domaine lumière est stable et entièrement contenu dans le commit déjà validé `3345dd2`.

### 2.5 Prompteur et vidéo

| Fonctionnalité | Statut | UI disponible | Runtime branché | Persistance | Confiance | Fichiers principaux |
|---|---|---|---|---|---|---|
| Affichage paroles/mémos synchronisé | Fonctionnel | Oui | Oui | JSON | Élevée | `PrompterView.swift:99-105,239-251` |
| Fenêtre Prompter séparée (2ᵉ écran) | Fonctionnel | Oui (bouton toolbar) | Oui | — | Élevée | `VELVET_SHOWApp.swift:94` |
| Thème Prompter indépendant du thème principal | Fonctionnel | Oui | Oui | Séparée | Élevée | `ThemeManager.swift:16-102` |
| Statut pill (2ᵉ écran détecté / prompter ouvert-fermé) | Fonctionnel | Oui, 4 états exacts | Oui | — | Élevée | `ContentView.swift:616-688` |
| PANIC / "Backup Prompter" — panneau intégré, PAS une fenêtre séparée | Fonctionnel, mais nom trompeur en communication | Oui (⌘⇧P, bouton 🚨) | Oui | Non persisté | Élevée | `AppState.swift:1567-1570`, `ShowLibraryViews.swift:852-899` |
| AirPlay / Sidecar | Partiel — détection générique `NSScreen.screens.count>1`, aucune API Apple dédiée | — | Partielle | — | Élevée | `AppState.swift:1510,1545-1561` |
| Import vidéo mp4/mov/m4v (association à un morceau) | **Présent mais non branché** — API complète (`setVideo`/`removeVideo`), 0 appelant UI | Non (icône 🎥 lecture seule) | API oui, UI non | JSON si appelée | Élevée | `AppState.swift:1859-1905` |
| Lecture/pause/stop/seek vidéo | Fonctionnel (si vidéo présente via legacy) | Indirect | Oui | — | Élevée | `VideoPlayerController.swift:56-81` |
| Synchronisation audio/vidéo | Fonctionnel mais non testé — sync au niveau commande, **pas d'horloge commune**, dérive possible non corrigée | — | Oui, sans garde-fou de dérive | — | Élevée (limite documentée dans le code même) | `VideoPlayerController.swift:6-16` |
| Affichage vidéo dans le Prompter (Mac) | Fonctionnel | Oui | Oui | — | Élevée | `PrompterView.swift:139-162` |
| Vidéo sur le Prompteur distant iPad | **Absent par conception** (`#if os(macOS)`), pas un bug | Non | Non | — | Élevée | `PrompterView.swift:139-141` |
| Persistance vidéo | Fonctionnel | — | Oui | JSON | Élevée | `VelvetShowStore.swift:437-458` |

**Terminologie tranchée** : le raccourci ⌘⇧P **n'ouvre pas** une fenêtre "Prompter panic" séparée (contrairement à ce que décrit le guide "0.9 Beta") — il bascule un booléen qui affiche un panneau **"BACKUP PROMPTER"** intégré à la fenêtre principale (confirmé par le texte exact trouvé dans le code, cohérent avec `VelvetShow_UserGuide.md`, pas avec `Documentation/velvet-show-0.9-beta-user-guide.md`). Voir le document Terminologie pour le détail complet.

### 2.6 Velvet Remote (iPhone/iPad + serveur Mac)

| Fonctionnalité | Statut | UI disponible | Runtime branché | Cohérence Mac↔Remote | Confiance | Fichiers principaux |
|---|---|---|---|---|---|---|
| Découverte Bonjour (`_velvetshow._tcp`) | Fonctionnel | Oui | Oui (NWBrowser/NWListener) | Cohérent | Élevée | `VelvetRemoteClient.swift:83-126`, `VelvetRemoteServer.swift:19-63` |
| Reconnexion automatique | Fonctionnel | Implicite | Oui, backoff exponentiel **côté serveur Mac uniquement** (1→2→4→8→16→30s) ; client iOS = watchdog 10s sans backoff | Bonne | Élevée | `VelvetRemoteServer.swift:143-163`, `VelvetRemoteClient.swift:68-76,144-176` |
| Play/Pause, Next | Fonctionnel | Oui | Oui | Cohérent | Élevée | `RemoteControlView.swift:171-176`, `AppState.swift:417-454` |
| `prioritizeNext:<id>` (sans démarrer la lecture) | Fonctionnel | Oui (iPhone) | Oui | Cohérent avec la doc | Élevée | `AppState.swift:456-464,2236-2250` |
| Commande `stop` | **Présent mais non branché** — dans le protocole (commentaire), jamais géré | Non | Non (`default` → "Unknown command") | — | Élevée | `VelvetRemoteProtocol.swift:47` |
| Commande `panic` depuis le Remote | **Absent** — n'existe pas, malgré la présence du mot dans le protocole documenté | Non | Non | — | Élevée | idem |
| Badge de connexion (Wi-Fi/USB/déconnecté) | Fonctionnel | Oui | Oui | Cohérent | Élevée | `RemoteConnectionBadge.swift:20-35` |
| Timeline distante (iPad) | Fonctionnel | Oui | Oui | **Réimplémentation indépendante**, pas de code partagé avec la timeline Mac | Moyenne | `RemoteTimelineView.swift` |
| Prompteur distant (iPad) | Fonctionnel | Oui | Oui | **Fort** — réutilise littéralement le même composant SwiftUI que le Mac | Élevée | `RemotePrompterView.swift:43-58` |
| Indicateur +2 morceaux | Fonctionnel sur iPhone, **absent sur iPad** malgré la donnée disponible | Partiel | Oui côté données | Écart iPhone/iPad | Élevée | `RemoteControlView.swift:76-86` |
| USB prioritaire sur Wi-Fi | Fonctionnel | Oui (badge) | Oui | Cohérent | Élevée | `VelvetRemoteClient.swift:326-330` |
| **Sécurité réseau (auth/chiffrement)** | **Absent — risque critique roadmap** | — | TCP en clair, sans TLS, sans jeton | — | Élevée | Recherche exhaustive négative sur `NWProtocolTLS` |
| **Compatibilité de version protocole** | **Absent** — aucun champ de version, échec silencieux (`try?`) si divergence | — | — | — | Élevée | `VelvetRemoteProtocol.swift` (fichier entier) |
| Commandes lumière depuis le Remote | Absent, conforme à la roadmap ("Coming soon" sur le site) | — | — | — | Élevée | Recherche exhaustive négative |

### 2.7 BPM

| Fonctionnalité | Statut | Détail |
|---|---|---|
| Détection automatique | Fonctionnel | Autocorrélation sur flux d'onsets 60-190 BPM + correction d'octave, `BPMDetector.swift` |
| Fichiers compatibles | Fonctionnel | Tout fichier audio importé (MP3/WAV/AIFF/M4A) |
| Déclenchement | Fonctionnel | Bouton batch "analyser BPM manquants" |
| Persistance | Fonctionnel | `tempo` sur `VelvetTrack`, overrides possibles |
| Précision | Non mesurable en lecture seule de code | À valider par test terrain |
| Impact UI | Fonctionnel | Alimente AUTOMIX (tolérance ±8 %) |
| Tap-tempo manuel | **Non trouvé dans le code** malgré la promesse du site public (voir document Écosystème) | — |

### 2.8 DJ Handoff

| Fonctionnalité | Statut | Détail |
|---|---|---|
| Lancement djay Pro | Fonctionnel | `NSWorkspace.openApplication` + AppleScript ciblé |
| Autres apps (Spotify, Apple Music, Traktor) | Fonctionnel | Même mécanique, liste de bundle IDs + scan filesystem fallback |
| Cible personnalisée | Fonctionnel | Champs Bundle ID + nom d'app dans Settings |
| Cas app absente | Fonctionnel | `HandoffError.notInstalled`, erreur générique affichée |
| Fallback clavier (3 couches) | Fonctionnel | AppleScript ciblé → AppleScript System Events → CGEvent HID |
| Sandbox / permissions | **À vérifier — risque de crash non testé** | Entitlement `com.apple.security.automation.apple-events` présent, mais aucune clé `NSAppleEventsUsageDescription` trouvée dans le projet ; sur macOS moderne cela provoque généralement un crash au premier envoi d'Apple Event. Non testé à l'exécution (mission lecture seule). |

### 2.9 Trial et licence

| Fonctionnalité | Statut | Détail |
|---|---|---|
| Trial actif (30 jours) | Fonctionnel | Ancré Keychain (`app.velvetshow.trial`), migration depuis UserDefaults |
| Expiration | Fonctionnel | Blocage total (`BetaExpiredView` plein écran) |
| Accès fonctions pendant trial | Fonctionnel | 100 % débloqué, aucune restriction de fonctionnalité |
| Activation licence (LemonSqueezy) | Fonctionnel mais non testé | **Endpoint `/validate` utilisé au lieu de `/activate`** — voir §6, risque commercial |
| Stockage | Fonctionnel | Keychain (`app.velvetshow.license`) |
| Risque de contournement | **Élevé** | Suppression Keychain = trial réinitialisable à volonté ; pas de re-vérification serveur après activation |

### 2.10 Update Checker

| Fonctionnalité | Statut | Détail |
|---|---|---|
| Vérification GitHub Releases | Fonctionnel | `api.github.com/repos/Alxsparker/velvetshow/releases/latest`, sans auth |
| Comparaison de version | Fonctionnel | Semver maison, tolère absence de patch |
| Badge + sheet | Fonctionnel | `UpdateAvailableBadge`/`UpdateAvailableSheet` |
| Absence réseau | Fonctionnel | Échec silencieux, dernier état en cache (UserDefaults, 6h) |
| Téléchargement | Fonctionnel mais partiel | Ouvre la page GitHub Release dans le navigateur — pas d'installation automatique |
| Sécurité | Non applicable au risque classique | Aucun binaire exécuté par l'app elle-même ; Gatekeeper/notarisation prennent le relais après téléchargement navigateur |

### 2.11 Import / export legacy

| Fonctionnalité | Statut | Détail |
|---|---|---|
| Import ShowBuddy (ouverture DB) | Fonctionnel | Charge Sets/AudioFiles/LightShows/Memos/MIDI, lecture seule |
| Import trims ShowBuddy → Velvet | Fonctionnel | Migration idempotente, ne touche jamais un trim Velvet déjà personnalisé |
| Import MaestroDMX (MIDI + OSC) | Fonctionnel | Voir §2.3 |
| Robustesse face à un schéma ShowBuddy.db incomplet/ancien | À vérifier | Échec total (pas de dégradation partielle) si une requête référence une colonne absente |

### 2.12 Configuration et préférences

Réglages confirmés persistés et fonctionnels : destinations MIDI, profil lumière + `VerificationState`, host/port OSC, thème principal et thème Prompter indépendants, dossier MediaFiles (bookmark security-scoped), cible DJ Handoff, Show Safety, Rest Cue, avance d'envoi MIDI, dernier effet de transition. Aucune incohérence de persistance détectée dans ce périmètre.

---

## 3. Parcours utilisateur réels

### 1. Créer un show et importer des morceaux
**Fonctionne.** Import audio → catégorisation → création de show → glisser-déposer dans la setlist, tout est branché et persisté. Point de friction mineur : deux listes de formats audio légèrement différentes selon le point d'entrée (import "Velvet autonome" vs import via `AudioImportSheet`/remplacement), sans documentation centralisée du filtre exact.

### 2. Préparer un morceau avec mémos et cues
**Fonctionne bien.** Timeline riche (mémos, cues MIDI, cues OSC, trim), édition directe sur la forme d'onde. Point d'incertitude : le "Lighting Cue" du panneau mémo ne liste que les événements MaestroDMX (`maestroMidiEvents()`), pas les événements MIDI génériques — limitation UI non documentée.

### 3. Lancer un concert
**Fonctionne**, avec un vrai souci de fiabilité scénique (Show Safety double-clic, Repeat Mode avec bannière, historique, queue prioritaire). Friction potentielle : l'utilisateur qui active le picker de transition découvrira que FADE/SLOW FADE, pourtant présentés comme disponibles par le guide "0.9 Beta", sont en réalité invisibles — seuls FILTER et AUTOMIX (récent, non committé) sont sélectionnables.

### 4. Piloter MaestroDMX
**Fonctionne très bien**, c'est le parcours le plus abouti de tout l'audit : import du show, déclenchement automatique via timeline, contrôle manuel du brightness et du cue picker, tout vérifié conforme à la documentation d'architecture.

### 5. Utiliser un footswitch MIDI
**Fonctionne**, MIDI Learn et bindings génériques opérationnels, filtrage Note Off pour éviter le double-déclenchement.

### 6. Utiliser le Prompter vidéo
**Ne fonctionne pas en pratique** — le mécanisme d'association vidéo↔morceau existe entièrement côté moteur mais n'a **aucun point d'entrée UI** pour importer une vidéo. Un utilisateur suivant scrupuleusement le guide ne trouvera nulle part le bouton pour attacher une vidéo à un morceau.

### 7. Passer en DJ handoff
**Fonctionne selon la lecture du code**, avec une architecture de fallback à trois niveaux impressionnante — mais un doute sérieux et non testé (`NSAppleEventsUsageDescription` potentiellement absente) fait peser un risque de crash au premier usage réel, à vérifier en priorité avant toute démonstration publique de cette fonctionnalité vedette.

### 8. Utiliser Velvet Remote
**Fonctionne** pour le cas d'usage principal (play/pause/next/prioritize), avec un vrai soin apporté au prompteur distant (composant partagé avec le Mac). Friction : aucun bouton Stop ni Panic sur le Remote alors que le protocole les mentionne en commentaire ; l'utilisateur qui cherche à couper le son depuis son iPhone en cas de problème ne le pourra pas.

### 9. Revenir après un crash ou redémarrage
**Fonctionne** dans le cas simple (fichier `.bak` chargé automatiquement si le JSON principal est corrompu). Angle mort : si les deux fichiers sont corrompus simultanément, l'app redémarre silencieusement à vide sans avertissement clair — l'utilisateur pourrait croire avoir perdu ses données sans indication du système sur ce qui s'est passé.

---

## 4. Fonctionnalités invisibles ou sous-exploitées

- **AUTOMIX** (crossfade BPM-aware) — fonctionnalité neuve et de qualité, mais son intégration est partielle : elle ne s'applique qu'au remplacement manuel, pas à AUTO SHOW, pas aux raccourcis clavier, pas au Remote. Rien dans le code ne documente si c'est un choix de scope Phase 1 ou un oubli.
- **Import vidéo associé à un morceau** — moteur complet, aucune UI. C'est la fonctionnalité "présente mais invisible" la plus nette de tout l'audit.
- **Journal MIDI (`midiLog`)** — alimenté à chaque envoi, jamais affiché à l'utilisateur. Une vue de diagnostic existe en germe mais n'a jamais été construite.
- **Import Wolfmix / QLab / Lightkey (fichiers MIDI/show)** — boutons visibles dans l'UI mais désactivés "(bientôt)" ; le site public promet pourtant une compatibilité QLC+/Resolume/Companion/OBS bien plus large que ce que même ces boutons désactivés laissent entrevoir.
- **`TrackEndBehavior` par morceau** (fondu / fondu lent / filtre / smart en fin de morceau) — persisté, lu, jamais réglable par l'utilisateur.
- **Sélecteur de genre en mode concert** — désactivé volontairement dans le code (`if false`), avec un commentaire explicite indiquant comment le réactiver.

---

## 5. Écarts entre code, UI et documentation

| Écart | Où | Détail |
|---|---|---|
| `CLAUDE.md` sous-estime `AppState.swift` (~2200 documentées vs 6690 réelles) et surestime `ContentView.swift` (~5400 documentées vs 1902 réelles) | `CLAUDE.md:34,42` | Le fichier n'a pas été mis à jour depuis une refonte structurelle majeure. |
| `CLAUDE.md` ne mentionne ni la fenêtre Settings (4ᵉ fenêtre réelle) ni le système `LightingControlProfile`/`VerificationState` | `CLAUDE.md` | Architecture significative absente de la doc de référence développeur. |
| Les deux transitions FADE/SLOW FADE sont présentées comme disponibles par le guide "0.9 Beta" mais exclues du picker UI réel | `Documentation/velvet-show-0.9-beta-user-guide.md:158-162` vs `AppState.swift:61-66` | Décision produit non répercutée dans le guide. |
| Le raccourci ⌘⇧P est décrit comme ouvrant une fenêtre "Prompter panic" séparée par le guide "0.9 Beta", alors qu'il bascule un panneau intégré "Backup Prompter" | `Documentation/velvet-show-0.9-beta-user-guide.md` vs `AppState.swift:1567-1570` | Confirmé par le guide racine (`VelvetShow_UserGuide.md`), qui est fidèle au comportement réel. |
| Le modèle Extension/Transport/Capability est décrit dans `GLOSSARY.md`/`ARCHITECTURE_DECISIONS.md` comme si l'abstraction existait déjà en code | `Documentation/Architecture/GLOSSARY.md` | N'existe pas encore ; conforme à la roadmap (Phase 3 non atteinte), mais peut induire en erreur un lecteur qui ne croise pas avec `ROADMAP_ARCHITECTURE.md`. |
| Le point de dispatch MIDI central porte le nom `maestroDestination`/`maestroDestinationID` alors qu'il est censé être générique | `AppState.swift:921,5533` | Écart mineur avec l'esprit d'ADR-0006, sans être une violation stricte (pas de branche conditionnelle par moteur). |
| "Sortie MIDI", "Avance d'envoi", "Cue de repos" et une vingtaine d'autres libellés en français figés dans une UI très majoritairement anglaise | `MidiSettingsView.swift`, `TimelineEditor.swift` | Voir document i18n dédié. |

---

## 6. Dette fonctionnelle (classée par priorité)

### Critique

1. **Sécurité réseau Velvet Remote inexistante.** TCP en clair, sans authentification, port fixe annoncé par Bonjour. Impact : n'importe quel appareil du réseau local (Wi-Fi de festival, de salle, de résidence partagée) peut envoyer des commandes de lecture au Mac. Risque en concert : interruption malveillante ou accidentelle du show par un tiers. Fichiers : `VelvetRemoteClient.swift:214`, `VelvetRemoteServer.swift:57`. Recommandation : TLS + jeton d'appairage avant toute exposition à un public non maîtrisé.
2. **Licence LemonSqueezy sur le mauvais endpoint (`/validate` au lieu de `/activate`).** Impact : absence probable de limite d'activations réelle, perte de revenu potentielle à l'échelle commerciale. Fichier : `LicenseManager.swift:79`. Recommandation : migrer vers `/activate` et gérer `instance_id` correctement avant toute vente à grande échelle.
3. **DJ Handoff — clé `NSAppleEventsUsageDescription` potentiellement absente.** Impact : crash probable au premier usage de la fonctionnalité vedette "handoff DJ" sur un build signé propre. Fichier : absence confirmée dans `project.pbxproj`/Info.plist généré. Recommandation : test manuel prioritaire avant toute démo publique.

### Élevée

4. **Import vidéo associé au morceau sans aucune UI d'entrée.** Moteur complet et persisté, mais totalement inaccessible à l'utilisateur — fonctionnalité vendue par le nom "Prompter video" dans un tooltip mais jamais activable. `AppState.swift:1859-1905`.
5. **`deleteVelvetTrack` — code de suppression destructive non branché mais dormant.** Si jamais relié à un bouton par erreur future, il contourne tout le mécanisme Velvet Trash. `AppState.swift:4188-4199`.
6. **Contournement trivial du trial 30 jours** par suppression d'une entrée Keychain, sans second facteur. `BetaTrial.swift:85-95`.
7. **Absence de versioning du protocole Velvet Remote.** Une divergence Mac/Remote après mise à jour asynchrone (App Store) provoquerait un échec silencieux (`try?`) sans diagnostic pour l'utilisateur. `VelvetRemoteProtocol.swift`.
8. **Internationalisation quasi absente hors `MidiSettingsView.swift`.** Impact direct sur la crédibilité internationale du produit. Voir document dédié.

### Moyenne

9. **`CLAUDE.md` et deux guides utilisateur en contradiction / obsolescence.** Impact : confusion pour tout futur contributeur (humain ou agent) et pour l'utilisateur final qui suit un guide inexact. Voir §5.
10. **Perte silencieuse de données si `VelvetShowState.json` et `.bak` sont corrompus simultanément.** Rare, mais sans aucun avertissement utilisateur. `VelvetShowStore.swift:379-391`.
11. **Timeline distante du Remote (iPad) réimplémentée indépendamment**, sans code partagé avec la timeline Mac — risque de divergence visuelle progressive. `RemoteTimelineView.swift`.
12. **Indicateur "+2 morceaux" absent sur iPad alors que la donnée existe** côté protocole. `RemotePrompterView.swift`.
13. **Commandes `stop` et `panic` absentes du Remote** malgré leur présence documentée dans le protocole en commentaire. `VelvetRemoteProtocol.swift:47`.

### Faible

14. Sweep du filtre commenté "20kHz→300Hz" mais codé à 800Hz (`AudioEngine.swift:1109`).
15. Nommage cassé "fin→end" (`onPlaybackEndished`, `gainEndal`) — cosmétique, sans risque fonctionnel, mais nuit à la lisibilité du code pour un futur contributeur.
16. Commentaire orphelin en fin de `ShowLibraryViews.swift` référant un composant déplacé depuis.
17. Onboarding : "Add your audio files (MP3, WAV, AIFF...)" omet M4A explicitement dans le texte alors qu'il est supporté.
18. Raccourci ⌘B fantôme mentionné dans un commentaire de code (`AppState.swift:1313`) alors que le vrai raccourci est "T".

---

## 7. Ce qui est prêt à être montré

**Prêt pour une démo.** Bibliothèque/setlist, lecture audio avec crossfade FILTER, pilotage MaestroDMX complet (MIDI+OSC, import, brightness, cue picker), timeline mémos/MIDI/OSC, prompteur (sans vidéo), Velvet Remote sur réseau contrôlé (Wi-Fi personnel, pas un réseau public).

**Prêt pour un bêta-test élargi.** Tout ce qui précède, plus trial/licence dans son état actuel (à condition d'accepter le risque de contournement), DJ handoff (après vérification de la clé Apple Events manquante), import ShowBuddy/MaestroDMX.

**Prêt pour un usage live personnel.** L'app entière dans son état actuel, par un utilisateur qui connaît ses propres limites (réseau Wi-Fi personnel maîtrisé, pas de vidéo prompteur, transitions FILTER/AUTOMIX uniquement). C'est manifestement déjà le cas d'usage réel de l'auteur.

**Pas encore prêt pour publication publique internationale.** Sécurité réseau du Remote, robustesse de la licence, couverture i18n, cohérence des guides utilisateur et des promesses du site public doivent être corrigées en priorité — voir chapitres Critique et Élevée de la dette fonctionnelle, et le document Écosystème pour le détail des écarts marketing.

---

## 8. Verdict simple

**Velvet Show est-il déjà utilisable comme remplaçant moderne de ShowBuddy Setlist ?**
Oui, fonctionnellement, pour un musicien solo ou un petit groupe qui utilise MaestroDMX et un réseau Wi-Fi personnel maîtrisé. Le cœur (audio, setlist, MIDI, OSC, MaestroDMX, Remote) est solide et déjà utilisé en conditions réelles d'après le seul avis App Store disponible. Ce n'est pas encore un remplaçant pour un utilisateur qui a besoin de ShowBuddy Active pour un autre moteur lumière que MaestroDMX (ShowBuddy Active, DMXIS restent verrouillés, non fonctionnels) ni pour un contexte de vente à un public inconnu sur un réseau non maîtrisé.

**Quelles fonctions sont réellement différenciantes ?**
Le pilotage MaestroDMX vérifié avec `VerificationState`, l'OSC natif avec bibliothèque réutilisable, et le Remote iPhone/iPad gratuit avec prompteur partagé. C'est la combinaison, pas une fonction isolée, qui différencie.

**Quelles fonctions donnent seulement l'impression d'exister mais ne sont pas assez terminées ?**
L'import vidéo associé au morceau (0 UI), les profils lumière autres que MaestroDMX (verrouillés par design, pas encore par manque — c'est honnête, mais le site public ne le dit pas clairement), les commandes Stop/Panic du Remote (dans le protocole, jamais implémentées), et toute la promesse de compatibilité "myDMX, Zero 88, Resolume, Companion, OBS, QLab" du site public qui n'a aucune trace dans le code.

**Quelle est la prochaine priorité fonctionnelle logique ?**
Dans l'ordre : (1) sécuriser le protocole Remote (TLS + jeton), (2) corriger l'endpoint de licence LemonSqueezy, (3) vérifier/corriger la clé Apple Events du DJ Handoff, (4) soit brancher l'import vidéo à une UI soit le retirer de toute communication produit, (5) aligner le site public sur ce que le code sait réellement faire aujourd'hui plutôt que sur la roadmap.

---

## 9. Vérification finale

```
Branche active : feature/lighting-profiles-phase1

git status --short :
 M "VELVET SHOW/AppState.swift"
 M "VELVET SHOW/ConcertViews.swift"
```

- ✅ Aucun fichier de code n'a été modifié pendant cet audit (les deux fichiers listés ci-dessus portaient déjà ces modifications avant le début de la mission — confirmé par comparaison de leur contenu à l'identique tout au long de l'analyse).
- ✅ Aucun commit n'a été créé (`git log -5` identique en début et fin de mission : `0fdeeb8` reste le commit le plus récent).
- ✅ Aucune commande Git destructive (`reset`, `stash`, `checkout`, `merge`, `rebase`) n'a été utilisée — seules des commandes de lecture (`status`, `log`, `diff`, `show`, `branch --show-current`) ont été exécutées.
- ✅ Aucun changement de branche n'a eu lieu.
- ✅ Rien n'a été poussé sur GitHub.

Seuls des fichiers nouveaux ont été créés dans `Documentation/Audits/` (ce document et ses trois compléments), conformément à l'autorisation explicite de la mission.
