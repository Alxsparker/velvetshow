# Cohérence de l'écosystème Velvet — App macOS, Velvet Remote, site public, documentation

**Date :** 12 juillet 2026 · Périmètre : `velvetshow.app` (EN + FR), fiche App Store "Velvet Remote", documentation d'architecture, deux guides utilisateur, comparés au code réel audité dans [VELVET_SHOW_CURRENT_CAPABILITIES_2026-07-12.md](VELVET_SHOW_CURRENT_CAPABILITIES_2026-07-12.md).

## Résumé en une phrase

Le site public raconte l'histoire d'un produit environ deux à trois ans en avance sur ce que le code sait faire aujourd'hui — ce n'est pas un problème de mensonge délibéré (le ton reste globalement honnête sur les prix et la nature du produit), mais un problème de **vision produit non tempérée par l'état réel de l'implémentation**, avec deux affirmations qui posent un risque de confiance client concret : le fonctionnement de PANIC et le mécanisme technique du prompteur iPad.

---

## 1. Correction préalable importante sur le périmètre de la mission

Le brief demandait de comparer "Velvet Remote iPhone" et "Velvet Remote iPad" comme **deux applications séparées** sur l'App Store. Vérification faite : **il n'existe qu'une seule fiche App Store**, intitulée simplement "Velvet Remote" (`https://apps.apple.com/fr/app/velvet-remote/id6780494799`), universelle iPhone + iPad, listée avec la mention Apple **"Conçue pour iPad. Non validée pour macOS."** Il n'y a pas deux apps distinctes à comparer, mais une seule app dont l'interface s'adapte à l'idiome de l'appareil (confirmé côté code par `RemoteDiscoveryView.swift` : routage `UIDevice.current.userInterfaceIdiom == .phone` vers `RemoteControlView` sinon vers `RemotePrompterView`). Ce document traite donc "Velvet Remote" comme une app unique à deux présentations, conformément à ce qui est réellement publié.

Données de la fiche : 1 avis (5,0/5), taille 9,8 Mo, iOS 17,6+, langues déclarées "Français et Anglais", gratuite, aucune collecte de données déclarée.

---

## 2. Comparaison détaillée : promesses du site public vs code réel

### 2.1 Compatibilité lumière — écart le plus important de tout l'audit

Le site (EN et FR, contenu identique traduit) affiche une section "WORKS WITH" listant : **MaestroDMX, myDMX, Zero 88, Wolfmix, QLC+, Resolume, Companion, OBS, + any MIDI system** — puis une seconde liste pour OSC : **MaestroDMX, QLab, Companion, + any OSC system**.

Confrontation avec le code réel (voir inventaire lumière détaillé) :

| Produit annoncé sur le site | État réel dans le code |
|---|---|
| MaestroDMX | ✅ Réellement fonctionnel, `verifiedLive`, MIDI+OSC |
| QLC+ | Présent comme `Lighting Profile` sélectionnable, mais `researchOnly` — **aucun code d'envoi, aucune capacité de pilotage réelle** |
| Lightkey | `researchOnly` — même constat, et seulement comme bouton d'import de fichier désactivé "(bientôt)" ailleurs dans l'UI |
| Wolfmix | Un seul bouton désactivé "Wolfmix… (bientôt)" dans un sheet d'import MIDI — **aucune intégration de pilotage** |
| myDMX | **Absent du code — aucune occurrence, aucune trace, aucun profil, aucune mention dans la documentation d'architecture** |
| Zero 88 | **Absent du code — idem** |
| Resolume | **Absent du code — idem** |
| Companion | **Absent du code — idem** |
| OBS | **Absent du code — idem** |
| QLab | **Absent comme cible réelle** — apparaît seulement comme bouton d'import de fichier MIDI désactivé "(bientôt)", jamais comme cible OSC malgré l'exemple visuel du site ("QLab — fire cue Q12 · /cue/Q12/start") |

