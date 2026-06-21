//
//  AudioEngine.swift
//  VELVET SHOW
//
//  Moteur de lecture audio — Phase Audio 0.
//
//  Rôle minimal :
//  - charger un fichier audio (mp3, wav, aiff, m4a... tout ce que
//    AVAudioFile sait lire),
//  - le jouer / mettre en pause / arrêter,
//  - exposer en continu la position (TimeInterval), la durée totale
//    du fichier, et les bornes de trim (start / end) issues du LightShow.
//
//  Ce que le moteur NE fait PAS encore, volontairement :
//  - pas d'autoplay enchaîné song suivant,
//  - pas de scheduling MIDI synchronisé au playhead (Phase MIDI 2),
//  - pas de waveform préchargée,
//  - pas de click track (2e sortie stéréo, Phase Audio 1),
//  - pas de fade in/out global (Phase Audio 1),
//  - pas d'application de TrimStart / TrimEnd : on les stocke seulement
//    for les phases suivantes,
//  - pas de seek utilisateur : la lecture reprend depuis la dernière
//    position de pause, ou depuis 0 après Stop.
//
//  Position : for V0, on track le temps écoulé via `CACurrentMediaTime`
//  depuis l'instant où `play()` a été appelé. C'est précis at ±quelques ms
//  et largement suffisant for piloter Prompter + barre de progression.
//  Le scheduling fin viendra via `playerNode.lastRenderTime` quand la
//  Phase MIDI 2 demandera une précision sub-frame for les events.
//
//  Sandbox : sur macOS App Sandbox, les fichiers hors container ne sont
//  accessibles qu'avec un security-scoped resource. `load(...)` accepte
//  un `accessFolder` optionnel — une URL résolue depuis un bookmark
//  utilisateur — qu'il ouvre avec `startAccessingSecurityScopedResource`
//  et qu'il garde ouvert pendant toute la durée du fichier chargé.
//

import Foundation
import AVFoundation
import QuartzCore  // CACurrentMediaTime

@MainActor
@Observable
final class AudioEngine {

    // MARK: - Types

    enum PlaybackState: Equatable {
        case stopped
        case paused
        case playing
        case stopping
    }

    enum AudioError: LocalizedError {
        case noPath
        case fileUnreadable(String)
        case engineStartFailed(String)
        case noCleanNodeAvailable

        var errorDescription: String? {
            switch self {
            case .noPath:                   return "Le song n'a pas de chemin (Path NULL)."
            case .fileUnreadable(let m):    return "Cannot play: \(m)"
            case .engineStartFailed(let m): return "AVAudioEngine startup: \(m)"
            case .noCleanNodeAvailable:     return "Crossfade refused: no clean node available."
            }
        }
    }

    // MARK: - État observable

    private(set) var state: PlaybackState = .stopped

    /// URL du fichier actuellement chargé (nil si rien n'est chargé).
    private(set) var currentURL: URL?

    /// Duration totale du fichier audio, en secondes.
    private(set) var totalDuration: TimeInterval = 0

    /// Position de lecture, en secondes depuis le début du fichier
    /// (NON relative au trim).
    /// Mise at jour at ~30 Hz par le timer UI — utilisée for l'affichage.
    /// Pour le scheduling MIDI, préférer `livePosition`.
    private(set) var currentPosition: TimeInterval = 0

    /// Position calculée en ligne depuis `CACurrentMediaTime()`, sans
    /// passer par le cache du timer UI (30 Hz).
    /// Staleness : 0 ms. Fiable même sous HALC overload.
    /// Retourne `currentPosition` si le moteur n'est pas en lecture.
    var livePosition: TimeInterval {
        guard state == .playing else { return currentPosition }
        let elapsed = CACurrentMediaTime() - playStartHostTime
        return min(effectiveEnd, positionAtPlayStart + elapsed)
    }

    /// Trim start, en secondes depuis le début du fichier. 0 = pas de trim.
    private(set) var trimStart: TimeInterval = 0

    /// Trim end, en secondes depuis le début du fichier.
    /// 0 = pas de trim de fin (on lit jusqu'à `totalDuration`).
    private(set) var trimEnd: TimeInterval = 0

    /// Offset de volume non destructif appliqué au song chargé.
    /// 0 dB = volume original, borné par AppState at [-12 dB, +12 dB].
    private(set) var volumeOffsetDB: Double = 0

    /// Dernière erreur — affichée éventuellement at l'utilisateur.
    private(set) var lastError: String?

    /// Niveau RMS courant (0..1) — mis at jour ~30 Hz par le tap audio.
    /// Consommé par le VU-mètre dans l'UI concert.
    private(set) var meterLevel: Float = 0

    // MARK: - Valeurs dérivées for l'UI

    /// Start effectif de la lecture (= `trimStart`).
    ///
    /// 0 si aucun trim de début n'est défini. Les trims sont appliqués
    /// par le moteur depuis la Phase Audio 1 : `play()` démarre à
    /// `effectiveStart`, `scheduleSegment` borne le segment à
    /// `[effectiveStart, effectiveEnd]`.
    var effectiveStart: TimeInterval {
        max(0, min(trimStart, totalDuration))
    }

    /// Borne "fin" effective.
    ///
    /// Si `trimEnd > 0` et valide (> trimStart, ≤ totalDuration), c'est
    /// `trimEnd`. Sinon, on lit jusqu'à la fin du fichier.
    var effectiveEnd: TimeInterval {
        let end = trimEnd
        if end > effectiveStart, end <= totalDuration {
            return end
        }
        return totalDuration
    }

    /// Duration jouable = fenêtre de lecture effective.
    var effectiveDuration: TimeInterval {
        max(0, effectiveEnd - effectiveStart)
    }

    /// Position affichée dans la barre de progression, relative au
    /// début effectif (0 = `trimStart`, `effectiveDuration` = `trimEnd`).
    var effectivePosition: TimeInterval {
        max(0, min(effectiveDuration, currentPosition - effectiveStart))
    }

    /// Temps restant dans la fenêtre de lecture effective.
    var effectiveRemaining: TimeInterval {
        max(0, effectiveDuration - effectivePosition)
    }

    // MARK: - CoreAudio internals

    private let engine = AVAudioEngine()

    // Nœud A — chaîne complète filtre/delay/reverb
    private let nodeA       = AVAudioPlayerNode()
    private let filterNodeA = AVAudioUnitEQ(numberOfBands: 1)
    private let delayNodeA  = AVAudioUnitDelay()
    private let reverbNodeA = AVAudioUnitReverb()

    // Nœud B — chaîne complète filtre/delay/reverb
    private let nodeB       = AVAudioPlayerNode()
    private let filterNodeB = AVAudioUnitEQ(numberOfBands: 1)
    private let delayNodeB  = AVAudioUnitDelay()
    private let reverbNodeB = AVAudioUnitReverb()

