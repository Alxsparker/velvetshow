# Velvet Show — Glossaire produit officiel et audit de terminologie

**Date :** 12 juillet 2026 · Complète le chapitre 11 du brief d'audit. Méthode : comptage direct par grep des occurrences de chaque terme dans le code source (chaînes UI, pas commentaires sauf mention contraire), croisé avec les deux guides utilisateur et la documentation d'architecture. Objectif : fournir la référence de vocabulaire unique à utiliser dans le code, l'interface, la documentation et le futur site web.

---

## 1. Méthode et principe

Pour chaque paire de termes potentiellement concurrents citée par le brief, ce document tranche en faveur du terme **réellement dominant dans l'UI actuelle** (ce que voit l'utilisateur aujourd'hui), signale l'écart avec les noms internes de code quand il existe, et propose une convention unique à figer pour l'avenir. Un écart entre nom de code interne et libellé UI n'est **pas en soi un problème** tant qu'il est cohérent et documenté — le problème apparaît quand deux endroits de l'UI elle-même, ou deux documents destinés à l'utilisateur, se contredisent.

---

## 2. Verdict par paire de termes

### Show / Concert — **pas une incohérence, deux concepts distincts à bien distinguer**

- **"Show"** (35 occurrences UI comptées contre 4 pour "Concert" dans les chaînes visibles) désigne la **setlist** — l'objet persistant que l'utilisateur crée, nomme, colore, réordonne (`VelvetShow`, `ShowSet`, libellé de mode "Shows").
- **"Concert"** désigne, dans le code interne, la **session de lecture live** d'un Show — la queue en cours, l'historique de lecture, le mode répétition (`ConcertQueueItem`, `ConcertHistoryEntry`, `ConcertPlayedTrack`, fichier `ConcertViews.swift`, `isRehearsalMode`).
- **Recommandation** : conserver cette distinction à deux niveaux, mais la nommer explicitement dans la documentation utilisateur (aucun des deux guides actuels ne l'explique). Terme de référence pour le glossaire officiel : **"Show"** pour l'objet setlist, **"Concert session"** pour l'exécution live d'un Show — à ne jamais utiliser "Concert" seul comme synonyme de "Show" dans une future documentation ou un futur site.

### Song / Track — **usage à deux niveaux cohérent, mais non documenté comme tel**

- Les types de données internes utilisent presque exclusivement **"Track"** : `AudioFile`, `VelvetTrack`, `VelvetShowTrack`, `ConcertPlayedTrack`, `TrashedVelvetTrack`.
- L'UI visible par l'utilisateur utilise presque exclusivement **"Song"** (133 occurrences de chaînes contenant "Song" contre 2 pour "Track" dans les chaînes UI) : `LibraryMode.label` retourne littéralement `"Songs"`, "Quick Songs", "Import a Song", "Upcoming Songs" (Remote).
- Il existe même un type `Song` (`Models.swift:1223`) distinct de `AudioFile`/`VelvetTrack`, probablement une façade unifiée pour l'UI.
- **Recommandation** : c'est un renommage UI-facing déjà largement effectué (code interne = Track, produit = Song) mais **jamais documenté comme convention** — ni dans `CLAUDE.md`, ni dans `Documentation/Architecture/GLOSSARY.md`. Le guide `Documentation/velvet-show-0.9-beta-user-guide.md` utilise encore "Track Library" (nom interne) là où `VelvetShow_UserGuide.md` utilise "Songs mode" (nom produit actuel). **Terme de référence officiel : "Song"** dans toute communication utilisateur et documentation ; "Track" reste réservé au vocabulaire de code interne, à ne jamais exposer dans un guide utilisateur futur.

### Lighting Profile / Lighting Engine — **terminologie déjà cohérente, un seul terme utilisé**

Recherche exhaustive : "Lighting Engine" n'apparaît nulle part dans le code ni la documentation. Seul **"Lighting Profile"** est utilisé, conformément à `Documentation/Architecture/GLOSSARY.md`. Pas d'incohérence détectée sur cette paire. Point d'attention distinct (pas une confusion de nom mais de couche) : le réglage interne s'appelle `maestroControlProtocol` et non `maestroTransport`, alors que la documentation d'architecture emploie le terme **"Transport"** (voir paire suivante) — c'est la seule zone de flottement réelle autour de ce concept.

### Cue / Scene — **usage majoritairement cohérent avec une exception MaestroDMX assumée**

- **"Cue"** domine largement (110 occurrences de chaînes UI) pour désigner un événement programmé sur la timeline (Cue MIDI, Cue OSC, Cue de repos/Rest Cue).
- **"Scene"** apparaît (10 occurrences) presque exclusivement dans le contexte MaestroDMX : chemin OSC `/show/cue/scene/1`, libellé "Scene Name" du sheet d'import MaestroDMX, "Lights / Maestro Scenes" dans le menu de contrôle live, et dans la doc utilisateur : "Rest Cue... restore a calm lighting scene."
- **Analyse** : ce n'est pas une confusion accidentelle — "Scene" désigne spécifiquement une **scène lumière MaestroDMX** (un état de l'éclairage), tandis que "Cue" désigne l'**événement de déclenchement** générique (MIDI/OSC/mémo) sur la timeline. Une "Cue" peut déclencher une "Scene". La distinction est défendable mais jamais explicitée pour l'utilisateur.
- **Recommandation** : conserver "Cue" comme terme générique de timeline, réserver "Scene" exclusivement au vocabulaire lumière MaestroDMX (déjà presque le cas), et l'expliciter dans le glossaire produit public : *"Une Cue déclenche une action programmée (MIDI, OSC ou mémo) ; une Scene est un état lumière MaestroDMX que peut appeler une Cue."*