Sur les neuf produits nommément cités par le site comme compatibles, **un seul (MaestroDMX) dispose d'une intégration réellement fonctionnelle**. Cinq (myDMX, Zero 88, Resolume, Companion, OBS) n'ont **strictement aucune trace dans le code ni dans la documentation d'architecture** — ce ne sont pas des fonctionnalités en cours de développement visibles dans une roadmap, ce sont des noms qui n'existent qu'sur le site public. Les trois autres (QLC+, Lightkey, QLab) existent sous une forme très en amont (statut `researchOnly` sans aucun code d'envoi, ou bouton d'import désactivé) qui ne justifie pas la mention "WORKS WITH" au sens où un client la comprendrait (branchement et pilotage effectif).

**Recommandation** : retirer immédiatement myDMX, Zero 88, Resolume, Companion, OBS et QLab de toute liste "Works with"/"Compatible avec" tant qu'aucune ligne de code ne les concerne, même en recherche. Réserver la mention "compatible" à MaestroDMX seul, et présenter QLC+/Lightkey/DMXIS/ShowBuddy Active comme "en cours d'évaluation" plutôt que comme compatibles — ce qui correspondrait honnêtement au statut `researchOnly`/`unverifiedMapping` que le produit applique déjà en interne avec beaucoup de rigueur (voir `VerificationState`). Le décalage est d'autant plus regrettable que **le produit dispose déjà en interne d'un vocabulaire honnête pour exprimer cette nuance** (`Documentation/Architecture/GLOSSARY.md`) — il n'est simplement pas utilisé sur le site.

### 2.2 PANIC MODE — contradiction factuelle vérifiée

Le site affirme (EN) : *"press PANIC. Audio stops, the stage screen switches to a calm safety display, and the show pauses cleanly until you're ready to continue."* — traduction FR identique : *"L'audio s'arrête, l'écran de scène bascule vers un affichage calme, et le show se met en pause proprement."*

Le guide utilisateur officiel du produit (`VelvetShow_UserGuide.md`, section 12, "PANIC Mode") dit explicitement l'inverse : *"PANIC mode does not affect audio playback or MIDI output."* Le code confirme le guide, pas le site : `triggerPrompterPanic()` (`AppState.swift:1567-1570`) ne fait que basculer un booléen d'affichage (`isPanicPrompterVisible`) qui montre un panneau "BACKUP PROMPTER" intégré à la fenêtre principale — **aucun appel à un quelconque arrêt audio, aucune pause de lecture**.

C'est la contradiction la plus sérieuse de tout cet audit : une fonctionnalité présentée sur le site comme un filet de sécurité qui **coupe le son** ("if a string breaks or the room needs a moment") alors qu'elle ne le fait pas du tout dans le produit réel. Un artiste qui presserait PANIC en pensant couper le son sur la base de la promesse du site serait surpris de constater que l'audio continue.

**Recommandation** : corriger le texte du site en priorité absolue (avant toute autre correction de ce document) pour refléter le comportement réel — PANIC est un filet de sécurité visuel pour l'artiste (retrouver ses repères), pas une coupure audio. Formulation suggérée, alignée sur le guide utilisateur réel : *"Press PANIC and your backup lyrics/notes appear instantly on your main screen — a safety net if the stage display fails, without interrupting the music."*

### 2.3 "Apple Continuity" pour le prompteur iPad — mécanisme technique incorrect

Le site consacre une section entière à ce mécanisme : *"iPad as a wireless prompter via Apple Continuity. No network required — works over Bluetooth + WiFi automatically."*

