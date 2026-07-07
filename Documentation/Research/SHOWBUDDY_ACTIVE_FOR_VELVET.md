# Audit ShowBuddy Active pour intégration Velvet Show

Date d'audit: 2026-07-04  
Racine de travail: `/Users/alexandrechalon/Documents/ShowBuddyResearch`  
Dossier d'audit: `SHOWBUDDY_ACTIVE_AUDIT`

Mission respectée: analyse en lecture seule sur les fichiers originaux. Les fichiers copiés l'ont été uniquement dans `SHOWBUDDY_ACTIVE_AUDIT/copied_files`.

## Tableau de séparation produits

| Fonction | Active | Setlist | Legacy |
|---|---|---|---|
| Lecture audio | ❓ Non confirmé par fichiers Active inspectés | ⚠️ Hors périmètre | ⚠️ Présent dans `ShowBuddy.db` et `Media Files`, contexte legacy uniquement |
| Playlist | ✅ Shows/banques/presets Active trouvés | ⚠️ App installée, non analysée | ⚠️ Tables `Sets`, `SetElements`, contexte legacy uniquement |
| DMX | ✅ `DmxLibrary`, `DmxConfig.xml`, presets `.prt`, Art-Net string | ⚠️ Hors périmètre | ⚠️ Tables `DmxisCues`, fichiers `.dmxis`, contexte legacy uniquement |
| OSC | ✅ Indices forts dans l'app: `OSC Remote Control`, ports, JUCE OSC | ⚠️ Hors périmètre | ❓ Non attribué |
| MIDI | ✅ Indices forts dans l'app et presets `.prt`: MIDI Learn, notes/CC, clock | ⚠️ Hors périmètre | ⚠️ Tables `MidiEvents`, `MidiMessages`, contexte legacy uniquement |
| Vidéo | ✅ `Media/*.webm`, presets vidéo `.prt`, `Video Examples` | ⚠️ Hors périmètre | ❓ Non attribué |
| Prompteur | ❓ Aucun indice Active trouvé | ⚠️ Hors périmètre | ⚠️ `ShowMemos` legacy, ne pas attribuer à Active |
| Remote | ✅ Indices `OSC Remote Control` | ⚠️ Hors périmètre | ❓ Non attribué |

Ligne directrice: ce rapport porte sur ✅ ShowBuddy Active. Les éléments ⚠️ ShowBuddy Setlist et ⚠️ ShowBuddy legacy sont signalés seulement parce qu'ils existent localement ou aident à comprendre une migration/intégration; ils ne sont jamais utilisés comme preuve de fonctionnalité Active.

## Résumé exécutif

✅ ShowBuddy Active est installé localement en version `2.3.1`. Son support global contient des shows d'exemple, presets, fixtures DMX, macros, médias vidéo et documentation. Les formats de show Active sont largement lisibles: `DmxConfig.xml`, `bank.xml` et presets `.prt` sont du XML.

Pour Velvet Show, les pistes d'intégration les plus crédibles sont:

- Runtime: pilotage de ShowBuddy Active via MIDI, probablement stable et accessible depuis Velvet Show via IAC/CoreMIDI.
- Runtime: pilotage via OSC, à valider dans l'UI ou la documentation officielle car les chaînes internes prouvent la présence d'OSC mais pas le contrat d'adresses.
- Offline: génération ou inspection de fichiers XML Active (`Shows`, `Presets`, `DmxConfig.xml`) pour préparer des banques/presets/fixtures.
- Lumière réseau: Active contient des indices Art-Net (`New Art-Net output...`, `Send to Art-Net`), donc Velvet Show pourrait déclencher Active plutôt que générer le DMX lui-même.

Limite majeure: aucune liste d'adresses OSC publiques n'a été trouvée dans les fichiers texte. Les chaînes extraites du binaire ne remplacent pas une API documentée.

## Chemins trouvés

