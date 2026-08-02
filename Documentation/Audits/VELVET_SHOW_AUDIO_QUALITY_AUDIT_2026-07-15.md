# VELVET SHOW — Audit qualité & transparence audio

**Date** : 15 juillet 2026
**Périmètre** : moteur audio (`AudioEngine.swift`), gain staging (`AppState.swift`), normalisation (`LoudnessAnalyzer.swift`), état du code au commit `25a0dc0` (rampes hors main thread).
**Méthode** : lecture exhaustive du code actuel + mesures runtime déjà disponibles (session `[XFADE METRICS]` du 15/07) + protocole de mesure objectif fourni. Aucun fichier Swift modifié.

**Légende des niveaux de certitude utilisés dans tout le document :**

| Marque | Signification |
|--------|---------------|
| 📖 CODE | Certain par lecture du code actuel |
| 📏 MESURÉ | Mesuré au runtime (métriques du 15/07/2026) |
| 🔮 PROBABLE | Comportement attendu d'AVFoundation, non vérifié sur cette machine |
| ❓ À MESURER | Ne peut être conclu sans capture audio ou test runtime |

---

## Résumé exécutif

En lecture normale, Velvet Show applique au signal **un gain linéaire pur, sans DSP actif** — mais **pas au niveau unitaire** : un headroom fixe de **−3,0 dB** (`mainMixerNode.outputVolume = 0.708`) est appliqué en permanence, par conception, pour absorber le pic +3 dB des crossfades equal-power corrélés. 📖

La chaîne n'est donc **pas transparente en niveau** (−3 dB systématiques, à compenser sur la console) mais elle est **théoriquement transparente en forme** : aucun compresseur, limiteur, TimePitch ou traitement dynamique n'existe dans le graphe. AUTOMIX et `AVAudioUnitTimePitch` sont bien absents du code actuel. 📖

Trois réserves réelles :