    // Nœud C — chaîne complète filtre/delay/reverb
    private let nodeC       = AVAudioPlayerNode()
    private let filterNodeC = AVAudioUnitEQ(numberOfBands: 1)
    private let delayNodeC  = AVAudioUnitDelay()
    private let reverbNodeC = AVAudioUnitReverb()

    private var audioFile: AVAudioFile?
    var onPlaybackEndished: (() -> Void)?
    nonisolated(unsafe) private var scopedFolderURL: URL?
    nonisolated(unsafe) private var timer: Timer?
    nonisolated(unsafe) private var fadeTimer: Timer?
    nonisolated(unsafe) private var filterTimer: Timer?
    private var filterGeneration: Int = 0
    private var fadeGeneration: Int = 0
    private var meterTapInstalled = false
    private var playStartHostTime: TimeInterval = 0
    private var positionAtPlayStart: TimeInterval = 0
    private var didEndishSegment: Bool = false
    private var scheduleEpoch: Int = 0
    private var hasEverPlayed: Bool = false   // [AUDIO-DIAG] premier play détection
    private(set) var isSeeking: Bool = false

    // MARK: - Crossfade internals

    private var crossfadeFile: AVAudioFile?
    private var crossfadeURL: URL?
    nonisolated(unsafe) private var crossfadeScopedFolderURL: URL?
    private var crossfadeTotalDuration: TimeInterval = 0
    private var crossfadeTrimStart: TimeInterval = 0
    private var crossfadeTrimEnd: TimeInterval = 0
    private var crossfadeVolumeOffsetDB: Double = 0
    private var crossfadeNormGainDB: Double = 0

    /// Gain de normalisation LUFS appliqué au song actif (dB).
    /// Mis at jour par AppState via setNormGainDB(_:) avant la lecture.
    var normGainDB: Double = 0
    private var crossfadeStartHostTime: TimeInterval = 0
    nonisolated(unsafe) private var crossfadeTimer: Timer?
    private var crossfadeGeneration: Int = 0

    /// Nœud actuellement en lecture (lecteur actif).
    private var activeNode: AVAudioPlayerNode!
    /// Nœud entrant pendant un crossfade. nil = pas de crossfade en cours.
    private var incomingNode: AVAudioPlayerNode?

    // Flags de propreté par nœud : true = stop() appelé après le dernier segment,
    // queue vide, prêt for un nouveau scheduleSegment sans pollution.
    // Initialement true (aucun segment jamais schedulé sur ces nœuds).
    private var nodeAClean = true
    private var nodeBClean = true
    private var nodeCClean = true

    // Générations par nœud for les callbacks sentinelle (détection d'orphelins).
    private var coolingGenA = 0
    private var coolingGenB = 0
    private var coolingGenC = 0

    /// Chaîne d'effets du nœud actif.
    private var activeFilterNode: AVAudioUnitEQ {
        activeNode === nodeA ? filterNodeA : activeNode === nodeB ? filterNodeB : filterNodeC
    }
    private var activeDelayNode: AVAudioUnitDelay {
        activeNode === nodeA ? delayNodeA : activeNode === nodeB ? delayNodeB : delayNodeC
    }
    private var activeReverbNode: AVAudioUnitReverb {
        activeNode === nodeA ? reverbNodeA : activeNode === nodeB ? reverbNodeB : reverbNodeC
    }

    private(set) var isCrossfading: Bool = false
    var onCrossfadeAborted: (() -> Void)?

    /// Position de lecture du song ENTRANT pendant un crossfade, en
    /// secondes absolues dans son fichier (même référentiel que livePosition).
    /// nil hors crossfade. Permet au scheduler MIDI de suivre le nouveau
    /// song dès le début du fade au lieu d'attendre la fin.
    var crossfadeIncomingLivePosition: TimeInterval? {
        guard isCrossfading else { return nil }
        let elapsed = CACurrentMediaTime() - crossfadeStartHostTime
        return min(crossfadeEffectiveEnd, crossfadeTrimStart + elapsed)
    }

    private var crossfadeEffectiveEnd: TimeInterval {
        let s = max(0, min(crossfadeTrimStart, crossfadeTotalDuration))
        let e = crossfadeTrimEnd
        if e > s && e <= crossfadeTotalDuration { return e }
        return crossfadeTotalDuration
    }

    private var playbackGain: Float {
        Float(pow(10.0, (volumeOffsetDB + normGainDB) / 20.0))
    }

    /// Met at jour le gain de normalisation et l'applique immédiatement
    /// au nœud actif si le moteur est en lecture.
    func setNormGainDB(_ db: Double) {
        normGainDB = db
        if state == .playing || state == .paused {
            activeNode.volume = playbackGain
        }
    }

    // MARK: - Cycle de vie