| Provenance | Chemin | Statut |
|---|---|---|
| ✅ ShowBuddy Active | `/Applications/Show Buddy Active.app` | App bundle présent |
| ✅ ShowBuddy Active | `/Library/Application Support/db audioware/Show Buddy Active` | Support global principal |
| ✅ ShowBuddy Active | `/Library/Application Support/db audioware/Show Buddy Active/Documentation/Show Buddy Active.pdf` | Documentation PDF |
| ✅ ShowBuddy Active | `/Library/Application Support/db audioware/Show Buddy Active/DmxLibrary` | 403 fixtures `.dmx` |
| ✅ ShowBuddy Active | `/Library/Application Support/db audioware/Show Buddy Active/Macros` | Macros + Python embarqué |
| ✅ ShowBuddy Active | `/Library/Application Support/db audioware/Show Buddy Active/Presets` | Presets `.prt` |
| ✅ ShowBuddy Active | `/Library/Application Support/db audioware/Show Buddy Active/Shows` | Shows exemples |
| ✅ ShowBuddy Active | `/Library/Application Support/db audioware/Show Buddy Active/Media` | Médias vidéo/image exemples |
| ⚠️ ShowBuddy Setlist | `/Applications/Show Buddy Setlist.app` | Présent, non analysé fonctionnellement |
| ⚠️ ShowBuddy Setlist | `~/Library/Application Support/CrashReporter/Show Buddy Setlist_*.plist` | CrashReporter seulement |
| ⚠️ ShowBuddy legacy | `/Library/Application Support/db audioware/Show Buddy` | Bases, médias, docs legacy |
| ❓ Indéterminé | `~/Library/Preferences/com.dbaudioware.showbuddy.plist` | Préférences génériques |
| ❓ Indéterminé | `~/Library/Preferences/Show Buddy.settings` | XML prefs générique |

Recherche dans `~/Library/Containers`: première tentative interrompue par `fts_read: Interrupted system call`; relance avec `-maxdepth 3` sans résultat. Recherche dans `/Library/Application Support`: plusieurs `Permission denied` sur dossiers Apple système, sans bloquer l'audit.

## Structure Active

Structure principale de `/Library/Application Support/db audioware/Show Buddy Active`:

- `Documentation/Show Buddy Active.pdf`
- `DmxLibrary/` avec fabricants et fixtures `.dmx`
- `Macros/` avec `Python`, `Shapes`, `Colours`, `Global Edits`, `Chases`, `System`, `Fan`, `Select`, `Channel Masks`, `Utility`
- `Presets/General/Reset All.prt`
- `Shows/Sample Show`
- `Shows/Sample 3D Beams`
- `Help/`
- `Media/` avec fichiers `.webm` et `.png`

Copies effectuées dans l'audit:

- `copied_files/Application Support/db audioware/Show Buddy Active/Documentation`
- `copied_files/Application Support/db audioware/Show Buddy Active/DmxLibrary`
- `copied_files/Application Support/db audioware/Show Buddy Active/Macros`
- `copied_files/Application Support/db audioware/Show Buddy Active/Presets`
- `copied_files/Application Support/db audioware/Show Buddy Active/Shows`
- `copied_files/Application Support/db audioware/Show Buddy Active/Help`
- `copied_files/Application Support/db audioware/Show Buddy Active/Media`
- `copied_files/Applications/Show Buddy Active.app/Contents/Info.plist`
- `copied_files/Applications/Show Buddy Active.app/Contents/Resources/RecentFilesMenuTemplate.nib`

Taille d'audit finale observée: environ 76 Mo avant rédaction finale.

## Application macOS Active

✅ ShowBuddy Active:

- Bundle: `/Applications/Show Buddy Active.app`
- `CFBundleDisplayName`: `Show Buddy Active`
- `CFBundleIdentifier`: `com.dbaudioware.platinum`
- Version: `2.3.1`
- Copyright: `(c) 2018-2025 db audioware limited`
- Minimum macOS: `10.15`
- Binaire: Mach-O universal `x86_64` + `arm64`
- Ressources visibles: `Icon.icns`, `RecentFilesMenuTemplate.nib`
- Frameworks inclus: aucun dossier `Contents/Frameworks` trouvé dans le bundle inspecté