Le code (agent d'audit Velvet Remote, confirmé sur `VelvetRemoteClient.swift`, `VelvetRemoteServer.swift`, `RemoteDiscoveryView.swift`) montre un mécanisme entièrement différent : découverte **Bonjour** (`_velvetshow._tcp`) et connexion **TCP sur le port 7777**, sur le réseau local Wi-Fi (ou USB) — **pas** l'API Apple Continuity (qui est un framework Apple spécifique, distinct, utilisé par exemple par Sidecar ou Universal Clipboard). Aucune trace d'utilisation de ce framework n'existe dans le code. La conséquence pratique contredit même l'affirmation du site : la connexion **requiert bien le même réseau Wi-Fi** (ou un câble USB), contrairement à "No network required".

Le site distingue d'ailleurs lui-même, juste en dessous, une section "LOCAL NETWORK" décrivant... exactement le mécanisme Bonjour/Wi-Fi réellement implémenté — les deux sections du site semblent décrire deux mécanismes différents alors que le code n'en contient qu'un seul. Il est probable que "Apple Continuity" soit un raccourci marketing pour "connexion automatique sans configuration", mais le nom de la technologie citée est incorrect et vérifiable comme tel par n'importe quel client technique.

**Recommandation** : retirer la mention "Apple Continuity" et fusionner les deux sections en une seule description fidèle : découverte Bonjour automatique sur le réseau Wi-Fi local, avec bascule USB prioritaire quand câblé.

### 2.4 Raccourci PANIC affiché : ⌥+⌘+P vs ⌘⇧P réel

Détail vérifiable et simple à corriger : le site affiche *"⌥ + ⌘ + P — one key, reachable in the dark"* pour PANIC. Le raccourci réel, confirmé par `CLAUDE.md`, les deux guides utilisateur et le code (`VELVET_SHOWApp.swift`), est **⌘⇧P** (Command+Shift+P), pas Option+Command+P. Un utilisateur qui suivrait le raccourci affiché sur le site ne déclencherait rien.

### 2.5 Fonctionnalités correctement représentées

Pour équilibrer ce constat, plusieurs promesses du site sont vérifiées **exactes** :

- **Prix et modèle commercial** ("$79 full licence", "30-day free trial") — exact, confirmé par `BetaTrial.swift` (30 jours) et le positionnement LemonSqueezy du code.
- **OSC natif avec bibliothèque d'événements réutilisables et test manuel** — exact, confirmé par `OSCEngine.swift` et `MidiSettingsView.swift`.
- **Import direct de cue list MaestroDMX** — exact et même plus riche que décrit (déduplication intelligente par empreinte).
- **Master Brightness control** — exact, confirmé (`MASTER BRIGHTNESS`, libellé identique dans le code et sur le site).
- **Mode MIDI, OSC, ou les deux simultanément pour MaestroDMX** — exact (`MaestroControlProtocol` avec cas `.both`).
- **Velvet Remote gratuit, découverte automatique, reconnexion automatique** — exact.
- **"OSC Remote Control — Coming Soon"** (roadmap) — cohérent avec le constat que le Remote n'a aujourd'hui aucune commande lumière, confirmé par recherche exhaustive.
- **Distribution hors Mac App Store, téléchargement direct** — exact, confirmé par le lien de téléchargement GitHub Releases (`v0.13`) trouvé sur le site, cohérent avec `UpdateChecker.swift` qui interroge l'API GitHub Releases.
- **Comparatif tarifaire ShowBuddy (Setlist $119 + Active $199 = $318+)** — invérifiable indépendamment dans cet audit (prix tiers), mais la logique produit ("deux apps, deux fenêtres" vs "une seule app à $79") est cohérente avec l'architecture réelle de Velvet Show.
- **Chords/tap-tempo** ("Chords and key changes synced to the waveform", "BPM display and tap-tempo per song") — **non vérifié positivement** : aucune trace de gestion d'accords/tonalité ni de tap-tempo manuel n'a été trouvée par les agents d'audit Timeline/Playback (seule une détection BPM automatique par bouton existe). À vérifier avant de laisser cette promesse en l'état — statut recommandé : "à vérifier", pas "confirmé faux", faute de recherche dédiée exhaustive sur ce point précis.

### 2.6 Site FR — qualité de traduction, mais hérite des mêmes inexactitudes

Le site propose une version française complète (`/fr`) structurellement identique et fidèlement traduite (voir document i18n dédié pour le score détaillé). C'est un point positif en soi, mais cela signifie que **les trois inexactitudes ci-dessus (compatibilité lumière, PANIC, Apple Continuity) existent aussi en français** — la traduction n'a pas été l'occasion de les corriger, elle les a simplement propagées dans les deux langues.

---

## 3. Cohérence application macOS ↔ Velvet Remote (App Store)

La description de la fiche App Store est factuellement alignée avec le code vérifié pour Velvet Remote — c'est le point de comparaison le plus sain de tout cet audit :

- "Connect your iPhone to Velvet Show over Wi-Fi or USB cable. No configuration, no IP address" — exact, confirmé par Bonjour + détection USB automatique.
- "Tap any track to queue it as the next song — without interrupting playback" — exact, confirmé (`prioritizeNext:<id>`).
- "Automatic reconnection after any network interruption — playback continues on the Mac" — exact, confirmé (le Mac ne bloque jamais sur l'état du client).
- "Velvet Remote requires Velvet Show running on a Mac on the same network" — exact et honnête (contrairement au site principal qui minimise cette exigence avec "Apple Continuity"/"No network required").

Seul écart significatif trouvé : la fiche ne mentionne aucune limite connue (pas de commande Stop/Panic depuis le Remote, pas d'indicateur "+2" sur iPad) — omission neutre plutôt que promesse fausse, donc de moindre gravité que les trois points du site principal.

---

## 4. Fonctionnalités présentes en code mais jamais mises en avant (opportunités marketing)

À l'inverse des sur-promesses ci-dessus, plusieurs capacités réelles et solides du produit ne sont **pas du tout exploitées** dans la communication actuelle :

- **La reprise automatique après interruption système audio** (reconstruction du graphe AVAudioEngine, reprise exacte à la position) — un argument de fiabilité scénique fort, absent du site, alors que la fiabilité est justement l'angle central du positionnement ("Aucune surprise en concert" dans `PRODUCT_VISION.md`).
- **Le mécanisme `VerificationState`** lui-même — c'est un vrai différenciateur ("Velvet Show ne vous laissera jamais activer en live un pilotage lumière non vérifié") qui pourrait devenir un argument de confiance client explicite, au lieu d'être invisible et menacé d'être contredit par la liste "WORKS WITH" trop large du site.
- **La normalisation loudness LUFS/EBU R128** — fonctionnalité professionnelle avancée (True Peak -1dBTP), absente de toute communication, alors qu'elle intéresserait directement un public "ingénieur son" que le site cible explicitement ("Show-control professionals").
- **Le fallback DJ Handoff à trois niveaux** (AppleScript ciblé → System Events → CGEvent HID) — robustesse technique réelle, invisible dans la description "djay Pro" du site.
- **Import ShowBuddy avec migration idempotente des trims** — argument concret pour rassurer un client ShowBuddy hésitant à migrer ("vos réglages ne seront jamais perdus ni écrasés"), absent du comparatif actuel qui reste sur l'argument prix.

---

## 5. Synthèse des actions prioritaires (ordre de correction recommandé)

1. **Corriger la description de PANIC sur le site** (EN + FR) — risque de confiance client le plus direct, correction textuelle simple, aucun changement de code requis.
2. **Retirer myDMX, Zero 88, Resolume, Companion, OBS, QLab de "WORKS WITH"**, ou les déplacer clairement dans une section "Roadmap" distincte de la section "Compatible avec" actuelle.
3. **Corriger le raccourci PANIC affiché** (⌘⇧P, pas ⌥⌘P).
4. **Remplacer la mention "Apple Continuity" par une description fidèle du mécanisme Bonjour/Wi-Fi réel.**
5. **Vérifier concrètement l'existence de la gestion d'accords/tap-tempo** avant de laisser ces deux promesses en l'état.
6. **Ajouter les opportunités marketing listées en §4**, une fois les corrections 1 à 5 faites — inutile de mettre en avant de nouveaux arguments de confiance tant que des inexactitudes vérifiables subsistent sur des points de sécurité (PANIC) et de compatibilité (WORKS WITH).