    init() {
        // 3 chaînes identiques : nodeX → filterNodeX → delayNodeX → reverbNodeX → mainMixerNode
        // Toutes transparentes au repos (filter 20 kHz, delay/reverb wetDryMix=0).
        func attachChain(
            player: AVAudioPlayerNode,
            filter: AVAudioUnitEQ,
            delay: AVAudioUnitDelay,
            reverb: AVAudioUnitReverb,
            to eng: AVAudioEngine
        ) {
            eng.attach(player); eng.attach(filter); eng.attach(delay); eng.attach(reverb)
            eng.connect(player, to: filter, format: nil)
            eng.connect(filter, to: delay,  format: nil)
            eng.connect(delay,  to: reverb, format: nil)
            eng.connect(reverb, to: eng.mainMixerNode, format: nil)
            filter.bands[0].filterType = .lowPass
            filter.bands[0].frequency  = 20000
            filter.bands[0].bandwidth  = 0.5
            filter.bands[0].bypass     = false
            delay.wetDryMix     = 0
            delay.feedback      = 0
            delay.delayTime     = 0.625
            delay.lowPassCutoff = 15000
            reverb.loadFactoryPreset(.plate)
            reverb.wetDryMix = 0
        }
        attachChain(player: nodeA, filter: filterNodeA, delay: delayNodeA, reverb: reverbNodeA, to: engine)
        attachChain(player: nodeB, filter: filterNodeB, delay: delayNodeB, reverb: reverbNodeB, to: engine)
        attachChain(player: nodeC, filter: filterNodeC, delay: delayNodeC, reverb: reverbNodeC, to: engine)

        // Headroom permanent −3 dB : absorbe le pic equal-power (+3 dB)
        // pendant les crossfades. Compenser sur la CQ18T si nécessaire.
        engine.mainMixerNode.outputVolume = 0.708

        activeNode = nodeA

        // Warm-up : démarre le moteur at vide for éviter le cold start HALC
        // au premier play(). Le moteur tourne sans nœud actif — coût CPU négligeable.
        print("[AUDIO] engine warm-up start")
        do {
            try engine.start()
            print("[AUDIO] engine warm-up OK")
        } catch {
            print("[AUDIO] engine warm-up failed: \(error.localizedDescription)")
        }

        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleEngineConfigurationChange()
            }
        }
    }

    deinit {
        timer?.invalidate()
        fadeTimer?.invalidate()
        filterTimer?.invalidate()
        crossfadeTimer?.invalidate()
        if let url = scopedFolderURL {
            url.stopAccessingSecurityScopedResource()
        }
        if let url = crossfadeScopedFolderURL {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Chargement

    /// Charge un fichier audio dans le moteur. Décharge le précédent
    /// au passage. Reste at l'état `.stopped`. `currentPosition` est
    /// initialisée at 0 : les trims sont mémorisés mais pas appliqués
    /// pendant la Phase Audio 0.
    ///
    /// - parameters:
    ///   - url: chemin absolu du fichier audio.
    ///   - trimStart: début trimé ShowBuddy (secondes), stocké seulement.
    ///   - trimEnd: fin trimée ShowBuddy (secondes), stockée seulement.
    ///   - accessFolder: URL d'un dossier sandbox-scopé qui contient
    ///     le fichier. Si fournie, `startAccessingSecurityScopedResource`
    ///     est appelé dessus et l'accès reste ouvert tant que ce
    ///     fichier est chargé.
    func load(
        url: URL,
        trimStart: TimeInterval = 0,
        trimEnd: TimeInterval = 0,
        volumeOffsetDB: Double = 0,
        accessFolder: URL? = nil
    ) throws {
        // Décharge le précédent (ferme aussi son accès sandbox).
        unload()

        // Ouvre l'accès sandbox au dossier qui contient ce fichier.
        if let folder = accessFolder, folder.startAccessingSecurityScopedResource() {
            self.scopedFolderURL = folder
        }

        do {
            let file = try AVAudioFile(forReading: url)
            self.audioFile = file
            self.currentURL = url

            let sampleRate = file.processingFormat.sampleRate
            let dur = sampleRate > 0
                ? Double(file.length) / sampleRate
                : 0
            self.totalDuration = dur
            print("[AUDIO] file loaded — \(url.lastPathComponent) | dur=\(String(format:"%.1f",dur))s | sr=\(Int(sampleRate))Hz | format=\(url.pathExtension.lowercased())")
            print("[AUDIO] decoder ready — processingFormat: \(file.processingFormat)")

            // Borne defensivement les trims (au cas où la base contient
            // des valeurs incohérentes : trim négatif, trim au-delà du
            // fichier, trim end < trim start, etc.).
            let safeStart = max(0, min(trimStart, dur))
            self.trimStart = safeStart
            self.trimEnd = (trimEnd > safeStart && trimEnd <= dur) ? trimEnd : 0
            self.volumeOffsetDB = volumeOffsetDB
            self.activeNode.volume = playbackGain
            self.currentPosition = 0
            self.lastError = nil

        } catch {
            // Échec → on relâche aussi l'accès sandbox qu'on vient
            // d'ouvrir, sinon il fuit.
            if let folder = scopedFolderURL {
                folder.stopAccessingSecurityScopedResource()
                scopedFolderURL = nil
            }
            let message = "\(url.lastPathComponent) — \(error.localizedDescription)"
            self.lastError = message
            throw AudioError.fileUnreadable(message)
        }
    }

    /// Met at jour les bornes de trim sans recharger le fichier. Sécurise
    /// les valeurs reçues contre la durée du fichier en cours.
    /// Si la lecture est en cours et que `currentPosition` sort de la
    /// nouvelle fenêtre, on ne touche pas la position (apply-on-save :
    /// l'utilisateur ne veut pas que la lecture saute en plein concert).
    /// La prochaine action `play()` depuis stop appliquera proprement
    /// `effectiveStart`.
    func setTrims(start: TimeInterval, end: TimeInterval) {
        let dur = totalDuration
        let safeStart = max(0, min(start, dur))
        trimStart = safeStart
        trimEnd = (end > safeStart && end <= dur) ? end : 0
    }

    /// Met at jour le gain du song chargé sans recharger le fichier.
    /// Si la lecture est en cours, on rampe brièvement for éviter clics
    /// et changements brusques.
    func setVolumeOffsetDB(_ offsetDB: Double) {
        volumeOffsetDB = offsetDB
        let target = playbackGain
        if state == .playing {
            fadeVolume(to: target, duration: 0.08)
        } else {
            activeNode.volume = target
        }
    }

    /// Décharge le fichier courant. Stop le moteur si besoin, ferme
    /// l'accès sandbox, remet l'état at zéro.
    func unload() {
        stopImmediately()
        audioFile = nil
        currentURL = nil
        totalDuration = 0
        currentPosition = 0
        trimStart = 0
        trimEnd = 0
        volumeOffsetDB = 0
        if let folder = scopedFolderURL {
            folder.stopAccessingSecurityScopedResource()
            scopedFolderURL = nil
        }
    }

    // MARK: - Transport

    func play(fadeInDuration: TimeInterval = 0.2) {
        guard audioFile != nil else { return }
        guard state != .playing else { return }
        fadeTimer?.invalidate()
        fadeTimer = nil
        print("[AUDIO] play requested — file=\(currentURL?.lastPathComponent ?? "?") | state=\(state) | pos=\(String(format:"%.2f",currentPosition))s | engineRunning=\(engine.isRunning) | firstPlay=\(!hasEverPlayed)")

        // Play pressé pendant un echo-out (.stopping) : la chaîne active est
        // encore 100 % wet (delay/réverbe armés par stopWithEchoFade) et seule
        // stopImmediately la remettait at dry. Sans ce reset, la lecture
        // repartirait noyée dans le delay. La Task d'écho en vol se terminera
        // d'elle-même (guard state == .stopping).
        activeDelayNode.wetDryMix  = 0
        activeDelayNode.feedback   = 0
        activeReverbNode.wetDryMix = 0

        // Au démarrage depuis stop, on repart du début de la fenêtre
        // de lecture effective (= trimStart). Depuis pause, on reprend
        // là où on est. Si `currentPosition` est tombée hors fenêtre
        // pendant une édition de trim, on la clampe for ne pas
        // déclencher la fin immédiatement.
        if currentPosition < effectiveStart || currentPosition >= effectiveEnd {
            currentPosition = effectiveStart
        }

        do {
            if !engine.isRunning {
                print("[AUDIO] engine cold start — HALC IO thread not yet initialized")
                try engine.start()
                print("[AUDIO] engine started")
            }
        } catch {
            self.lastError = AudioError
                .engineStartFailed(error.localizedDescription)
                .localizedDescription
            return
        }

        scheduleSegment(from: currentPosition)
        let targetVolume = playbackGain
        activeNode.volume = fadeInDuration > 0 ? 0 : targetVolume
        activeNode.play()
        print("[AUDIO] activeNode PLAY — \(currentURL?.lastPathComponent ?? "?") pos=\(String(format:"%.2f",currentPosition))s xfading=\(isCrossfading)")
        if !hasEverPlayed {
            hasEverPlayed = true
            print("[AUDIO] firstPlay — this is the first playback since app launch")
        }
        print("[AUDIO] fade-in start — vol=0 → target=\(String(format:"%.3f",targetVolume)) dur=\(fadeInDuration)s")
        state = .playing
        print("[AUDIO] engine state → .playing")
        if !meterTapInstalled {
            installMeterTap()
            meterTapInstalled = true
        }
        didEndishSegment = false
        playStartHostTime = CACurrentMediaTime()
        positionAtPlayStart = currentPosition
        startTimer()
        fadeVolume(to: targetVolume, duration: fadeInDuration) {
            print("[AUDIO] fade-in end — vol=\(String(format:"%.3f",targetVolume))")
        }
    }

    func pause() {
        guard state == .playing else { return }
        // Fige la position courante AVANT de stopper le node.
        let elapsed = CACurrentMediaTime() - playStartHostTime
        currentPosition = min(effectiveEnd, positionAtPlayStart + elapsed)
        activeNode.pause()
        state = .paused
        stopTimer()
    }

    func seek(to position: TimeInterval) {
        guard audioFile != nil else { return }
        let target = max(effectiveStart, min(position + effectiveStart, effectiveEnd))
        currentPosition = target

        guard state == .playing else { return }
        fadeTimer?.invalidate()
        fadeTimer = nil
        activeNode.volume = 0
        scheduleSegment(from: target)
        activeNode.volume = 0
        activeNode.play()
        fadeVolume(to: playbackGain, duration: 0.025)
        didEndishSegment = false
        playStartHostTime = CACurrentMediaTime()
        positionAtPlayStart = target
        startTimer()
    }

    /// Seek musical avec mini fade-out / fade-in for éviter tout clic.
    /// - Si le song joue : fade-out → repositionnement → fade-in.
    /// - Si pause/stop : repositionnement direct, reste dans l'état courant.
    /// `position` est relative at `effectiveStart` (comme `effectivePosition`).
    func seekWithFade(
        to effectivePos: TimeInterval,
        fadeOut: TimeInterval = 0.15,
        fadeIn: TimeInterval = 0.15
    ) {
        guard audioFile != nil else { return }
        let absTarget = max(effectiveStart, min(effectivePos + effectiveStart, effectiveEnd))

        guard state == .playing else {
            // Pause ou stop : mise at jour visuelle seule, pas d'audio.
            currentPosition = absTarget
            return
        }

        isSeeking = true
        fadeTimer?.invalidate()
        fadeTimer = nil

        fadeVolume(to: 0, duration: fadeOut) { [weak self] in
            guard let self else { return }
            // Repositionnement audio
            self.scheduleSegment(from: absTarget)
            self.currentPosition = absTarget
            self.didEndishSegment = false
            self.activeNode.volume = 0
            self.activeNode.play()
            self.playStartHostTime = CACurrentMediaTime()
            self.positionAtPlayStart = absTarget
            self.startTimer()
            // Fade-in puis on lève le verrou.
            // Cas limite : si la fin naturelle du segment a eu lieu pendant
            // le seek (isSeeking bloquait handleEndOfSegment), la déclencher
            // maintenant — sinon la Queue Auto ne partirait jamais.
            self.fadeVolume(to: self.playbackGain, duration: fadeIn) { [weak self] in
                guard let self else { return }
                self.isSeeking = false
                if !self.didEndishSegment
                    && self.state == .playing
                    && self.currentPosition >= self.effectiveEnd {
                    self.handleEndOfSegment()
                }
            }
        }
    }

    /// Pause avec fade-out doux — utilisée par tous les transports
    /// utilisateur (barre espace, bouton, futur footswitch). L'état passe
    /// at `.paused` immédiatement for que l'UI réagisse sans délai, le
    /// nœud audio finit de fader sur `fadeOutDuration` puis est mis en
    /// pause. Si l'utilisateur reprend la lecture pendant le fade,
    /// `play()` annule proprement le fade en cours via `scheduleSegment`.
    func pause(fadeOutDuration: TimeInterval) {
        guard state == .playing else { return }
        guard fadeOutDuration > 0 else {
            pause()
            return
        }

        let elapsed = CACurrentMediaTime() - playStartHostTime
        currentPosition = min(effectiveEnd, positionAtPlayStart + elapsed)
        state = .paused
        stopTimer()

        fadeVolume(to: 0, duration: fadeOutDuration) { [weak self] in
            guard let self else { return }
            // L'utilisateur a peut-être relancé la lecture entre temps.
            guard self.state == .paused else { return }
            self.activeNode.pause()
        }
    }

    func stop() {
        stop(fadeOutDuration: 2.0)
    }

    func stop(fadeOutDuration: TimeInterval) {
        guard state == .playing || state == .paused || state == .stopping else {
            stopImmediately()
            return
        }
        guard fadeOutDuration > 0, state == .playing else {
            stopImmediately()
            return
        }

        let elapsed = CACurrentMediaTime() - playStartHostTime
        currentPosition = min(effectiveEnd, positionAtPlayStart + elapsed)
        print("[AUDIO] stop requested — fadeOut=\(fadeOutDuration)s | pos=\(String(format:"%.2f",currentPosition))s | engineRunning=\(engine.isRunning)")
        print("[AUDIO] fade-out start — vol=\(String(format:"%.3f",activeNode.volume)) → 0 dur=\(fadeOutDuration)s")
        state = .stopping
        print("[AUDIO] engine state → .stopping")
        stopTimer()
        fadeVolume(to: 0, duration: fadeOutDuration) { [weak self] in
            print("[AUDIO] fade-out end — calling stopImmediately()")
            self?.stopImmediately()
        }
    }

    func stopImmediately() {
        if isCrossfading { cancelCrossfade() }
        fadeTimer?.invalidate()
        fadeTimer = nil
        print("[AUDIO] stopImmediately — \(currentURL?.lastPathComponent ?? "?") state=\(state)")
        // Invalide toutes les sentinelles en vol avant les stop().
        coolingGenA &+= 1; coolingGenB &+= 1; coolingGenC &+= 1
        nodeA.stop(); nodeAClean = true
        nodeB.stop(); nodeBClean = true
        nodeC.stop(); nodeCClean = true
        // Remet les 3 chaînes d'effets at dry.
        resetFilter()
        delayNodeA.wetDryMix = 0; delayNodeA.feedback = 0; reverbNodeA.wetDryMix = 0
        delayNodeB.wetDryMix = 0; delayNodeB.feedback = 0; reverbNodeB.wetDryMix = 0
        delayNodeC.wetDryMix = 0; delayNodeC.feedback = 0; reverbNodeC.wetDryMix = 0
        // Reset rôles : nodeA = actif par défaut, pas d'entrant.
        activeNode   = nodeA
        activeNode.volume = 1
        incomingNode = nil
        state = .stopped
        print("[AUDIO] engine state → .stopped")
        currentPosition = 0
        stopTimer()
    }

    // MARK: - Internals

    /// Schédule le segment [startTime, effectiveEnd] dans le player.
    private func scheduleSegment(from startTime: TimeInterval) {
        guard let file = audioFile else { return }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return }

        let startFrame = AVAudioFramePosition(startTime * sampleRate)
        let endFrame   = AVAudioFramePosition(effectiveEnd * sampleRate)
        guard endFrame > startFrame else { return }

        let frameCount = AVAudioFrameCount(endFrame - startFrame)

        scheduleEpoch &+= 1          // incrémente la génération courante
        let capturedEpoch = scheduleEpoch

        activeNode.stop()
        activeNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: frameCount,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { _ in
            // Le callback CoreAudio vient d'un thread privé. On revient
            // sur le main actor for modifier l'état observable.
            Task { @MainActor [weak self] in
                // Callback orphelin : playerNode.stop() l'a déclenché
                // lors d'un unload ou d'un re-schedule → on l'ignore.
                guard let self, self.scheduleEpoch == capturedEpoch else { return }
                self.handleEndOfSegment()
            }
        }
    }

    /// Le segment vient de finir naturellement (sans stop() utilisateur).
    /// On se cale sur effectiveEnd et on repasse en .stopped.
    ///
    /// Verrou `didEndishSegment` : le callback CoreAudio `.dataPlayedBack`
    /// peut arriver avec un retard equivalent at la latence du buffer de
    /// sortie. Si la Queue Auto a déjà lancé le song suivant entre
    /// temps (state repassé at `.playing`), un 2e appel couperait ce
    /// nouveau song. Le verrou bloque cette ré-entrée.
    private func handleEndOfSegment() {
        guard !didEndishSegment else { return }
        // Pendant un seek avec fondu, le silence du fade-out ne doit pas
        // être interprété comme une fin naturelle.
        guard !isSeeking else { return }
        // Pendant un crossfade, la fin naturelle de l'ancien segment est
        // attendue et bénigne — finishCrossfade() s'occupe du nouveau song.
        guard !isCrossfading else { return }
        // Garde-fou : si l'utilisateur a stop() ou repositionné entretemps.
        guard state == .playing || state == .stopping else { return }
        didEndishSegment = true
        currentPosition = effectiveEnd
        stopImmediately()
        onPlaybackEndished?()
    }

    /// Vrai Echo Out DJ via AVAudioUnitDelay.
    ///
    /// - Parameter beatDuration: durée d'un temps en secondes, calculée par
    ///   AppState depuis le BPM du song en cours (60 BPM → 1.0 s,
    ///   120 BPM → 0.5 s). Défaut : 0.625 s ≈ 96 BPM.
    ///
    /// Mécanisme (pre-arm) :
    ///   1. `delayNode` est configuré (delayTime, feedback, wetDryMix = 100).
    ///      Changer `delayTime` peut flusher le buffer interne → on laisse
    ///      `playerNode` jouer at plein volume pendant exactement 1 beat pour
    ///      que le buffer se remplisse au nouveau delayTime.
    ///   2. Après 1 beat : `playerNode.volume = 0`. Le buffer contient du signal
    ///      réel → les répétitions démarrent immédiatement.
    ///   3. Les répétitions décroissent : 65 % → 42 % → 27 % → 18 % → ...
    ///   4. `stopImmediately()` est appelé après 4 beats supplémentaires + 40 ms
    ///      de marge (total : 5 beats depuis l'appel).
    ///
    /// Guard zombie : la Task vérifie `state == .stopping` au réveil — si Stop
    /// a été pressé entre-temps, elle sort sans appeler `stopImmediately()`.
    func stopWithEchoFade(beatDuration: TimeInterval = 0.625) {
        guard state == .playing || state == .paused else { stopImmediately(); return }
        fadeTimer?.invalidate()
        fadeTimer = nil

        // Étape 1 — Arme le delay de la chaîne active (peut flusher le buffer si delayTime change).
        // activeNode continue at plein volume → remplit le buffer au nouveau delayTime.
        activeDelayNode.delayTime     = min(2.0, beatDuration)  // AVAudioUnitDelay max = 2 s
        activeDelayNode.feedback      = 65
        activeDelayNode.wetDryMix     = 100
        activeDelayNode.lowPassCutoff = 12000
        activeReverbNode.wetDryMix    = 20
        state = .stopping
        stopTimer()

        let beatMs = Int(beatDuration * 1000)
        let tailMs = Int(beatDuration * 4 * 1000) + 40  // 4 répétitions + marge

        Task { @MainActor [weak self] in
            // Étape 2 — Après 1 beat, le buffer est plein → couper la source.
            try? await Task.sleep(for: .milliseconds(beatMs))
            guard let self, self.state == .stopping else { return }
            self.activeNode.volume = 0

            // Étape 3 — Laisser les 4 répétitions se dérouler, puis nettoyer.
            try? await Task.sleep(for: .milliseconds(tailMs))
            guard self.state == .stopping else { return }
            self.stopImmediately()
        }
    }

    // MARK: - Crossfade (FADE / SLOW FADE)

    // IMPORTANT ARCHITECTURE RULE
    //
    // AVAudioPlayerNode.stop() must NEVER be called during or immediately
    // after a crossfade while another player node is actively rendering.
    //
    // Doing so triggers HALC overloads and audible clicks/crackles.
    //
    // Nodes are only stopped when recycled as the next standby node,
    // immediately before scheduleSegment().

    /// Démarre un crossfade entre le song en cours (`playerNode`) et le
    /// nouveau song (`crossfadeNode`).
    ///
    /// - Les deux fades (out sur playerNode, in sur crossfadeNode) durent
    ///   exactement `duration` secondes et courent en parallèle.
    /// - `onComplete` est appelé sur MainActor at la fin du fade-out de
    ///   playerNode, après que `finishCrossfade()` a promu le nouveau song.
    /// - En cas d'erreur (fichier illisible), lève `AudioError.fileUnreadable`
    ///   et laisse l'état intact — AppState peut basculer sur un fallback.
    func startCrossfade(
        url: URL,
        trimStart: TimeInterval = 0,
        trimEnd: TimeInterval = 0,
        volumeOffsetDB: Double = 0,
        normGainDB: Double = 0,
        accessFolder: URL? = nil,
        duration: TimeInterval,
        withFilter: Bool = false,
        onComplete: @escaping () -> Void
    ) throws {
        // 1. Ouvre le fichier du nouveau song.
        if let folder = accessFolder, folder.startAccessingSecurityScopedResource() {
            crossfadeScopedFolderURL = folder
        }
        do {
            let file = try AVAudioFile(forReading: url)
            let sr = file.processingFormat.sampleRate
            let dur = sr > 0 ? Double(file.length) / sr : 0
            crossfadeFile = file
            crossfadeURL = url
            crossfadeTotalDuration = dur
            let safeStart = max(0, min(trimStart, dur))
            crossfadeTrimStart = safeStart
            crossfadeTrimEnd = (trimEnd > safeStart && trimEnd <= dur) ? trimEnd : 0
            crossfadeVolumeOffsetDB = volumeOffsetDB
            crossfadeNormGainDB = normGainDB
        } catch {
            crossfadeScopedFolderURL?.stopAccessingSecurityScopedResource()
            crossfadeScopedFolderURL = nil
            let msg = "\(url.lastPathComponent) — \(error.localizedDescription)"
            throw AudioError.fileUnreadable(msg)
        }

        // 2. Trouver un nœud propre disponible. Refuse le fade s'il n'y en a pas.
        let act = activeNode === nodeA ? "A" : activeNode === nodeB ? "B" : "C"
        print("[CLEAN] avant fade — A:\(nodeAClean ? "✓" : "✗") B:\(nodeBClean ? "✓" : "✗") C:\(nodeCClean ? "✓" : "✗") | active=\(act)")
        guard let incoming = nextCleanNode else {
            crossfadeScopedFolderURL?.stopAccessingSecurityScopedResource()
            crossfadeScopedFolderURL = nil
            crossfadeFile = nil; crossfadeURL = nil
            print("[WARN] FADE refused: no clean node available (all cooling)")
            throw AudioError.noCleanNodeAvailable
        }
        incomingNode = incoming
        setClean(incoming, false)
        let inLabel = incoming === nodeA ? "nodeA" : incoming === nodeB ? "nodeB" : "nodeC"
        print("[CLEAN] incoming selected = \(inLabel) for \(url.lastPathComponent)")

        guard let file = crossfadeFile else { return }
        let sr = file.processingFormat.sampleRate
        guard sr > 0 else { cancelCrossfade(); return }
        let startFrame = AVAudioFramePosition(crossfadeTrimStart * sr)
        let endFrame   = AVAudioFramePosition(crossfadeEffectiveEnd * sr)
        guard endFrame > startFrame else { cancelCrossfade(); return }

        scheduleEpoch &+= 1
        let capturedEpoch = scheduleEpoch

        incoming.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(endFrame - startFrame),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { _ in
            Task { @MainActor [weak self] in
                guard let self, self.scheduleEpoch == capturedEpoch else { return }
                self.handleEndOfSegment()
            }
        }

        // 3. Démarre le nœud entrant at volume 0.
        let newGain = Float(pow(10.0, (volumeOffsetDB + normGainDB) / 20.0))
        incoming.volume = 0
        incoming.play()
        let inName = incoming === nodeA ? "nodeA" : incoming === nodeB ? "nodeB" : "nodeC"
        print("[AUDIO] incomingNode PLAY — \(inName) \(url.lastPathComponent) gain→\(String(format:"%.2f",newGain))")
        isCrossfading = true
        crossfadeStartHostTime = CACurrentMediaTime()

        let oldName = currentURL?.lastPathComponent ?? "?"
        let newName = url.lastPathComponent
        print("[XFADE] Started — \"\(oldName)\" → \"\(newName)\" | duration: \(String(format: "%.1f", duration))s | gain→\(String(format: "%.2f", newGain))")

        // 4. Fade in du nœud entrant + fade out du nœud actif, en parallèle.
        //    Pour FILTER : sweep low-pass simultané sur activeNode (ancien song).
        if withFilter { startFilterSweep(duration: duration) }
        fadeCrossfadeVolume(node: incoming, to: newGain, duration: duration)
        fadeVolume(to: 0, duration: duration) { [weak self] in
            guard let self, self.isCrossfading else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isCrossfading else { return }
                await self.finishCrossfade()
                onComplete()
            }
        }
    }

    /// Abandonne proprement un crossfade en cours (Stop utilisateur, second
    /// remplacement, reconfiguration audio). crossfadeNode est arrêté ; les
    /// timers des deux fades sont invalidés. playerNode continue dans l'état
    /// où il se trouve — le caller gère la suite (stop, nouveau crossfade...).
    func cancelCrossfade() {
        guard isCrossfading else { return }
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        crossfadeGeneration &+= 1
        fadeTimer?.invalidate()
        fadeTimer = nil
        fadeGeneration &+= 1
        // Stop le nœud entrant. Appelé uniquement depuis stopImmediately()
        // ou handleEngineConfigurationChange() — pas pendant un rendu crossfade stable.
        if let incoming = incomingNode {
            incoming.stop()
            incoming.volume = 0
            setClean(incoming, true)
            incomingNode = nil
        }
        crossfadeFile = nil
        crossfadeURL = nil
        if let folder = crossfadeScopedFolderURL {
            folder.stopAccessingSecurityScopedResource()
            crossfadeScopedFolderURL = nil
        }
        resetFilter()
        isCrossfading = false
        print("[XFADE] Cancelled")
    }

    /// Promeut crossfadeNode en lecteur principal une fois les deux fades
    /// terminés. Appelé depuis la completion de `fadeVolume(to:0)` lancé par
    /// `startCrossfade` — toujours sur MainActor.
    ///
    /// Séquence atomique (MainActor, pas d'await) :
    ///   1. Calcule la position courante dans le nouveau fichier.
    ///   2. Arrête playerNode (déjà at volume 0 — pas de clic).
    ///   3. Swap audioFile / trims / sandbox.
    ///   4. Reschedule playerNode depuis cette position.
    ///   5. Démarre playerNode au gain cible.
    ///   6. Arrête crossfadeNode.
    ///   7. Met at jour l'état de l'engine.
    private func finishCrossfade() async {
        let elapsed = CACurrentMediaTime() - crossfadeStartHostTime
        let pos = min(crossfadeEffectiveEnd, crossfadeTrimStart + elapsed)

        // Swap sandbox.
        scopedFolderURL?.stopAccessingSecurityScopedResource()
        scopedFolderURL          = crossfadeScopedFolderURL
        crossfadeScopedFolderURL = nil

        // Swap métadonnées.
        audioFile      = crossfadeFile
        currentURL     = crossfadeURL
        totalDuration  = crossfadeTotalDuration
        trimStart      = crossfadeTrimStart
        trimEnd        = crossfadeTrimEnd
        volumeOffsetDB = crossfadeVolumeOffsetDB
        normGainDB     = crossfadeNormGainDB

        // Remet le filtre de la chaîne sortante at transparent AVANT le swap.
        resetFilter()

        // Rotation des rôles : incoming → active, active → cooling.
        let outgoing = activeNode!
        activeNode   = incomingNode!
        incomingNode = nil

        // Marque le nœud sortant dirty AVANT la sentinelle.
        // Sans ça, nextCleanNode le sélectionne immédiatement comme incoming
        // alors que sa queue CoreAudio draint encore l'ancien segment.
        setClean(outgoing, false)

        currentPosition     = pos
        didEndishSegment    = false
        isCrossfading       = false
        state               = .playing
        playStartHostTime   = CACurrentMediaTime()
        positionAtPlayStart = pos
        startTimer()

        // Sentinelle sur le nœud sortant : fire quand sa queue est vide → stop() safe.
        // Aucun stop() ici — outgoing est au volume 0 mais sa queue n'est pas encore vide.
        scheduleSentinelle(on: outgoing)

        let name = activeNode === nodeA ? "nodeA" : activeNode === nodeB ? "nodeB" : "nodeC"
        print("[XFADE] Swap complete: activeNode=\(name) pos=\(String(format:"%.2f",pos))s")
    }

    // MARK: - 3-node helpers

    /// Nœud propre disponible for le prochain crossfade.
    /// Exclut activeNode et incomingNode (en cours d'utilisation).
    /// Exclut tout nœud dont le flag clean est false (queue pas encore drainée).
    private var nextCleanNode: AVAudioPlayerNode? {
        for node in [nodeA, nodeB, nodeC] {
            guard node !== activeNode else { continue }
            guard node !== incomingNode else { continue }
            if isClean(node) { return node }
        }
        return nil
    }

    private func isClean(_ node: AVAudioPlayerNode) -> Bool {
        node === nodeA ? nodeAClean : node === nodeB ? nodeBClean : nodeCClean
    }

    private func setClean(_ node: AVAudioPlayerNode, _ value: Bool) {
        if node === nodeA { nodeAClean = value }
        else if node === nodeB { nodeBClean = value }
        else { nodeCClean = value }
    }

    private func coolingGen(_ node: AVAudioPlayerNode) -> Int {
        node === nodeA ? coolingGenA : node === nodeB ? coolingGenB : coolingGenC
    }

    @discardableResult
    private func incrementCoolingGen(_ node: AVAudioPlayerNode) -> Int {
        if node === nodeA { coolingGenA &+= 1; return coolingGenA }
        if node === nodeB { coolingGenB &+= 1; return coolingGenB }
        coolingGenC &+= 1; return coolingGenC
    }

    /// Schédule 1 frame sur `node` (vol=0, inaudible). Quand le callback
    /// dataPlayedBack se déclenche, la queue est vide → stop() est safe.
    private func scheduleSentinelle(on node: AVAudioPlayerNode) {
        guard let file = audioFile else { return }
        guard file.processingFormat.sampleRate > 0 else { return }
        let gen = incrementCoolingGen(node)
        let capturedNode = node
        node.scheduleSegment(
            file, startingFrame: 0, frameCount: 1, at: nil,
            completionCallbackType: .dataPlayedBack
        ) { _ in
            Task { @MainActor [weak self] in
                guard let self, self.coolingGen(capturedNode) == gen else { return }
                capturedNode.stop()
                self.setClean(capturedNode, true)
                let n = capturedNode === self.nodeA ? "nodeA"
                      : capturedNode === self.nodeB ? "nodeB" : "nodeC"
                print("[XFADE] Sentinelle — \(n) stop() safe, propre")
            }
        }
    }

    /// Variante de `fadeVolume` for le nœud entrant.
    /// Timer et génération indépendants — les deux fades coexistent sans
    /// s'invalider mutuellement. `node` est capturé at l'appel.
    private func fadeCrossfadeVolume(
        node: AVAudioPlayerNode,
        to target: Float,
        duration: TimeInterval,
        completion: (() -> Void)? = nil
    ) {
        crossfadeTimer?.invalidate()
        crossfadeGeneration &+= 1
        let gen = crossfadeGeneration

        guard duration > 0 else {
            node.volume = target
            completion?()
            return
        }

        let startVolume = node.volume
        let startedAt   = CACurrentMediaTime()
        crossfadeTimer = Self.commonModeTimer(interval: 1.0 / 60.0) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.crossfadeGeneration == gen else { return }
                let progress = min(1.0, (CACurrentMediaTime() - startedAt) / duration)
                let volume: Float
                if target <= 0 {
                    volume = startVolume * Float(cos(Double(progress) * .pi / 2))
                } else if startVolume <= 0 {
                    volume = target * Float(sin(Double(progress) * .pi / 2))
                } else {
                    volume = startVolume + (target - startVolume) * Float(progress)
                }
                node.volume = volume
                if progress >= 1.0 {
                    node.volume = target
                    self.crossfadeTimer?.invalidate()
                    self.crossfadeTimer = nil
                    completion?()
                }
            }
        }
    }

    // MARK: - Filter sweep (FILTER transition)

    /// Remet filterNode at l'état transparent (cutoff 20 kHz).
    /// Appelé depuis stopImmediately, cancelCrossfade, finishCrossfade
    /// et handleEngineConfigurationChange.
    private func resetFilter() {
        filterTimer?.invalidate()
        filterTimer = nil
        filterGeneration &+= 1
        activeFilterNode.bands[0].frequency = 20000
    }

    /// Anime le cutoff low-pass de 20 kHz → 300 Hz sur `duration` secondes.
    /// Courbe logarithmique (perçue comme linéaire at l'oreille).
    private func startFilterSweep(duration: TimeInterval) {
        filterTimer?.invalidate()
        filterGeneration &+= 1
        let gen = filterGeneration

        let logStart = log10(20000.0)
        let logEnd   = log10(800.0)
        let startedAt = CACurrentMediaTime()

        filterTimer = Self.commonModeTimer(interval: 1.0 / 60.0) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.filterGeneration == gen else { return }
                let progress = min(1.0, (CACurrentMediaTime() - startedAt) / duration)
                let logFreq  = logStart + (logEnd - logStart) * progress
                self.activeFilterNode.bands[0].frequency = Float(pow(10.0, logFreq))
                if progress >= 1.0 {
                    self.activeFilterNode.bands[0].frequency = 800
                    self.filterTimer?.invalidate()
                    self.filterTimer = nil
                }
            }
        }
    }

    // MARK: - Reconfiguration périphérique audio

    /// Appelé quand macOS émet AVAudioEngineConfigurationChange.
    /// Le moteur a été arrêté automatiquement et le graph invalidé :
    /// il faut reconstruire la connexion et, si on était en lecture,
    /// reprendre at la position courante.
    private func handleEngineConfigurationChange() {
        print("[VELVET] AVAudioEngineConfigurationChange — reconstruction du graph audio")

        // 1. Retire le tap RMS : son format est lié at l'ancien périphérique.
        if meterTapInstalled {
            engine.mainMixerNode.removeTap(onBus: 0)
            meterTapInstalled = false
        }

        // 2. Reconstruit les 3 chaînes de connexions → mainMixerNode.
        //    Obligatoire après une invalidation de graph ; sans ça,
        //    engine.start() réussit mais aucun son ne sort.
        engine.connect(nodeA, to: filterNodeA, format: nil)
        engine.connect(filterNodeA, to: delayNodeA,  format: nil)
        engine.connect(delayNodeA,  to: reverbNodeA, format: nil)
        engine.connect(reverbNodeA, to: engine.mainMixerNode, format: nil)
        engine.connect(nodeB, to: filterNodeB, format: nil)
        engine.connect(filterNodeB, to: delayNodeB,  format: nil)
        engine.connect(delayNodeB,  to: reverbNodeB, format: nil)
        engine.connect(reverbNodeB, to: engine.mainMixerNode, format: nil)
        engine.connect(nodeC, to: filterNodeC, format: nil)
        engine.connect(filterNodeC, to: delayNodeC,  format: nil)
        engine.connect(delayNodeC,  to: reverbNodeC, format: nil)
        engine.connect(reverbNodeC, to: engine.mainMixerNode, format: nil)
        resetFilter()

        // 3. Si un crossfade était en cours, l'abandonner proprement.
        //    AppState reprendra le song précédent via onCrossfadeAborted.
        if isCrossfading {
            cancelCrossfade()
            onCrossfadeAborted?()
        }

        // 4. Paused ou stopped : on laisse l'état tel quel.
        //    Le prochain play() appellera engine.start() normalement.
        guard state == .playing else {
            print("[VELVET] Audio reconfiguration: state \(state), no automatic resume")
            return
        }

        // 5. Était en lecture : on reprend at la position courante.
        //    Stoppe et nettoie les nœuds non-actifs (sentinelles orphelines incluses).
        coolingGenA &+= 1; coolingGenB &+= 1; coolingGenC &+= 1
        for node in [nodeA, nodeB, nodeC] where node !== activeNode {
            node.stop()
            node.volume = 0
            setClean(node, true)
        }
        do {
            try engine.start()
            scheduleSegment(from: currentPosition)
            activeNode.volume = playbackGain
            activeNode.play()
            print("[AUDIO] activeNode PLAY (reconfiguration audio) — \(currentURL?.lastPathComponent ?? "?") pos=\(String(format:"%.2f",currentPosition))s")
            installMeterTap()
            meterTapInstalled = true
            playStartHostTime = CACurrentMediaTime()
            positionAtPlayStart = currentPosition
            print("[VELVET] Audio reconfiguration: resumed at \(String(format: "%.1f", currentPosition))s")
        } catch {
            lastError = "Audio device changed: resume failed (\(error.localizedDescription))"
            state = .stopped
            stopTimer()
            print("[VELVET] Audio reconfiguration failed: \(error)")
        }
    }

    // MARK: - Timer UI

    /// Crée un timer répétitif enregistré en mode `.common` : il continue
    /// de tirer pendant les menus ouverts et les drags de fenêtre
    /// (RunLoop en .eventTracking), contrairement at Timer.scheduledTimer
    /// qui s'enregistre en .default et gèle — fades figés en plein concert.
    private static func commonModeTimer(
        interval: TimeInterval,
        block: @escaping (Timer) -> Void
    ) -> Timer {
        let t = Timer(timeInterval: interval, repeats: true, block: block)
        RunLoop.main.add(t, forMode: .common)
        return t
    }

    private func startTimer() {
        stopTimer()
        timer = Self.commonModeTimer(interval: 1.0 / 30.0) { _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func fadeVolume(
        to target: Float,
        duration: TimeInterval,
        completion: (() -> Void)? = nil
    ) {
        fadeTimer?.invalidate()
        // Incrémente la génération : toute task @MainActor en vol créée par
        // le timer précédent verra une génération différente et s'annulera.
        // Évite les tasks fantômes qui continueraient at écrire playerNode.volume
        // ou at déclencher la completion après qu'un nouveau fade a commencé.
        fadeGeneration &+= 1
        let gen = fadeGeneration

        guard duration > 0 else {
            activeNode.volume = target
            completion?()
            return
        }

        let startVolume = activeNode.volume
        let startedAt = CACurrentMediaTime()
        fadeTimer = Self.commonModeTimer(interval: 1.0 / 60.0) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.fadeGeneration == gen else { return }
                let progress = min(1.0, (CACurrentMediaTime() - startedAt) / duration)
                // Equal-power uniquement for les fades vers/depuis le silence :
                // - to 0 : cos(t·π/2) — −3 dB au milieu, chute régulière.
                // - depuis 0 : sin(t·π/2) — montée régulière.
                // Linéaire for les transitions partielles (gain offset, étapes echo) :
                // la formule cos donnerait 0 en fin de fade au lieu de la cible.
                let volume: Float
                if target <= 0 {
                    volume = startVolume * Float(cos(Double(progress) * .pi / 2))
                } else if startVolume <= 0 {
                    volume = target * Float(sin(Double(progress) * .pi / 2))
                } else {
                    volume = startVolume + (target - startVolume) * Float(progress)
                }
                self.activeNode.volume = volume
                if progress >= 1.0 {
                    self.activeNode.volume = target  // valeur exacte garantie
                    self.fadeTimer?.invalidate()
                    self.fadeTimer = nil
                    completion?()
                }
            }
        }
    }

    private func installMeterTap() {
        let mixer = engine.mainMixerNode
        let format = mixer.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        mixer.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }
            var sum: Float = 0
            for i in 0..<frameCount { sum += channelData[i] * channelData[i] }
            let rms = sqrt(sum / Float(frameCount))
            Task { @MainActor [weak self] in
                self?.meterLevel = rms
            }
        }
    }

    private func tick() {
        guard state == .playing else { return }
        // Garde-fou : si le moteur s'est arrêté sans que
        // AVAudioEngineConfigurationChange ait encore été livré,
        // on délègue at handleEngineConfigurationChange qui reconstruit
        // le graph correctement avant de tenter engine.start().
        if !engine.isRunning {
            handleEngineConfigurationChange()
            return
        }
        let elapsed = CACurrentMediaTime() - playStartHostTime
        let newPos = positionAtPlayStart + elapsed
        // On clampe la position affichée at effectiveEnd, mais on NE
        // déclenche PAS handleEndOfSegment ici. CACurrentMediaTime est
        // l'horloge CPU et arrive systématiquement en avance sur la
        // sortie audio réelle (latence du buffer de sortie). Couper le
        // node sur ce signal-là provoque un clic + une micro-coupure
        // des derniers samples. C'est le callback CoreAudio
        // `.dataPlayedBack` qui déclenche la fin — il est sample-accurate.
        currentPosition = min(effectiveEnd, newPos)
    }
}