Le binaire n'a pas été désassemblé. Seule extraction `strings` a été utilisée, conformément à la limite demandée.

## Formats lisibles

### Shows Active

✅ ShowBuddy Active:

`Shows/Sample Show` et `Shows/Sample 3D Beams` contiennent:

- `DmxConfig.xml`
- `bank.xml`
- presets `.prt`

Les `.prt` sont du XML et commencent par:

```xml
<DbAudiowarePreset product="DMXIS Platinum" major="2" minor="0" patch="10" ...>
```

38 fichiers XML de type `DbAudiowarePreset` ont été repérés dans `Shows` et `Presets`.

`DmxConfig.xml` mappe les fixtures avec:

- chemin de fixture `.dmx`
- nom affiché (`disp`)
- plage DMX `from` / `to`
- position dans l'éditeur
- paramètres de faisceau

Exemple de modèle observé:

```xml
<DmxFixture name=".../Stairville/xBrick 5Ch Mode.dmx" disp="Wash1" from="1" to="5">
```

### Fixtures `.dmx`

✅ ShowBuddy Active:

403 fixtures `.dmx` trouvées. Format ASCII simple. Exemple `8 Way Dimmer.dmx`:

```text
Ch1
D,0,255,
Ch2
D,0,255,
```

Ce format est exploitable pour parser des canaux, noms et plages de valeurs.

### Presets `.prt`

✅ ShowBuddy Active:

Les presets exposent des paramètres MIDI:

```xml
<Param nm="Bank" v="..." cc="-1" nrpn="-1" ch="0"/>
<Param nm="Preset" v="..." cc="-1" nrpn="-1" ch="0"/>
<Param nm="PresetUp" ... cc="-62" ... ch="1"/>
```

Ils exposent aussi de nombreux paramètres vidéo/lumière avec suffixes `-osctype`, `-osclevel`, `-oscphase`, `-oscspeed`, `-oscshape`. Attention: dans ce contexte, `osc` désigne aussi les oscillateurs internes de modulation, pas forcément le protocole réseau OSC.

### `.dmxis`

⚠️ ShowBuddy legacy:

1472 fichiers `.dmxis` trouvés sous `/Library/Application Support/db audioware/Show Buddy/Media Files`. Ils relèvent du dossier legacy, pas du dossier Active. Les médias complets pèsent environ 31 Go et n'ont pas été copiés. Un seul échantillon `.dmxis` a été copié pour analyse.

`file` indique `data`; `strings` montre une signature visible `jatm`. Le format paraît binaire/propriétaire et n'a pas été reverse-engineeré.

### `.sab`

❓ Indéterminé:

Aucun fichier `.sab` trouvé dans les emplacements inspectés.

## Indices OSC

✅ ShowBuddy Active, depuis `strings` sur le binaire:

- `OSC Remote Control`
- `Enable OSC`
- `oscInPort`
- `oscOutPort`
- `oscOutAdd`
- `oscMaxBanks`
- `oscMaxPresets`
- `OSC output error`
- classes JUCE OSC: `OSCReceiver`, `OSCException`, `OSCFormatError`

✅ ShowBuddy Active, depuis XML `.prt`:

- nombreux attributs `*-osctype`, `*-osclevel`, `*-oscphase`, `*-oscspeed`, `*-oscshape`
- ces attributs semblent surtout liés à la modulation/oscillateur interne des paramètres

Conclusion OSC: Active a très probablement une fonction de remote control OSC, mais les adresses OSC publiques et les ports par défaut n'ont pas été trouvés dans les fichiers texte. Il faut les relever dans l'UI ou la documentation officielle.

## Indices MIDI

✅ ShowBuddy Active, depuis `strings`:

- `MIDI Learn`
- `MIDI Controller`
- `MIDI Notes`
- `MIDI Export`
- `Audio/MIDI Settings`
- `Listen on MIDI channel`
- `Sync to incoming MIDI clock`
- `Control banks with MIDI notes`
- `Control presets with MIDI notes`
- `MIDI bank control`
- `MIDI preset control`
- `MIDI send delay (ms)`
- `defaultMidiOutputDevice`
- `Bluetooth MIDI`

