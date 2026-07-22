# Velvet Show — Audit d'internationalisation (i18n)

**Date :** 12 juillet 2026 · **Méthode :** grep exhaustif direct sur le code source (pas d'échantillonnage), lecture intégrale des fichiers `Localizable.strings`, vérification du fichier de projet Xcode. Complète le chapitre 10 du brief d'audit. Voir aussi [VELVET_SHOW_CURRENT_CAPABILITIES_2026-07-12.md](VELVET_SHOW_CURRENT_CAPABILITIES_2026-07-12.md) pour le contexte produit complet.

## Verdict en une phrase

**L'application macOS principale n'est internationalisée qu'à hauteur d'un seul écran de réglages sur trente-deux fichiers Swift**, et même cet écran contient un bug de clé qui casse la traduction de 9 messages d'erreur. **Velvet Remote (iOS), déjà publié sur l'App Store, a une architecture i18n propre mais très partielle.** Le site public, en revanche, est intégralement et correctement traduit en français — c'est aujourd'hui la pièce la mieux internationalisée de tout l'écosystème, ce qui est l'inverse de ce qu'on attendrait d'un produit dont le code est la valeur réelle.

---

## 1. Langues actuellement supportées

| Composant | Langues déclarées | Langues réellement couvertes |
|---|---|---|
| App macOS "VELVET SHOW" | `developmentRegion = en`, `knownRegions = (en, Base, fr)` (`VELVET SHOW.xcodeproj/project.pbxproj:150-155`) | Anglais partout (langue de fait du code), français seulement dans `MidiSettingsView.swift` et de façon éparse dans des libellés isolés ailleurs |
| Velvet Remote (iOS, publié) | FR + EN (confirmé par la fiche App Store : "Langues : Français et Anglais") | FR + EN uniquement sur l'écran de découverte et les libellés de transport |
| Site public velvetshow.app | EN (`/`) + FR (`/fr`) | Intégralement traduit dans les deux langues, contenu identique structurellement |

## 2. Architecture i18n réelle de l'app macOS

### 2.1 Une incohérence structurelle dès la base

Le projet Xcode déclare `developmentRegion = en` — l'anglais est censé être la langue de développement de référence. Mais les deux seuls fichiers `Localizable.strings` de l'app (`VELVET SHOW/en.lproj/` et `VELVET SHOW/fr.lproj/`) sont construits avec le **français comme langue source** : les clés sont des phrases françaises, et `fr.lproj/Localizable.strings` est une table d'identité (clé = valeur, les deux en français) :

```
/* Localizable.strings — Français (langue source)
   VELVET SHOW — Phase 2 i18n : MidiSettingsView
   Clé = valeur courante affichée. Valeur = identique (français = source). */
"Préférences" = "Préférences";
```

tandis que `en.lproj/Localizable.strings` traduit ces mêmes clés françaises vers l'anglais :

```
/* Localizable.strings — English
   VELVET SHOW — Phase 2 i18n : MidiSettingsView
   Keys are French source strings. Values are natural English for live musicians. */
"Préférences" = "Preferences";
```

C'est l'inverse de ce que déclare `developmentRegion = en` dans le projet. Ce n'est pas bloquant techniquement (SwiftUI résout `Text("Préférences")` par correspondance de clé quel que soit le sens déclaré), mais c'est une incohérence d'architecture qui traduit une évolution non planifiée : le code a été écrit en français d'abord, puis un mécanisme de traduction anglaise a été ajouté après coup, sans jamais mettre à jour la déclaration du projet.

### 2.2 Portée réelle : un seul écran sur trente-deux fichiers

L'en-tête des deux fichiers `Localizable.strings` de l'app le dit explicitement : **"Phase 2 i18n : MidiSettingsView"**. C'est vérifié par le contenu : les ~155 clés couvrent exclusivement les réglages MIDI/OSC/Rest Cue/import (`MidiSettingsView.swift`) — aucune clé ne concerne la bibliothèque, le mode concert, le prompteur, la licence, le trial, l'update checker ou l'onboarding.

Mesure de la couverture réelle par comptage direct :

| Fichier | Occurrences `Text(...)`/`Label(...)` en dur | Localisées via `Localizable.strings` |
|---|---|---|
| `MidiSettingsView.swift` | 168 | Oui, très majoritairement (via le mécanisme implicite `Text("clé française")`) |
| `ConcertViews.swift` | 68 | Non |
| `TimelineEditor.swift` | 55 | Non |
| `ContentView.swift` | 44 | Non |
| `ShowLibraryViews.swift` | 26 | Non |
| `AudioFileOperations.swift` | 22 | Non |
| `VelvetTrashView.swift` | 20 | Non |
| `MediaLibraryRemapView.swift` | 13 | Non |
| `LicenseView.swift` | 8 | Non |
| `GuideTourOverlay.swift` | 8 | Non |
| `VELVET_SHOWApp.swift` | 6 | Non |
| `UpdateChecker.swift` | 5 | Non |
| `PrompterView.swift` | 2 | Non |

Au total, environ **295 chaînes `Text`/`Label` en dur** dans l'app, dont seules celles de `MidiSettingsView.swift` bénéficient d'un mécanisme de traduction. Sur les 24 autres fichiers Swift porteurs d'UI, **aucun n'a de table de traduction** — leur contenu s'affiche dans la langue littéralement écrite dans le code source, quel que soit le réglage de langue système de l'utilisateur.

À noter, `NSLocalizedString` (l'API historique) n'est utilisé **nulle part** dans l'app (0 occurrence confirmée par grep exhaustif) ; le mécanisme utilisé est soit la résolution implicite de `Text("clé")` par SwiftUI contre `Localizable.strings`, soit 9 appels explicites à `String(localized:)`.

### 2.3 Bug confirmé : 9 messages d'erreur ne se traduisent jamais en français

Les 9 appels `String(localized: "...")` du fichier (tous dans `MidiSettingsView.swift`, gestion des erreurs d'import MIDI/MaestroDMX) utilisent le **texte anglais** comme clé littérale :

```swift
// MidiSettingsView.swift:1092
parseError = String(localized: "Could not create the MIDI sequence.")
// MidiSettingsView.swift:1357
fileError = String(localized: "Unknown format: expected a MaestroDMX show file.")
```

Or les deux fichiers `Localizable.strings` de l'app utilisent le **français** comme clé (`"Impossible de créer la séquence MIDI." = "Could not create the MIDI sequence.";`). Une recherche exhaustive confirme qu'**aucune des 9 clés anglaises utilisées dans le code ne correspond à une entrée dans `fr.lproj/Localizable.strings` ou `en.lproj/Localizable.strings`**. Résultat concret : un utilisateur en français qui déclenche une de ces 9 erreurs (fichier MIDI illisible, format MaestroDMX non reconnu, sauvegarde MaestroDMX chiffrée, aucune cue trouvée…) verra le message **toujours en anglais**, jamais traduit, contrairement à tout le reste de l'écran de réglages MIDI qui l'entoure et qui, lui, bascule correctement en français. C'est une incohérence visible et reproductible à l'intérieur d'un seul et même écran.

### 2.4 Mélange français/anglais hors du périmètre "Phase 2"

En dehors de `MidiSettingsView.swift`, une recherche de caractères accentués français dans les chaînes de code confirme la présence de libellés **français en dur, jamais traduits**, dispersés dans une application par ailleurs très majoritairement écrite en anglais (295 chaînes anglaises en dur contre une vingtaine de résidus français). Exemples confirmés, tous des chaînes UI réelles (pas des commentaires) :

| Chaîne trouvée | Fichier:ligne | Nature |
|---|---|---|
| `"Mode Répétition"` | `ConcertViews.swift:2074` — *(dans un commentaire de code, mais le libellé UI réel voisin utilise "Repeat Mode" en anglais — cf. document Terminologie)* | Commentaire, pas UI directe |
| `"Joués"` | `AppState.swift:703,2154` | Commentaire de code décrivant un comportement, terme UI réel = "Played"/"Remaining" en anglais selon l'agent d'audit orchestration |
| `"MediaFiles: non défini"` mentionné en commentaire | `AppState.swift:360` | Commentaire de code, texte UI réel probablement anglais |

Après vérification ligne par ligne (voir méthode ci-dessous), l'essentiel des résidus français détectés par la recherche de caractères accentués se sont révélés être des **commentaires de code en français** (le codebase est commenté en français par son auteur), et non des chaînes visibles à l'écran — ce qui est cohérent avec un développeur francophone documentant son propre code. Les cas confirmés de **texte réellement affiché à l'utilisateur** en français en dehors de `MidiSettingsView.swift` sont concentrés sur les libellés déjà cités en §2.2 et sur les tooltips `.help(...)`, qui sont eux **tous en anglais**, y compris sur des écrans qui contiennent par ailleurs des commentaires en français — confirmant que la langue d'écriture des commentaires (français, langue de l'auteur) et la langue de l'UI (anglais, langue cible du produit) sont deux couches bien séparées dans l'esprit du code, mais que la traduction FR de cette UI anglaise n'a été faite que pour un seul écran.

**Conclusion de cette section** : le risque principal n'est pas un mélange chaotique FR/EN visible partout à l'écran, mais l'inverse — **une app annoncée bilingue qui est en réalité unilingue anglaise partout sauf un seul écran**, avec un bug qui casse même la traduction de cet unique écran pour 9 messages d'erreur.

### 2.5 Tooltips, alertes, menus : zéro couverture

Recherche ciblée sur les modificateurs `.help(...)` (info-bulles macOS) hors `MidiSettingsView.swift` : des dizaines d'occurrences trouvées dans `ContentView.swift`, `ShowLibraryViews.swift`, `ConcertViews.swift`, `BetaTrial.swift` — toutes en anglais en dur, aucune ne passe par `Localizable.strings`. Exemples : `.help("Switch between Songs and Shows")`, `.help("Move to Velvet Trash")`, `.help("MaestroDMX master brightness")`, `.help("Lights / Maestro Scenes")`. Un utilisateur macOS configuré en français verra donc une interface où seul l'écran de réglages MIDI change de langue ; absolument tous les tooltips, boutons, alertes et menus du reste de l'application (bibliothèque, mode concert, licence, mise à jour, onboarding) restent figés en anglais.

Le menu d'onboarding (`VELVET_SHOWApp.swift`) — "Welcome to Velvet Show", "Your live performance companion", "Would you like to explore Velvet Show with a guided demo?" — n'a également aucune trace de localisation.

### 2.6 `InfoPlist.strings`

L'app macOS principale **n'a aucun fichier `InfoPlist.strings`** (recherché dans tout le dépôt, absent). Le nom affiché dans Finder, le copyright, et les futures descriptions de permission système (si des entitlements sensibles comme les Apple Events venaient à en exiger une, voir le document principal §6 point 3) ne sont donc localisés dans aucune langue autre que celle du binaire par défaut.

---

## 3. Velvet Remote (iOS, déjà publié) — architecture propre mais très partielle

Contrairement à l'app macOS, Velvet Remote utilise le mécanisme moderne et correct : des clés stables (`remote.connected.wifi`, `remote.searching`, etc.) résolues via `String(localized: "clé", bundle: .main)`, avec des fichiers `en.lproj`/`fr.lproj` cohérents entre eux (18 lignes chacun, traduction complète du périmètre couvert). C'est une bonne pratique, techniquement supérieure à celle de l'app macOS.

Le problème est le **périmètre** : seuls l'écran de découverte (`RemoteDiscoveryView`) et les libellés de transport (`VelvetRemoteClient.swift`) sont couverts. Les écrans réellement utilisés en concert — `RemoteControlView.swift` (liste "Upcoming Songs", commandes Play/Next) et `RemoteTimelineView.swift` — contiennent des chaînes anglaises en dur non localisées : `"No upcoming songs"`, `"UPCOMING SONGS"`, `"Waiting for Velvet Show…"`, `"Waiting for data…"`. Un utilisateur francophone verrait donc un écran de connexion parfaitement traduit, puis, une fois connecté (c'est-à-dire pendant tout l'usage réel en concert), une interface entièrement anglaise.

`InfoPlist.strings` existe bien pour Velvet Remote (`en.lproj`/`fr.lproj`), contrairement à l'app macOS — cohérent avec les exigences de l'App Store, qui impose généralement une localisation minimale des métadonnées.

---

## 4. Terminologie produit dans les fichiers de traduction — cohérence interne

Les nouveaux termes du domaine lumière listés par le brief (Lighting Profile, Verification State, Verified Live, Experimental, Research Only, Mapping Unverified, Generic MIDI, Generic OSC, ShowBuddy Active, DMXIS, QLC+, Lightkey) **n'apparaissent dans aucun fichier `Localizable.strings`** — ils vivent exclusivement dans `AppState.swift` sous forme de chaînes Swift natives (`rawValue` d'enum), non localisées, donc affichées identiquement quelle que soit la langue système. C'est cohérent avec le reste du constat : le domaine lumière, pourtant le plus activement développé actuellement (branche `feature/lighting-profiles-phase1`), n'a reçu aucun effort d'internationalisation.

À l'inverse, `Localizable.strings` révèle deux noms de logiciels tiers absents de toute la documentation d'architecture : **`"Wolfmix… (bientôt)"`** et **`"QLab… (bientôt)"`**, présentés comme de futures sources d'import aux côtés de Lightkey. Ni Wolfmix ni QLab ne figurent dans `Documentation/Architecture/ROADMAP_ARCHITECTURE.md` ni dans `Documentation/Research/RESEARCH_INDEX.md`. C'est un écart de gouvernance documentaire mineur mais réel : une intention produit existe dans le code (bouton visible, même désactivé) sans être tracée dans la documentation censée faire autorité.

---

## 5. Audit UX international

**Un utilisateur américain comprend-il immédiatement l'interface ?** Oui, sans réserve — l'app est très majoritairement écrite et pensée en anglais, avec un vocabulaire de musicien live cohérent (Songs, Shows, Live Notes, Stage Screen, Rest Cue).

**Un utilisateur français comprend-il immédiatement l'interface ?** Partiellement. Il comprendra l'écran de réglages MIDI (traduit), mais naviguera dans une bibliothèque, un mode concert, un prompteur, un écran de licence et un onboarding entièrement en anglais — sans que rien ne signale que seule une petite partie de l'app change de langue. Pour un développeur francophone testant son propre outil, l'anglais omniprésent n'est pas un obstacle ; pour un client payant francophone non-anglophone visé par une commercialisation internationale francophone, c'est un déficit clair par rapport à la promesse implicite (l'app déclare officiellement le français comme langue supportée dans son bundle).

**Certains termes techniques devraient-ils être laissés en anglais ?** Oui — `MIDI`, `OSC`, `Cue`, `BPM`, `DMX`, `Bonjour` sont des termes techniques internationaux que même la version française du site public conserve tels quels, à raison (`Documentation/Architecture` fait le même choix). Les traductions déjà faites dans `MidiSettingsView.swift` respectent bien ce principe (ex. "Cue de repos" traduit "Rest Cue" mais garde "MIDI", "CC", "PC" intacts).

**Certains devraient-ils être traduits ?** Oui — les libellés de navigation quotidienne (Songs/Shows, Play/Pause/Next, Trash, Settings, tooltips d'action) sont les plus visibles et les plus fréquemment lus en concert ; ce sont précisément ceux qui restent non traduits aujourd'hui, alors que du vocabulaire plus technique (MIDI Rest Cue) l'est déjà.

---

## 6. Scores

| Axe | Note /5 | Justification |
|---|---|---|
| **Architecture i18n** | 2/5 | Mécanisme SwiftUI/`Localizable.strings` correctement choisi et propre là où il est utilisé (app macOS comme Remote), mais `developmentRegion` du projet macOS incohérent avec la langue source réelle des fichiers de traduction, et bug de clé avéré sur 9 messages d'erreur. |
| **Couverture des traductions** | 1/5 | Un seul écran sur trente-deux fichiers côté macOS ; deux écrans sur sept côté Remote. La quasi-totalité du parcours utilisateur réel (bibliothèque, concert, prompteur, licence, onboarding) n'est traduite dans aucune langue autre que l'anglais du code source. |
| **Cohérence terminologique** | 3/5 | Là où la traduction existe, elle est soignée et garde intelligemment les termes techniques en anglais. Le vocabulaire produit plus large (Songs vs Track Library, PANIC vs Prompter panic) a des incohérences propres, documentées dans [VELVET_SHOW_TERMINOLOGY_GLOSSARY_2026-07-12.md](VELVET_SHOW_TERMINOLOGY_GLOSSARY_2026-07-12.md), indépendantes de la question linguistique. |
| **Qualité UX multilingue** | 2/5 | Un utilisateur francophone perçoit une app à deux vitesses : un îlot traduit (réglages MIDI) au milieu d'un océan anglais, sans indication de pourquoi. Le site public, lui, obtient une qualité UX multilingue proche de 5/5 — contraste qui doit être résolu avant toute campagne de commercialisation francophone ou internationale mettant en avant le support des deux langues. |

**Recommandation prioritaire** : avant toute communication commerciale affirmant un support français (le bundle le déclare déjà), soit achever l'internationalisation de l'app macOS au niveau du site public, soit retirer `fr` de `knownRegions` et assumer une app anglophone jusqu'à ce que l'effort soit généralisé — l'état actuel (bilingue à 3 %) est le pire des deux mondes pour la perception d'un client payant.