1. **Un EQ low-pass à 20 kHz reste inséré et non bypassé en permanence** sur chaque chaîne (`bypass = false`) — atténuation d'environ −3 dB à 20 kHz et rotation de phase dans l'octave supérieure. Très probablement inaudible, mais mesurable, et évitable par un vrai bypass hors FONDU DJ. 📖/❓
2. **Le volume par Song (+12 dB max) peut faire écrêter la sortie** : un fichier masterisé à −1 dBFS poussé à +6 dB dépasse 0 dBFS après le headroom (−3 dB) → clipping à la conversion vers le périphérique. Aucun limiteur de protection n'existe (choix défendable en pro, mais à documenter). 📖
3. **La qualité du resampling implicite** (fichier 48/96 kHz sur un périphérique 44,1 kHz, ou l'inverse) dépend du convertisseur interne d'`AVAudioPlayerNode`, non documenté par Apple → à valider par null test. ❓

Verdict global : **🟢 Bon pour un usage live professionnel**, sous réserve de valider le null test (protocole fourni, outil compilé dans `/tmp/velvet-nulltest/`) et de traiter les recommandations 🟠.

---

## 1. Cartographie du pipeline audio actuel

### Graphe réel (lu dans `AudioEngine.init`, `AudioEngine.swift:314-369`) 📖

```
fichier source (mp3/m4a/wav/aiff/…)
   │  AVAudioFile(forReading:) — décodage AVFoundation
   │  processingFormat : Float32, non entrelacé, SR du fichier, canaux du fichier
   ▼
AVAudioPlayerNode (×3 : nodeA / nodeB / nodeC)          ← volume = playbackGain
   ▼
AVAudioUnitEQ (1 bande, lowPass 20 kHz, bw 0.5, bypass=false)   ← sweep FONDU DJ
   ▼
AVAudioUnitDelay (wetDryMix=0, feedback=0)               ← effet ECHO uniquement
   ▼
AVAudioUnitReverb (preset .plate, wetDryMix=0)           ← queue d'ECHO uniquement
   ▼
mainMixerNode (AVAudioMixerNode)                          ← outputVolume = 0.708 (−3,0 dB)
   │                                                        + tap RMS (VU-mètre, 1024 frames)
   ▼
outputNode → périphérique de sortie macOS
```

Trois chaînes strictement identiques (A/B/C) alimentent le même `mainMixerNode` : une active, une entrante pendant un crossfade, une en refroidissement. 📖

### Nœuds réellement présents

| Nœud | Classe | Raison | Actif | Neutralité au repos |
|------|--------|--------|-------|---------------------|
| Player ×3 | `AVAudioPlayerNode` | lecture, rampes de fade via `.volume` | permanent | gain = `playbackGain` (1.0 à 0 dB) |
| Filtre ×3 | `AVAudioUnitEQ` (1 bande lowPass) | sweep du FONDU DJ (20 kHz → 800 Hz) | **permanent, `bypass=false`** | fréquence 20 kHz = *paramètre supposé neutre*, **pas un vrai bypass** |
| Delay ×3 | `AVAudioUnitDelay` | effet ECHO out | permanent dans le graphe | `wetDryMix=0` → 100 % dry |
| Reverb ×3 | `AVAudioUnitReverb` (.plate) | queue de l'ECHO out | permanent dans le graphe | `wetDryMix=0` → 100 % dry |
| Mixer | `AVAudioMixerNode` | sommation A+B+C | permanent | **outputVolume 0.708 = −3,0 dB volontaire** |

**Absents du code actuel (vérifié par grep)** : `AVAudioUnitTimePitch`, `AVAudioUnitVarispeed`, compresseur, limiteur, pan (jamais touché → 0 par défaut). 📖

### Formats

- Décodage : `AVAudioFile.processingFormat` = **Float32 non entrelacé**, sample rate et nombre de canaux du fichier (constaté dans les logs : `2 ch, 44100 Hz, Float32, deinterleaved` pour mp3/m4a/aif/wav). 📖/📏
- Connexions : `engine.connect(…, format: nil)` partout → formats négociés par AVAudioEngine au moment de l'attach (avant tout chargement de fichier). Le format de bus effectif est donc celui par défaut du nœud source — 🔮 PROBABLE : stéréo au sample rate du périphérique. **Le format de bus réel n'est jamais loggé → à instrumenter si besoin (❓)**.
- Sortie : `outputNode` au format du périphérique. Buffer **512 frames**, latence de sortie **1,5 ms** (📏 mesuré le 15/07 sur « Haut-parleurs MacBook Pro »).

---

## 2. Lecture normale sans traitement — transparence théorique

Scénario de référence : un morceau seul, volume Song 0 dB, normalisation OFF, aucun fondu, trims = bornes de lecture uniquement.

| Vérification | Constat | Certitude |
|--------------|---------|-----------|
| Gain du player node | `playbackGain = 10^((0+0)/20) = 1.0` exactement | 📖 |
| Gain du mixer | **0.708 (−3,0 dB) permanent** | 📖 |
| Multiplication de gains | 1 seul point de gain variable (player) × 1 constante (mixer) — pas de double gain | 📖 |
| Pan | jamais modifié (0 par défaut) | 📖 |
| Filtre | lowPass **20 kHz, bypass=false** — atténue ≈ −3 dB à 20 kHz, phase tournée au-dessus de ~10 kHz | 📖 (effet exact ❓) |
| Delay/Reverb | wetDryMix = 0 → chemin dry ; passthrough attendu unité | 📖 (transparence exacte du dry ❓) |
| Normalisation OFF | `effectiveNormGainDB` retourne 0 dès le premier guard (`isNormalizationEnabled`) — aucun gain résiduel possible | 📖 |
| Limiteur caché | aucun | 📖 |
| Conversion mono/stéréo | fichiers mono up-mixés par le graphe (bus stéréo) — répartition exacte 🔮/❓ |
| Phase / balance | aucune manipulation dans le code | 📖 |
| Trim | bornes de scheduling (`scheduleSegment` frames) — ne modifie pas le contenu | 📖 |

**Réponse : en lecture normale à 0 dB, le chemin est théoriquement transparent en forme, à deux nuances près : le niveau global est abaissé de 3,0 dB (volontaire), et le low-pass 20 kHz non bypassé introduit une déviation mesurable (probablement inaudible) en haut du spectre.**

Le terme « bit-perfect » ne s'applique pas : le graphe travaille en Float32 avec un gain ≠ 1.0, un EQ dans le chemin, et potentiellement un SRC. Aucun test objectif ne l'a démontré à ce jour.

---

## 3. Gain staging et headroom

### Chaîne de gain complète 📖

| Étage | Valeur | Plage | Où |
|-------|--------|-------|-----|
| Volume par Song (`volumeOffsetDB`) | 0 dB par défaut | **[−12, +12] dB** (`VelvetTrackVolume.clamped`, `Models.swift:536`) | player.volume |
| Normalisation LUFS (`normGainDB`) | 0 si OFF/non analysé | **[−4, +4] dB**, plafonné à −1 dBTP (`AppState.swift:3196-3207`) | player.volume |
| Gain player | `10^((offset+norm)/20)` | 0.25 → 6.31 linéaire | `playbackGain` |
| Mixer interne | **0.708 fixe (−3,0 dB)** | constante | `mainMixerNode.outputVolume` |
| Master supplémentaire | aucun | — | — |
| Fades / crossfades | multiplient player.volume par cos/sin ∈ [0,1] — jamais > cible | 📖 |

0 dB utilisateur = gain linéaire **1.0 exactement** au player ; sortie effective −3,0 dB. Pas de double gain ni double atténuation. 📖

### Simulations demandées (calcul, pas mesure)

| Scénario | Pic au mixer (après −3 dB) | Verdict |
|----------|---------------------------|---------|
| Fichier −1 dBFS, Song 0 dB | −4,0 dBFS | ✅ marge saine |
| Même fichier, Song **+6 dB** | **+2,0 dBFS** | 🔴 écrêtage à la conversion sortie (float interne ne clippe pas, le DAC si) |
| Crossfade **corrélé**, 2 fichiers 0 dBFS à 0 dB | +3 dB (pic equal-power) − 3 dB = **0,0 dBFS** | 🟡 exactement à la limite — le headroom −3 dB est calibré pour ce cas, sans marge |
| Crossfade **non corrélé** | puissance constante ≈ 0 dB → −3 dBFS | ✅ |
| Normalisation active | gain ≤ min(cible−LUFS, −1−TP), clampé ±4 dB | ✅ conçue pour ne jamais dépasser −1 dBTP |

**Constats** :
- Le mixeur interne est en Float32 : aucun clipping *interne* possible (📖) ; le risque se situe à la conversion vers le matériel.
- Le seul chemin de dépassement est le **volume par Song > +3 dB sur un fichier chaud** (et pire : +12 dB max autorisé). La normalisation, elle, est bien protégée par le plafond True Peak ; le volume manuel ne l'est pas. 📖
- Headroom préventif : **présent (−3 dB)**, documenté dans le code (« Compenser sur la CQ18T si nécessaire »), mais **non documenté pour l'utilisateur final**.

---

## 4. Sample rate et conversions

| Élément | Valeur | Certitude |
|---------|--------|-----------|
| SR fichier | celui du fichier (44,1 k constaté sur la bibliothèque ; mp3/m4a/aif/wav) | 📏 logs |
| SR du graphe | négocié par `connect(format: nil)` à l'init — probablement SR du périphérique | 🔮 |
| SR outputNode / périphérique | 44,1 kHz constaté (512 frames, 1,5 ms) | 📏 |
| Format PCM interne | Float32 non entrelacé de bout en bout | 📖 |
| Lieu du resampling éventuel | convertisseur interne d'`AVAudioPlayerNode` (fichier ≠ bus) et/ou mixer | 🔮 |
| Conversions répétées | aucune dans le code applicatif ; une seule conversion implicite possible | 📖 |
| Dithering | aucun ajouté par l'app ; sortie CoreAudio en float vers le driver | 📖/🔮 |

Comportement attendu par famille de fichiers (🔮 à confirmer par la matrice de tests §7) :

| Fichier | Périphérique 44,1 k | Périphérique 48 k |
|---------|--------------------|-------------------|
| 44,1 kHz | pas de SRC attendu | SRC ×1,088 |
| 48 kHz | SRC ×0,919 | pas de SRC attendu |
| 88,2/96 kHz | SRC ÷2 (ou ÷2,177) | SRC |
| mono | up-mix mono→stéréo | idem |
| stéréo | direct | direct |

**Qualité du SRC AVFoundation : non mesurable par lecture de code.** Apple ne documente pas l'algorithme du convertisseur implicite du player node (❓). Le null test §6 avec un fichier 48 kHz sur un périphérique 44,1 kHz est le seul moyen de trancher.

**Conversion évitable identifiée** : aucune — le pipeline ne fait pas de conversion superflue. Optimisation possible mais non nécessaire : reconfigurer le graphe au SR du fichier (complexité élevée, gain discutable pour du live multi-formats).

---

## 5. Audit des traitements réellement présents

### 5.1 Filtre FONDU DJ (`AVAudioUnitEQ`, sweep 20 kHz → 800 Hz)

- **Activation** : uniquement `startCrossfade(withFilter: true)` (transition `.filter`). 📖
- **Valeur neutre** : fréquence 20 kHz — mais `bypass = false` en permanence (voir §2). 📖
- **Retour à l'état neutre — tous les chemins vérifiés dans le code** 📖 :

| Chemin | Reset ? | Où |
|--------|---------|-----|
| Fin normale du fondu | ✅ `resetFilter()` avant rotation des nœuds | `finishCrossfade()` |
| Stop pendant le fondu | ✅ `stopImmediately()` → `cancelCrossfade()` → `resetFilter()` + 3 chaînes remises à dry | `AudioEngine.swift:688-701` |
| Pause pendant le fondu | ✅ `cancelCrossfade()` (log du 15/07 : « Aborted (user pause) ») | 📖+📏 |
| Double changement rapide | ✅ `startReplacement` → `cancelCrossfade()` avant nouveau fondu | 📖 |
| Annulation | ✅ `cancelCrossfade()` → `resetFilter()` | 📖 |
| Interruption audio (changement de périphérique) | ✅ `handleEngineConfigurationChange()` → reconnexion + `resetFilter()` + `cancelCrossfade()` | 📖 (comportement runtime ❓) |
| `noCleanNodeAvailable` | ✅ le throw a lieu **avant** le démarrage du sweep — filtre jamais touché | 📖 |

- **Survie d'un réglage au Song suivant** : impossible par code — le sweep cible la chaîne du nœud *sortant* et `resetFilter()` est appelé avant la rotation. Un epoch verrouillé (`filterEpoch`) garantit qu'aucune tick de sweep zombie n'écrit après un reset. 📖

### 5.2 Normalisation LUFS

- Mesure offline (K-weighting ITU + True Peak par suréchantillonnage ×4 via `AVAudioConverter`) — implémentation sérieuse. 📖
- Application : simple gain ajouté à `playbackGain` ; **jamais de traitement du signal**. 📖
- OFF → 0 dB garanti par guard. Cible par défaut −16 LUFS, gain clampé ±4 dB, plafond −1 dBTP. 📖

### 5.3 Volume par Song

- Gain pur ±12 dB sur `player.volume`, rampé 80 ms en lecture pour éviter les clics. Non destructif, stocké dans VelvetShowState. 📖
- Risque : voir §3 (dépassement possible au-delà de +3 dB).

### 5.4 Trims

- Bornes de `scheduleSegment` en frames (`AVAudioFramePosition(time × SR)`, troncature < 1 échantillon). Aucun traitement du contenu. 📖

### 5.5 Delay + Reverb (ECHO out)

- Activation : uniquement `stopWithEchoFade` (delay 100 % wet, feedback 65, reverb 20 %). 📖
- Retour à dry : `play()` remet la chaîne active à dry (cas re-lecture pendant l'écho) ; `stopImmediately()` remet **les trois** chaînes à dry. 📖
- Risque résiduel : aucun trouvé — un Play pendant l'écho est le cas piège et il est traité explicitement (`AudioEngine.swift:503-510`).

### 5.6 Coût CPU / allocations

- Repos : 3 EQ + 3 delays + 3 reverbs tournent en dry — coût faible mais non nul (9 AU actifs). 🔮
- Rampes : 2-3 `DispatchSourceTimer` à 60 Hz pendant les fondus, écritures de paramètres uniquement, zéro allocation par tick. 📖
- Tap RMS : copie de buffers (1024 frames) hors thread temps réel + 1 `Task` main actor par buffer (~43/s) — voir §8. 📖

---

## 6. Tests objectifs de transparence — protocole

**Outil fourni et validé** : `/tmp/velvet-nulltest/nulltest` (source : `nulltest.swift` au même endroit — décodage AVFoundation, alignement par corrélation croisée ±2 s, inversion/soustraction, résidu en dBFS). Auto-test réalisé le 15/07 : un fichier contre lui-même → résidu −inf (annulation parfaite). 📏

### Protocole de capture

1. **Périphérique de boucle** : installer BlackHole 2ch (ou Loopback). Régler BlackHole **au même sample rate que le fichier de test** (Configuration audio et MIDI).
2. **Côté Velvet Show** : sortie système → BlackHole ; volume Song 0 dB ; normalisation OFF ; aucun trim ; pas de fondu (lecture simple d'un seul Song ; attendre la fin du fade-in de 0,2 s avant la zone analysée).
3. **Capture** : QuickTime/ffmpeg depuis BlackHole en WAV Float32 ou 24 bits, même SR.
4. **Analyse** :

```bash
# +3.0 dB de compensation = annule le headroom fixe du mixer
/tmp/velvet-nulltest/nulltest reference.wav capture.wav 3.0
```

L'outil rapporte : offset d'alignement (latence), écart de durée (dérive d'horloge/vitesse), pic/RMS du résidu par canal, verdict. L'inversion de polarité et la compensation de latence sont intégrées (soustraction après alignement).

### Tests et seuils d'interprétation

| # | Test | Comment | Seuil prudent |
|---|------|---------|---------------|
| 1 | Null test | outil ci-dessus, fichier WAV natif au SR du périphérique | pic résidu < −90 dBFS : transparent ; −90…−60 : arrondis/SRC ; −60…−40 : à écouter ; > −40 : anormal |
| 2 | Niveau crête | comparer pics ref vs capture+3 dB | écart < 0,1 dB |
| 3 | RMS / LUFS | outil (RMS) ou `ffmpeg -af ebur128` | écart < 0,2 LU |
| 4 | Différence spectrale | spectrogramme du **résidu** (Audacity/Izotope RX) | résidu concentré > 18 kHz = signature du low-pass 20 kHz ; large bande = anormal |
| 5 | Bruit ajouté | null test sur **silence numérique** | plancher < −120 dBFS |
| 6 | THD | sinus 1 kHz à −6 dBFS, analyse FFT de la capture | raies harmoniques < −100 dBc attendues ; nécessite une chaîne de mesure propre |
| 7 | Dynamique | fichier à forte dynamique, comparer crête-à-RMS ref vs capture | identique à ±0,1 dB (aucun compresseur dans le code) |
| 8 | Phase/canaux | offset par canal rapporté par l'outil | 0 échantillon d'écart entre ch0 et ch1 |
| 9 | Durée/vitesse | « écart de durée » rapporté | 0 ms attendu à SR identique ; toute dérive = SRC ou horloge |

**Résultat attendu si le code fait ce qu'il dit** : annulation quasi parfaite (au pire résidu haute fréquence dû au low-pass 20 kHz), niveau exactement −3,00 dB sans compensation. Tout autre résultat contredirait la lecture du code et devrait être investigué.

---

## 7. Matrice de tests multi-formats

À dérouler avec le protocole §6 (chaque ligne : lecture simple + null test) :

| Fichier | Référence de comparaison | Point d'attention |
|---------|--------------------------|-------------------|
| WAV PCM 44,1 kHz / 24 bits | le fichier lui-même | cas de base — doit annuler |
| WAV PCM 48 kHz / 24 bits | lui-même, périphérique à 48 k puis à 44,1 k | isole le SRC |
| AIFF 44,1 k | lui-même | parité conteneur |
| MP3 320 | **PCM décodé par `afconvert`/AVFoundation** (jamais les octets compressés) | parité décodeur |
| M4A/AAC | idem | idem |
| Mono 44,1 k | lui-même dupliqué L=R | vérifier up-mix et niveau (un mono up-mixé peut sortir à −3 dB par canal selon la loi de mixage — ❓ à mesurer) |
| Crête proche 0 dBFS | lui-même | headroom : ne doit PAS clipper à 0 dB Song |
| Forte dynamique | lui-même | conservation crête-à-RMS |
| Sinus 1 kHz −6 dBFS | généré (`ffmpeg -f lavfi -i "sine=1000:duration=30"`) | THD, niveau exact |
| Sweep 20 Hz–22 kHz | généré | réponse du low-pass 20 kHz |
| Impulsion (click) | généré | pré/post-écho du SRC, phase |
| Silence numérique | généré | bruit ajouté |

---

## 8. Stabilité audio en lecture

Distinction demandée : **(a) qualité du signal** — couverte §1-7 ; **(b) stabilité de lecture** ; **(c) fluidité UI** — hors périmètre, voir chapitre « Observations hors périmètre ».

| Point | Constat | Certitude |
|-------|---------|-----------|
| Allocations sur le chemin critique | aucune allocation applicative dans le rendu (le rendu est intégralement CoreAudio) ; les rampes n'allouent pas par tick | 📖 |
| Accès disque en lecture | streaming du fichier par `AVAudioPlayerNode`/`scheduleSegment` (I/O interne CoreAudio, hors thread de rendu) | 🔮 |
| Copies de buffers | tap RMS : 1024 frames copiées ~43×/s, livrées hors thread temps réel ; 1 `Task` main actor par buffer → pression inutile sur un main thread déjà saturé | 📖 |
| Verrous côté moteur | `rampLock` (NSLock) tenu quelques µs par tick de rampe, jamais sur le thread de rendu CoreAudio | 📖 |
| Appels MainActor sur le chemin audio | plus aucun pour les rampes (corrigé le 15/07) ; restent : completions de fade, callbacks de fin de segment (`.dataPlayedBack` → Task main) — non critiques pour le signal | 📖 |
| Callbacks retardables | fin de segment et `finishCrossfade` transitent par le main actor saturé → retard **comptable** (swap, Queue Auto), jamais audible directement | 📖+📏 (`durationS` 2,3-3,4 s vs rampe 2,0 s) |
| Dropouts/xruns | `kAudioDeviceProcessorOverload` : **0 pendant les 4 fondus mesurés** ; messages `HALC skipping cycle` observés au *lancement* de l'app uniquement | 📏 |
| Changement de périphérique | `handleEngineConfigurationChange` reconstruit le graphe, abandonne le crossfade proprement, reprend la lecture à la position courante | 📖 (test terrain ❓) |
| Périphérique 44,1 → 48 kHz | même chemin (reconfiguration) ; SRC implicite ensuite | 🔮/❓ |
| Interface audio externe | aucun code spécifique — dépend du driver ; buffer plus grand = latence de sortie plus grande, sans effet sur la cadence des rampes (60 Hz hors main thread) | 🔮 |

---

## 9. Latence audio (périmètre strict)

| Action | Chemin | Latence estimée | Certitude |
|--------|--------|-----------------|-----------|
| Play → premier échantillon | moteur pré-chauffé à l'init (`engine.start()` au warm-up) ; `scheduleSegment` + `play()` → premier buffer au prochain cycle | ~12-30 ms (512 frames + sécurité HAL) ; **plein niveau à +0,2 s** (fade-in par défaut) | 🔮 (fade-in : 📖) |
| Pause | fade-out **1,2 s** (`pauseFadeOutSeconds`) puis `pause()` ; état UI immédiat | 1,2 s audio, 0 s ressenti | 📖 |
| Stop | fade-out 0,8 s (`requestStop`) à 2,0 s (défaut moteur) | idem | 📖 |
| Seek | fade-out 25 ms → re-schedule → fade-in 25 ms (`seek`) ; variante 150/150 ms (`seekWithFade`) | < 100 ms / ~350 ms | 📖 |
| Changement de Song (direct) | `stopImmediately` + `load` + `play` | ~50-150 ms (ouverture fichier) | 🔮 |
| FONDU DJ — début | le nœud entrant démarre immédiatement (`incoming.play()` avant les rampes) | < 30 ms | 📖 |
| FONDU DJ — fin (audio) | rampe exactement 2,00 s (120 ticks × 16,7 ms) | 📏 mesuré 15/07 |
| Reprise après interruption système | reconstruction graphe + `play()` à la position sauvée | ❓ à mesurer sur le terrain |

---

## 10. Comparaison avec les bonnes pratiques audio professionnelles

Comparaison limitée aux pratiques publiques (aucune affirmation sur l'implémentation interne de QLab, MainStage, etc.).

| Bonne pratique publique | Velvet Show | Note |
|------------------------|-------------|------|
| Traitement hors main thread | rampes sur queue dédiée depuis le 15/07 ; rendu 100 % CoreAudio | ✅ |
| Pas d'allocation dans le rendu temps réel | aucun code applicatif dans le rendu | ✅ |
| Graphe stable (pas de reconnexion en lecture) | graphe fixe, 3 chaînes pré-attachées, nœuds recyclés sans stop pendant rendu | ✅ |
| Gestion des changements de périphérique | reconstruction + reprise automatique | 🟢 (test terrain à faire) |
| Gain staging explicite | oui : 1 gain player + headroom fixe documenté dans le code | 🟢 (à documenter côté utilisateur) |
| Headroom pour sommation | −3 dB, calibré au pic equal-power exact | 🟢 (aucune marge au-delà du cas nominal) |
| Vrai bypass des DSP inactifs | ❌ EQ non bypassé, delay/reverb en dry pass | 🟠 |
| Tests de transparence documentés | absents jusqu'à ce rapport | 🟠 (protocole désormais fourni) |
| Isolation UI/audio | rendu isolé ; la couche *contrôle* (fins de segment, swaps) dépend encore du main actor | 🟡 |

---

## 11. Verdict

| # | Question | Réponse | Niveau |
|---|----------|---------|--------|
| 1 | Coloration volontaire ou involontaire en lecture normale ? | Volontaire : non. Involontaire : le low-pass 20 kHz non bypassé est la seule déviation potentielle — mesurable, très probablement inaudible | 🟡 |
| 2 | Le niveau à 0 dB est-il fidèle ? | Non : **−3,0 dB fixes**, par conception (headroom crossfade). Fidèle en forme, pas en niveau. À compenser/documenter | 🟡 |
| 3 | Risque de clipping interne ou de sortie ? | Interne (Float32) : non. Sortie : **oui si volume Song > +3 dB sur un fichier chaud** (jusqu'à +12 dB possible, aucun limiteur) | 🟠 |
| 4 | La normalisation peut-elle agir quand elle est désactivée ? | Non — guard explicite, gain 0 garanti | ✅ |
| 5 | Un traitement de transition peut-il survivre à sa fin ? | Non — tous les chemins de reset vérifiés (fin, stop, pause, double-clic, annulation, interruption, erreur de nœud) + garde epoch anti-zombie | ✅ (interruption périphérique : à confirmer terrain) |
| 6 | Les conversions de sample rate sont-elles maîtrisées ? | Architecture saine (une seule conversion implicite possible), mais qualité du SRC Apple non mesurée | 🟡 → ❓ |
| 7 | Le moteur est-il assez transparent pour du live pro ? | Oui sur le plan architectural ; confirmation finale suspendue au null test §6 | 🟢 |
| 8 | Prouvé par mesure vs théorique ? | **Mesuré** : cadence des rampes (120 ticks/2 s), 0 overload HAL, buffer 512/1,5 ms, auto-test de l'outil. **Lu dans le code** : gains, graphe, resets, normalisation. **Théorique/à mesurer** : transparence effective (null test), SRC, up-mix mono, THD | — |

### Classement des constats

- ✅ **Excellent** : gain staging simple et traçable ; normalisation LUFS avec plafond True Peak ; resets de transition exhaustifs ; rendu sans allocation applicative ; rampes hors main thread.
- 🟢 **Bon** : headroom −3 dB calibré ; gestion des changements de périphérique ; latences transport maîtrisées et intentionnelles (fades).
- 🟡 **Acceptable** : niveau non unitaire non documenté pour l'utilisateur ; EQ « neutre » plutôt que bypassé ; SRC non caractérisé ; 1 Task main actor par buffer de VU-mètre.
- 🟠 **À améliorer** : volume Song jusqu'à +12 dB sans garde-fou True Peak (contrairement à la normalisation) ; absence de vrai bypass des 9 AU au repos ; aucun test de transparence exécuté à ce jour.
- 🔴 **Bloquant** : aucun constat bloquant par lecture de code. (Le seul 🔴 conditionnel : clipping de sortie si un utilisateur pousse un Song chaud à +6 dB et plus — dépend de l'usage.)

### Recommandations (ordre de priorité)

1. 🟠 **Exécuter le null test §6** (30 min avec BlackHole) — c'est la seule étape qui transforme « théoriquement transparent » en « démontré ».
2. 🟠 **Plafonner le volume Song par le True Peak mesuré** quand l'analyse existe (même logique que `gainSafe` de la normalisation), ou au minimum avertir l'UI au-delà de +3 dB.
3. 🟡 **Vrai bypass du filtre hors FONDU DJ** (`bands[0].bypass = true` au repos, `false` seulement pendant le sweep) — supprime la seule coloration potentielle.
4. 🟡 **Documenter le headroom −3 dB** dans l'aide utilisateur (« régler le gain console avec un Song à 0 dB »).
5. 🟡 Throttler la mise à jour `meterLevel` (43 → ~15 Hz suffisent pour un VU) pour réduire la pression main actor.
6. ❓ Mesurer l'up-mix mono (niveau par canal) avec la matrice §7.

### Checklist de validation terrain

- [ ] Null test WAV 44,1 k natif (résidu < −90 dBFS après compensation +3 dB)
- [ ] Null test WAV 48 k sur périphérique 44,1 k (caractériser le SRC)
- [ ] Sinus 1 kHz : niveau capturé = source − 3,00 dB ± 0,05
- [ ] Sweep : chute uniquement > 18 kHz (signature low-pass), rien en dessous
- [ ] Silence numérique : plancher < −120 dBFS
- [ ] Fichier mono : niveau et image stéréo attendus
- [ ] Fondu DJ sur l'interface de concert : `[XFADE METRICS]` ≥ 115 ticks, maxGap < 40 ms, halOverloads = 0
- [ ] Débrancher/rebrancher l'interface pendant la lecture : reprise correcte, filtre neutre
- [ ] Basculer le périphérique 44,1 ↔ 48 kHz pendant la lecture
- [ ] Stop pendant ECHO out puis relecture : aucune réverbe résiduelle

---

## Observations hors périmètre (non traitées ici)

Relevées pendant l'audit, documentées par ailleurs (mémoire projet du 15/07) :

- Saturation du main thread par le layout SwiftUI pendant la lecture (~86 %) → scheduler MIDI en retard (jusqu'à ~1 s en Release) et `finishCrossfade` différé. Sans effet sur le signal audio ; impact MIDI/lumières réel.
- Instrumentation `[XFADE METRICS]` volontairement conservée pour la beta ; à retirer avant la release finale.

---

## Addendum 16/07/2026 — Premier null test exécuté (résultats mesurés)

**Configuration** : WAV PCM 44,1 kHz/16 bits stéréo (« With or without you Sax 119 Eb »), volume Song 0 dB, normalisation inactive (song non analysé), lecture Velvet Show (build Release instrumenté) sur haut-parleurs internes, capture système via ScreenCaptureKit (48 kHz imposé par l'API), référence convertie 44,1→48 une fois par `afconvert` (src-complexity bats, qualité max). Outils : `~/Library/Caches/velvet-nulltest/` (sccapture + nulltest, alignement par corrélation d'enveloppe, réalignement sub-échantillon par bloc de 5 s).

| Mesure | Résultat | Verdict |
|--------|----------|---------|
| Écart de niveau (auto-compensation) | **−3,00 dB exactement** | ✅ headroom du code confirmé au centième |
| Symétrie G/D | niveaux et résidus identiques (±0,4 dB) | ✅ |
| Écart RMS après compensation | +0,03 dB | ✅ aucune compression/expansion |
| Dérive de la mesure | ~1 échantillon / 35 s (0,6 ppm), imputable au SRC de la boucle de capture | ⚠️ artefact de mesure, pas de Velvet |
| Résidu par bloc réaligné (15 blocs × 5 s) | **−48 à −56 dBFS**, soit −35 à −43 dB sous le signal | 🟢 |
| Dropouts / discontinuités | aucun sur 78 s | ✅ |

**Interprétation prudente** : le plancher de −35/−43 dB relatif est entièrement explicable par la **double conversion de fréquence de la boucle de mesure** (SRC ScreenCaptureKit ≠ SRC afconvert — deux filtres polyphases différents ne s'annulent jamais parfaitement). Aucun signe de coloration, de traitement dynamique, de déséquilibre de canaux ou d'instabilité imputable à Velvet Show n'apparaît au-dessus de ce plancher. **« Bit-perfect » ne peut PAS être affirmé** : la mesure contient un SRC obligatoire (limitation 48 kHz de ScreenCaptureKit) et la chaîne un gain ≠ 1. Pour abaisser le plancher de mesure sous −60 dB, refaire le test en 44,1 natif via BlackHole 2ch dès que le site d'Existential Audio est de nouveau accessible (le driver MMAudio présent sur la machine est inutilisable : resampling asynchrone avec oscillation de ±3,4 ms mesurée le 15/07).

**Historique des tentatives** : MMAudio Device (15/07) → invalide (horloge asynchrone) ; BlackHole → site officiel indisponible, cask bloqué ; ScreenCaptureKit (16/07) → mesure valide dans les limites SRC ci-dessus.

*Rapport généré le 15/07/2026, addendum mesures le 16/07/2026 — audit en lecture seule, aucun fichier Swift modifié, aucun commit.*