✅ ShowBuddy Active, depuis `.prt`:

- champs `cc`, `nrpn`, `ch`
- paramètres `Bank`, `Preset`, `PresetUp`, `PresetDown`, `BankUp`, `BankDown`
- plusieurs paramètres numérotés pouvant être MIDI-learnés

⚠️ ShowBuddy legacy:

`ShowBuddy.db` contient `MidiEvents` et `MidiMessages`. Exemple de tables:

- `MidiEvents(MidiEventID, Name, Category)`
- `MidiMessages(MidiMessageID, MidiEventID, Time, OutDevice, Channel, Message, Data1, Data2)`

Ces données sont utiles pour comprendre l'ancien scheduler ShowBuddy, mais ne prouvent rien pour Active.

Conclusion MIDI: c'est la piste la plus pragmatique pour Velvet Show. Velvet peut envoyer notes/CC/clock via CoreMIDI/IAC pour sélectionner banques/presets ou synchroniser Active.

## Indices Art-Net / DMX

✅ ShowBuddy Active:

Chaînes binaires:

- `ArtNetOutput`
- `New Art-Net output...`
- `Send to Art-Net`
- `isArtnet`

Shows Active:

- `DmxConfig.xml` décrit les fixtures et adresses DMX
- les adresses supérieures à 512 apparaissent dans l'exemple (`from="513"`), ce qui suggère une gestion multi-univers ou adressage étendu; à valider dans l'UI Active

Fixtures:

- 403 définitions `.dmx`
- format lisible et exploitable

Conclusion DMX: Active semble conçu comme moteur lumière/vidéo avec sortie Art-Net possible. Velvet Show pourrait déclencher des presets plutôt que gérer tous les canaux DMX.

## Macros Python

✅ ShowBuddy Active:

`/Library/Application Support/db audioware/Show Buddy Active/Macros` est présent et copié. Comptage observé: 2164 fichiers `.py`, majoritairement sous `Macros/Python`, avec une distribution Python standard embarquée.

Sous-dossiers de macros Active:

- `Shapes`
- `Colours`
- `Global Edits`
- `Chases`
- `System`
- `Fan`
- `Select`
- `Channel Masks`
- `Utility`

Les recherches texte montrent beaucoup de bruit Python standard (`zipfile.py`, `shutil.py`, tests de socket, etc.). Aucune API Python propre à Velvet/ShowBuddy n'a été identifiée dans cette passe rapide, mais les dossiers métiers méritent une analyse ciblée ultérieure.

## Documentation incluse

✅ ShowBuddy Active:

`Show Buddy Active.pdf` est présent et copié. `pdftotext` n'est pas installé sur la machine; extraction texte complète non réalisée. `strings` sur le PDF a donné peu de contenu exploitable, probablement à cause de la compression PDF.

⚠️ ShowBuddy legacy:

`/Library/Application Support/db audioware/Show Buddy/Documentation/ShowBuddy.pdf` existe mais concerne le produit legacy; il n'est pas utilisé comme source de capacité Active.

## Bases de données

⚠️ ShowBuddy legacy:

Fichiers trouvés dans `/Library/Application Support/db audioware/Show Buddy`:

- `ShowBuddy.db`
- `ShowBuddy.db.default`
- `ShowBuddy.db.backup`
- `Show Buddy Commun.dbb`

`ShowBuddy.db` est SQLite valide, `PRAGMA integrity_check` renvoie `ok`. Tables principales observées:

- `AudioFiles`
- `DmxisCues`
- `LightShows`
- `MidiEvents`
- `MidiMessages`
- `Sets`
- `SetElements`
- `ShowMemos`
- `Things`
- `UndoStack`, `RedoStack`

Comptages:

- `AudioFiles`: 1177
- `MidiEvents`: 57
- `MidiMessages`: 62
- `DmxisCues`: 630
- `LightShows`: 1179
- `Sets`: 30
- `ShowMemos`: 10321

