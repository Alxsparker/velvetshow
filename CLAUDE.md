# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Compiler le projet (Debug, simulateur macOS)
xcodebuild -project "VELVET SHOW.xcodeproj" -scheme "VELVET SHOW" -destination "platform=macOS" build

# Compiler en Release
xcodebuild -project "VELVET SHOW.xcodeproj" -scheme "VELVET SHOW" -destination "platform=macOS" -configuration Release build

# Lancer l'app directement (après build)
open ~/Library/Developer/Xcode/DerivedData/VELVET\ SHOW-*/Build/Products/Debug/VELVET\ SHOW.app
```

Cible : **macOS 26.5**, Swift 5. Pas de dépendances externes — uniquement des frameworks Apple (AVFoundation, CoreMIDI, SQLite3 intégré à macOS, SwiftUI).

## Architecture

L'app est une app macOS SwiftUI multi-fenêtres. La source de vérité est `AppState` (`@Observable`, `@MainActor`), injectée via `.environment(appState)` dans toutes les fenêtres.

### Trois fenêtres

| ID | Rôle |
|----|------|
| principal (WindowGroup) | Fenêtre édition/contrôle — `ContentView` |
| `PrompterView.windowID` | Fenêtre Prompter scène — affichage mémos en live |
| `QueueFloatingView.windowID` | Fenêtre flottante — queue de lecture |

### Fichiers clés

- **`AppState.swift`** (~2200 lignes) — état global : DB chargée, sélections, lecture audio, MIDI, queue concert, historique, préférences. Toute mutation de données passe par ici.
- **`Models.swift`** (~870 lignes) — structs de données (read-only ShowBuddy + modèles Velvet locaux). Deux univers distincts :
  - *ShowBuddy* : `AudioFile`, `LightShow`, `ShowSet`, `SetElement`, `MidiEvent`, `MidiMessage`, `ShowMemo` — reflètent fidèlement le schéma SQLite de ShowBuddy.db.
  - *Velvet local* : `VelvetTrack`, `VelvetShow`, `VelvetShowTrack`, `EditableMemo`, `VelvetTrackTrim`, `VelvetTrackVolume`, `ConcertQueueItem`, `ConcertHistoryEntry` — état propre à l'app, jamais écrit dans ShowBuddy.db.
- **`ShowBuddyDatabase.swift`** — wrapper SQLite read-only sur l'API C de SQLite3. ShowBuddy.db n'est **jamais modifiée**.
- **`VelvetShowStore.swift`** — persistance locale Velvet dans `~/Library/Application Support/.../VelvetShowState.json`. Sauvegarde debouncée à 0,4 s.
- **`AudioEngine.swift`** — lecture audio via AVFoundation (`@Observable`, `@MainActor`). Expose `playbackState`, `currentTime`, `duration`. Gère les security-scoped resources pour les fichiers hors sandbox.
- **`MIDIEngine.swift`** — wrapper CoreMIDI minimal : liste les destinations, envoie des `MidiMessage` immédiats. Aucune logique métier ici.
- **`ContentView.swift`** (~5400 lignes) — toute l'UI principale : NavigationSplitView avec les deux modes `LibraryMode.trackLibrary` et `LibraryMode.showLibrary`.
- **`ThemeManager.swift`** — `AppTheme` (fenêtre principale) et `PrompterTheme` (prompter scène) — indépendants.

### Deux modes principaux (`LibraryMode`)

- **Track Library** : vue par morceau (`AudioFile`). Sidebar catégories → liste morceaux → fiche détail (mémos, MIDI, trim, volume).
- **Show Library** : vue par set (`ShowSet` + `SetElement`). Sidebar shows → setlist → queue concert. Mode performance.

### Règle fondamentale

ShowBuddy.db est **read-only**. Toute donnée produite par l'utilisateur (mémos, queue, trim, volume, historique…) est stockée dans `VelvetShowState.json` via `VelvetShowStore`.

### Raccourcis clavier globaux (définis dans `VELVET_SHOWApp.swift`)

| Touche | Action |
|--------|--------|
| Espace | Play/Pause |
| ⌘→ | Morceau suivant |
| ⌘← | Morceau précédent |
| ⌘. | Stop |
| ⌘⇧P | Prompter panic |
| S | Toggle sidebar Shows |
| T | Toggle Quick Library |