### Memo / Note — **incohérence confirmée entre les deux guides utilisateur, tranchée par le code**

- Le type de donnée interne est **`EditableMemo`**/**`ShowMemo`**, et l'UI de l'app macOS affiche littéralement **"Memos"** (onglet "Memos", "MIDI memos", statistiques "Memos"). C'est aussi le vocabulaire du guide `Documentation/velvet-show-0.9-beta-user-guide.md`.
- Le guide `VelvetShow_UserGuide.md` (racine, plus récent) utilise systématiquement **"Live Notes"** ("Section 9 — Live Notes", carte "Memos & MIDI" citée une fois puis "Live Notes" partout ailleurs dans ce même guide) pour désigner exactement le même objet.
- **Verdict tranché** : le code source, source de vérité ultime, utilise "Memo" partout (identifiants, libellés d'onglet, tooltips). **"Live Notes" n'existe dans aucune chaîne du code** — c'est un terme purement documentaire introduit dans le guide racine sans réplique dans le produit réel. **Terme de référence officiel : "Memo"**. Le guide `VelvetShow_UserGuide.md` doit être corrigé pour utiliser "Memo" partout où il dit actuellement "Live Notes", ou alors le code doit être renommé en UI vers "Live Notes" — mais les deux ne peuvent pas continuer à coexister dans deux guides différents pour le même produit.

### Transport / Protocol — **flottement réel, à corriger**

- La documentation d'architecture (`Documentation/Architecture/GLOSSARY.md`, `MASTER_ARCHITECTURE.md`) définit systématiquement **"Transport"** comme le canal générique d'envoi (MIDI, OSC, futur Art-Net).
- Le code, lui, nomme le réglage utilisateur correspondant **`maestroControlProtocol`** (type `MaestroControlProtocol`, valeurs MIDI/OSC/Both), jamais "Transport". Le mot **"Protocol"** est donc le terme réellement utilisé dans le code source à cet endroit précis, en contradiction directe avec le vocabulaire d'architecture documenté.
- **Recommandation** : c'est la seule vraie incohérence de nommage code↔doc trouvée sur cette paire de termes. Puisque `Documentation/Architecture/` fait autorité (`MASTER_ARCHITECTURE.md` s'auto-désigne comme référence absolue) et que la roadmap prévoit une généralisation du concept Transport à Art-Net puis à d'autres Extensions, **le code devrait migrer vers "Transport" à terme** (`maestroTransport` plutôt que `maestroControlProtocol`) — mais un tel renommage touche un symbole `maestro*`, ce que `KNOWN_RISKS.md` interdit explicitement avant la fin de la migration vers le modèle Extension (Phase 3). **Statut recommandé : documenter l'écart maintenant, reporter le renommage à la Phase 3.**

### Prompter / Lyrics — **usage à deux niveaux, cohérent une fois clarifié, mais recouvre aussi la confusion Prompter/PANIC**

- Le composant technique et la fenêtre séparée s'appellent partout **"Prompter"** (`PrompterView.swift`, `Window("Prompter", ...)`, bouton toolbar "Prompter").
- **"Lyrics"** (35 occurrences) désigne le contenu affiché à l'intérieur du Prompter (paroles importées, "Import Lyrics"), jamais le composant lui-même — usage cohérent, pas de confusion.
- **"Stage Screen"** (2 occurrences seulement, très rare dans le code) est un terme quasi absent du code mais central dans le guide `VelvetShow_UserGuide.md`, qui l'utilise comme nom de section ("Section 11 — Stage Screen") pour désigner... la même fenêtre Prompter. Le guide "0.9 Beta" utilise "Prompter Window" pour le même objet.
- **Le vrai problème de cette famille de termes n'est pas Prompter/Lyrics mais PANIC** : les deux guides utilisateur décrivent des comportements différents et contradictoires pour le raccourci ⌘⇧P (l'un dit qu'il ouvre une fenêtre séparée "Prompter panic", l'autre dit qu'il bascule un panneau interne "Backup Prompter"/PANIC Mode). Vérification code : le raccourci bascule un booléen (`isPanicPrompterVisible`) qui affiche un panneau **intitulé littéralement "BACKUP PROMPTER"**, intégré à la fenêtre principale — confirmant le guide racine, contredisant le guide "0.9 Beta".
- **Recommandation** : **terme de référence officiel : "Prompter"** pour la fenêtre/le composant technique dédié (2ᵉ écran), **"Backup Prompter"** pour le panneau de secours intégré à la fenêtre principale déclenché par PANIC, et abandon du terme **"Stage Screen"** (quasi absent du code, redondant avec "Prompter", source de confusion entre guides) au profit de "Prompter" partout dans la documentation future.

### Remote / Controller — **pas d'incohérence produit, "Controller" est un terme de code technique sans fuite UI**

"Remote" est le seul terme employé côté produit et UI ("Velvet Remote", app iOS, "Get Velvet Remote"). "Controller" (33 occurrences) n'apparaît que comme suffixe de nom de classe technique interne (`VideoPlayerController`, `PrompterWindowController`) — jamais exposé à l'utilisateur. Pas d'action requise, cette paire ne constitue pas une incohérence de terminologie produit.

---

## 3. Termes du domaine lumière — cohérence de la nouvelle terminologie (branche active)

Vérification des termes introduits récemment (commit `3345dd2`, "Add lighting profile verification states") :

| Terme | Présent dans le code | Présent dans la doc d'architecture | Présent dans une UI localisée (FR) | Cohérent partout où il apparaît |
|---|---|---|---|---|
| Lighting Profile | Oui (`AppState.swift`) | Oui (`GLOSSARY.md`) | Non (aucune clé `Localizable.strings`) | Oui |
| VerificationState | Oui, enum à 4 cas | Oui (`ADR-0005`) | Non | Oui |
| Verified Live (`verifiedLive`) | Oui | Oui | Non | Oui |
| Experimental (`experimental`) | Oui | Oui | Non | Oui |
| Research Only (`researchOnly`) | Oui | Oui | Non | Oui |
| Mapping Unverified (`unverifiedMapping`) | Oui | Oui | Non | Oui — note : le nom de code (`unverifiedMapping`) et le libellé UI probable ("Mapping Unverified") inversent l'ordre des mots ; à uniformiser si un badge textuel est un jour localisé |
| Generic MIDI | Oui | Oui | Non | Oui |
| Generic OSC | Oui | Oui | Non | Oui |
| ShowBuddy Active | Oui | Oui | Non | Oui |
| DMXIS | Oui | Oui | Non | Oui |
| QLC+ | Oui | Oui | Non | Oui |
| Lightkey | Oui | Oui | Non | Oui — mais Lightkey apparaît *aussi* dans `Localizable.strings` comme option d'**import de fichier** ("Lightkey… (bientôt)"), un concept différent du Lighting Profile "Lightkey" (`researchOnly`, pilotage live). Ambiguïté à lever : s'agit-il du même Lightkey vu sous deux angles (profil de pilotage live vs source d'import offline), ou de deux fonctionnalités distinctes portant le même nom ? À clarifier avant toute communication publique. |

**Constat global** : la terminologie du domaine lumière est interne et cohérente entre code et documentation d'architecture — logique, puisque ce domaine n'est pas encore exposé à l'utilisateur final (aucun de ces termes n'existe dans une chaîne UI localisée). Le risque n'est donc pas une incohérence actuelle, mais un **risque futur** : le jour où ces termes seront exposés à l'utilisateur (Phase 1 de la roadmap, "Clarification UI"), il faudra veiller à ce que le vocabulaire "Verified Live"/"Experimental"/"Research Only" reste identique entre l'app, sa traduction française, et le site public — qui aujourd'hui n'emploie déjà **aucun** de ces termes (voir document Écosystème) et présente une vision de la compatibilité lumière beaucoup plus simple et optimiste que la réalité du modèle `VerificationState`.

---

## 4. Glossaire produit officiel recommandé

À adopter tel quel dans le code, l'interface, la documentation et le futur site web :

| Terme officiel | Définition | Ne jamais utiliser à la place |
|---|---|---|
| **Show** | Une setlist nommée, créée par l'utilisateur ou importée de ShowBuddy | "Set", "Setlist" (sauf comme synonyme explicatif), "Playlist" |
| **Concert session** | L'exécution live d'un Show : queue, historique, morceau en cours | "Concert" seul comme synonyme de Show |
| **Song** | Un morceau audio dans la bibliothèque, tel qu'affiché à l'utilisateur | "Track" (réservé au code interne) |
| **Memo** | Une note textuelle positionnée sur la timeline d'un morceau, visible au Prompter | "Live Note", "Note" seul |
| **Cue** | Un événement programmé sur la timeline (MIDI, OSC, ou associé à un Memo) qui se déclenche automatiquement | "Trigger", "Event" seul |
| **Scene** | Un état lumière MaestroDMX que peut appeler une Cue ou le contrôle manuel | "Cue" comme synonyme quand il s'agit spécifiquement de lumière |
| **Lighting Profile** | Le moteur lumière tiers sélectionné (MaestroDMX, ShowBuddy Active, DMXIS, QLC+, Lightkey, Generic MIDI, Generic OSC) | "Lighting Engine", "Backend" |
| **VerificationState** | Le niveau de confiance d'un Lighting Profile (`verifiedLive`/`experimental`/`unverifiedMapping`/`researchOnly`), qui seul détermine l'accès aux contrôles live | Tout flag parallèle |
| **Transport** | Le canal générique d'envoi (MIDI, OSC, futur Art-Net) | "Protocol" (terme de code à faire migrer en Phase 3, voir §2) |
| **Prompter** | La fenêtre/le composant dédié à l'affichage scène des Memos et de la vidéo | "Stage Screen" |
| **Backup Prompter** | Le panneau de secours intégré à la fenêtre principale, activé par PANIC (⌘⇧P) | "Prompter panic" (fenêtre séparée — n'existe pas) |
| **Velvet Remote** | L'app compagnon iPhone/iPad | "Controller" (réservé au code interne) |

---

## 5. Score

| Axe | État |
|---|---|
| Paires sans incohérence réelle | Show/Concert (deux concepts distincts), Lighting Profile/Lighting Engine, Remote/Controller |
| Paires avec incohérence mineure, déjà tranchée par l'usage dominant | Song/Track, Cue/Scene |
| Paires avec incohérence réelle à corriger | **Memo/Live Notes** (deux guides utilisateur contradictoires), **Transport/Protocol** (doc vs code), **Prompter/Stage Screen/PANIC** (comportement décrit différemment selon le guide) |

**Priorité de correction unique et la plus visible pour l'utilisateur final** : unifier "Memo" vs "Live Notes" et clarifier le comportement réel de PANIC dans un seul guide utilisateur faisant autorité — les deux guides actuels ne peuvent pas continuer à coexister sans induire les futurs utilisateurs en erreur sur le fonctionnement d'une fonctionnalité de sécurité scénique.