Ces bases sont conservées en copie dans l'audit car elles peuvent aider une migration depuis legacy, mais elles ne doivent pas être mélangées aux capacités Active.

## Possibilités d'intégration Velvet Show

### Option A: Velvet pilote Active via MIDI

✅ ShowBuddy Active

Approche recommandée en premier:

- Velvet Show envoie des notes/CC via IAC/CoreMIDI.
- Active reçoit MIDI pour banque/preset, MIDI Learn et éventuellement MIDI clock.
- Avantages: robuste, macOS natif, simple à tester, faible dépendance à des formats internes.
- Limites: moins expressif qu'une API complète; mapping à configurer dans Active.

### Option B: Velvet pilote Active via OSC

✅ ShowBuddy Active

Approche prometteuse mais à documenter:

- Active expose vraisemblablement un mode `OSC Remote Control`.
- Les ports entrée/sortie et adresse distante sont présents dans les chaînes.
- Velvet Show pourrait envoyer des messages UDP OSC pour sélectionner banques/presets, déclencher cues, lire état, etc.
- Limite: les adresses OSC exactes n'ont pas été trouvées. Ne pas implémenter côté Velvet avant validation contractuelle.

### Option C: Velvet génère ou prépare des fichiers Active

✅ ShowBuddy Active

Approche offline:

- Générer `DmxConfig.xml`, `bank.xml`, `.prt` depuis une setlist Velvet.
- Préparer des banques/presets Active synchronisés à la conduite.
- Avantages: les fichiers sont XML lisibles.
- Risques: format non officiellement stable; besoin de diff après sauvegarde par Active.

### Option D: Active comme backend lumière/vidéo complet

✅ ShowBuddy Active

Approche architecture:

- Velvet reste maître temporel live: playback, setlist, prompteur, remote, MIDI scheduler.
- Active rend lumière/vidéo: DMX/Art-Net/media/presets.
- Velvet déclenche Active par MIDI/OSC au temps voulu.

C'est la séparation la plus saine si Active est retenu.

## Limites et zones inconnues

- Aucune session runtime n'a été lancée.
- Aucun port OSC/MIDI n'a été testé.
- Pas de désassemblage ni contournement de licence.
- Pas d'extraction PDF complète car `pdftotext` absent.
- Les chaînes extraites du binaire indiquent des fonctionnalités mais pas un contrat API.
- Les chemins `ENTTEC/DMXIS` apparaissent dans les XML Active; il faut vérifier si Active garde une compatibilité DMXIS interne ou si ce sont des chemins historiques.
- Les fichiers legacy peuvent être utiles pour migration, mais ne prouvent rien sur Active.

## Recommandations techniques

1. Prioriser un prototype MIDI Velvet -> ShowBuddy Active via port IAC: sélection banque/preset, start/stop si disponible, MIDI clock si nécessaire.
2. Ouvrir Active et capturer l'écran de configuration OSC Remote Control: ports, host, exemples d'adresses, options banks/presets.
3. Créer un show Active minimal nommé explicitement `VelvetIntegrationTest`, sauvegarder, puis comparer les XML produits avec les samples copiés.
4. Tester Art-Net seulement après validation que Velvet veut déléguer le rendu DMX à Active.
5. Éviter une intégration directe `.prt` en production avant d'avoir confirmé la stabilité du format sur plusieurs sauvegardes Active.
6. Ne pas utiliser `ShowBuddy.db` legacy comme source de vérité Active. Le garder seulement pour migration d'anciens shows.
7. Si OSC est documenté, préférer OSC pour commandes nommées et MIDI pour fallback scène/live.

## Commandes utilisées

Commandes principales exécutées en lecture seule sur les originaux:

