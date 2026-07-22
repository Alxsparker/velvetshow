# Cue « Repos » — comportements actuels (audit du 22/07/2026)

État du code audité : branche `feature/lighting-profiles-phase1`, HEAD `ad40948` + chantier non commité.
Configuration utilisateur réelle (UserDefaults) : type **MIDI**, event **57**, délai **0 s**, activée ; déclencheurs : Stop ✔, Fin naturelle ✔, Fin de concert ✔, **Entre deux morceaux ✘ (défaut d'usine)**.

Aucune modification de code n'accompagne ce document.

## Architecture du déclenchement

Un seul point d'entrée : `sendRestCueIfNeeded(trigger:)` (`AppState.swift:2400`), avec 4 déclencheurs
(`.stop`, `.naturalEnd`, `.concertEnd`, `.betweenTracks`) et 5 points d'appel :

| Appel | Fichier:ligne | Déclencheur |
|---|---|---|
| `requestStop()` | AppState.swift:3769 | `.stop` |
| Fin naturelle, queue manuelle préchargée | AppState.swift:2598 | `.betweenTracks` |
| Fin naturelle **hors contexte de show** (Track Library) | AppState.swift:2605 | `.naturalEnd` |
| Fin naturelle, dernier morceau de la setlist | AppState.swift:2611 | `.concertEnd` |
| Fin naturelle, morceau suivant existe, AUTO SHOW off | AppState.swift:2615 | `.betweenTracks` |

## Matrice des scénarios

### 1. Fin naturelle, Auto Next (AUTO SHOW on), morceau suivant existe
**Jamais envoyée — supprimée par design.**
Chemin nominal : `tickAutoNext` (AppState:5302) lance le crossfade avant la fin → `startReplacement` pose `isReplacingTrack = true` → la fin naturelle est absorbée par `guard !isReplacingTrack` (AppState:2487) → `sendRestCueIfNeeded` n'est même pas appelé.
Chemin fallback (morceau très court) : la branche AUTO SHOW de `handlePlaybackEndished` (AppState:2564) lance le suivant et `return` avant tout appel.
Filet supplémentaire : même si une branche l'appelait, la garde `isAutoShowEnabled && nextNaturalSongElementID != nil` (AppState:2414) la supprimerait, silencieusement.

### 2. Fin naturelle, AUTO SHOW on, aucun morceau suivant
**Envoyée** (déclencheur `.concertEnd`, AppState:2611), sauf :
- garde « mémo MIDI récent » : un trigger MIDI de mémo (start ou end) tiré dans les **10 dernières secondes** du morceau la saute — loggé « skipped, recent end memo » (AppState:2420-2428) ;
- event 57 absent de `midiEventsByID` → abandon **silencieux** (AppState:2434) ;
- destination MIDI absente → loggé « SANS DESTINATION » au dispatch.

### 3. Fin naturelle avec « Auto Pause » (l'app s'arrête et attend)
Cas atteint quand AUTO SHOW est **off** (nota : avec AUTO SHOW on, un morceau `.autoStop` enchaîne quand même — `tickAutoNext` AppState:5316-5318 force le fondu filter).
- S'il existe un morceau suivant (préchargé) : déclencheur `.betweenTracks` (AppState:2598 ou 2615) → **ignorée dans ta config** (toggle « entre deux morceaux » désactivé, défaut `false`, AppState:703).
- S'il n'y a pas de suivant : `.concertEnd` → envoyée (mêmes réserves que le cas 2).

⚠️ Piège de nommage : le déclencheur `.naturalEnd` (toggle « fin naturelle » ✔) n'est utilisé **que hors contexte de show** — lecture lancée depuis la Track Library sans set (AppState:2603-2606). En concert Show Library, une fin naturelle entre deux morceaux passe par `.betweenTracks`, pas par `.naturalEnd`.

**→ Cause la plus probable du concert : l'attente « quand on quitte une séquence de lecture » correspond au déclencheur `.betweenTracks`, qui était désactivé.**

### 4. Stop manuel
Deux gestes, deux comportements :
- **Bouton STOP transport / ⌘.** → `requestStop()` (AppState:3755) → `.stop` envoyé **avant** l'arrêt audio. Seules gardes : master enabled + toggle Stop (pas de fenêtre 10 s, pas de garde AUTO SHOW). → **Envoyée.**
- **Double-clic sur la tuile en cours de lecture** → `togglePlayback` → `audioEngine.stop()` direct (AppState:3433), sans passer par `requestStop()` → **jamais envoyée**. Incohérence réelle entre les deux « stops manuels ».

### 5. Fin de concert (dernier morceau, fin naturelle, queue vide)
**Envoyée** (`.concertEnd`, AppState:2611), AUTO SHOW on ou off — mêmes réserves que le cas 2 (fenêtre 10 s, event 57, destination).

### 6. Changement manuel de morceau pendant la lecture (Show Safety → fondu DJ)
**Jamais envoyée — par design.** `startReplacement` (AppState:3499) n'appelle jamais `sendRestCueIfNeeded`, et la fin naturelle du morceau sortant pendant le fade est absorbée par `isReplacingTrack`.

### 7. Double-clic sur une nouvelle tuile pendant la lecture
- Show Safety **on** : double-clic = confirmation → `startReplacement(effect: .filter)` → cas 6, **jamais envoyée**.
- Show Safety **off** : `togglePlayback` → load + play direct → **jamais envoyée** non plus.

### Cas djay (handoff armé)
Fin naturelle avec djay armé : court-circuit total dans `handlePlaybackEndished` — « pas de queue, pas d'auto-show, pas de cue de repos » (commentaire explicite AppState:2489-2492). → **Jamais envoyée par design.** À garder en tête pour le test Release « avec djay ».

## Gardes silencieuses (aucune trace en cas de non-déclenchement)

| Garde | Ligne | Effet |
|---|---|---|
| `restCueEnabled == false` | 2401 | abandon silencieux |
| Toggle du déclencheur désactivé | 2404-2409 | abandon silencieux |
| `isReplacingTrack` (hors `.stop`) | 2413 | abandon silencieux |
| AUTO SHOW + morceau suivant (hors `.stop`) | 2414 | abandon silencieux |
| Event MIDI introuvable (`midiEventsByID[id]`) | 2434-2435 | abandon silencieux |
| Event OSC introuvable (`oscEventsByID[id]`) | 2441-2442 | abandon silencieux |
| Re-check post-délai (isReplacingTrack / AUTO SHOW) | 2462-2464 | abandon silencieux |

Déjà loggées : fenêtre 10 s (« skipped, recent end memo »), dispatch (« SANS DESTINATION », « SEND FAILED », « no MIDI message to send »).

## Spécification du futur correctif (à implémenter APRÈS le test Release)

1. **Logs DEBUG sur chaque garde silencieuse** de `sendRestCueIfNeeded` et de `scheduleRestCueDispatch` :
   format proposé `[REST] skipped (<trigger>) — <raison>` en `print`, plus entrée `midiLog` pour les raisons
   utiles au diagnostic terrain (event introuvable notamment). Chaque non-déclenchement doit avoir une raison explicite.
2. Questions de design à trancher avec l'utilisateur (aucune n'est un correctif automatique) :
   - `.betweenTracks` désactivé par défaut alors que c'est le cas d'usage attendu (« l'app attend ») ;
   - le libellé « fin naturelle » qui ne couvre pas les fins naturelles en contexte de show ;
   - le double-clic-stop qui contourne `requestStop()` et n'envoie jamais la cue ;
   - le handoff djay qui supprime la cue.