```sh
mkdir -p SHOWBUDDY_ACTIVE_AUDIT
find /Applications -iname '*showbuddy*' -o -iname '*show buddy*'
find '/Users/alexandrechalon/Library/Application Support' -iname '*showbuddy*' -o -iname '*show buddy*'
find '/Library/Application Support' -iname '*showbuddy*' -o -iname '*show buddy*'
find '/Users/alexandrechalon/Library/Preferences' -iname '*showbuddy*' -o -iname '*show buddy*'
find '/Users/alexandrechalon/Library/Containers' -maxdepth 3 -iname '*showbuddy*' -o -iname '*show buddy*' -o -iname '*dbaudioware*'
find '/Users/alexandrechalon/Library/Caches' -iname '*showbuddy*' -o -iname '*show buddy*' -o -iname '*dbaudioware*'
find '/Users/alexandrechalon/Documents' -iname '*showbuddy*' -o -iname '*show buddy*' -o -iname '*.sab'
find '/Users/Shared' -iname '*showbuddy*' -o -iname '*show buddy*' -o -iname '*dbaudioware*' -o -iname '*.sab'
find '/Library/Application Support/db audioware/Show Buddy Active' -print
find '/Applications/Show Buddy Active.app' -print
plutil -p '/Applications/Show Buddy Active.app/Contents/Info.plist'
plutil -p '/Users/alexandrechalon/Library/Preferences/com.dbaudioware.showbuddy.plist'
defaults read '/Users/alexandrechalon/Library/Preferences/com.dbaudioware.showbuddy.plist'
file '/Library/Application Support/db audioware/Show Buddy/ShowBuddy.db'
file '/Library/Application Support/db audioware/Show Buddy Active/Documentation/Show Buddy Active.pdf'
sqlite3 '/Library/Application Support/db audioware/Show Buddy/ShowBuddy.db' '.schema'
sqlite3 '/Library/Application Support/db audioware/Show Buddy/ShowBuddy.db' '.tables'
sqlite3 '/Library/Application Support/db audioware/Show Buddy/ShowBuddy.db' 'PRAGMA integrity_check;'
grep -RInE 'OSC|osc|MIDI|midi|ArtNet|Art-Net|Python|macro|preset|bank|fixture|universe|DMX|port|UDP|TCP|TouchOSC|API' ...
strings '/Applications/Show Buddy Active.app/Contents/MacOS/Show Buddy Active'
strings '/Library/Application Support/db audioware/Show Buddy Active/Documentation/Show Buddy Active.pdf'
find '/Library/Application Support/db audioware/Show Buddy Active/DmxLibrary' -type f -name '*.dmx'
find '/Library/Application Support/db audioware/Show Buddy/Media Files' -type f -name '*.dmxis'
find '/Library/Application Support/db audioware' '/Users/alexandrechalon/Documents' -type f -name '*.sab'
sed -n '1,120p' '/Library/Application Support/db audioware/Show Buddy Active/DmxLibrary/Generics/8 Way Dimmer.dmx'
sed -n '1,40p' '/Library/Application Support/db audioware/Show Buddy Active/Shows/Sample Show/General/Blackout.prt'
sed -n '1,40p' '/Library/Application Support/db audioware/Show Buddy Active/Shows/Sample Show/DmxConfig.xml'
pdftotext '/Library/Application Support/db audioware/Show Buddy Active/Documentation/Show Buddy Active.pdf' ...
mdls -name kMDItemTextContent '/Library/Application Support/db audioware/Show Buddy Active/Documentation/Show Buddy Active.pdf'
cp -R ...
```

Échecs ou limites notés:

- `find` sur `/Library/Application Support` a rencontré des `Permission denied` dans des dossiers Apple système.
- Première recherche `~/Library/Containers` interrompue par `fts_read: Interrupted system call`; relance limitée sans résultat.
- `pdftotext` absent: `zsh:1: command not found: pdftotext`.
- `mdls -name kMDItemTextContent` sur le PDF n'a pas fourni de texte exploitable.

## Fichiers produits

- `SHOWBUDDY_ACTIVE_FOR_VELVET.md`
- `SHOWBUDDY_ACTIVE_FINDINGS.json`
- `logs/find_show_buddy_active_support.txt`
- `logs/find_show_buddy_support_maxdepth4.txt`
- `logs/find_app_bundle.txt`
- `logs/find_documents_showbuddy.txt`
- `analysis/*`
- `copied_files/*`
