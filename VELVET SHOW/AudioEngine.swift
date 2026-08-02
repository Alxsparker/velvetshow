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
#if DEBUG
import CoreAudio   // [XFADE METRICS] instrumentation temporaire (device + overloads HAL)
#endif

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

    /// Photographie structurée d'une perte de continuité détectée par le
    /// moniteur de contrôle (jamais depuis le callback audio temps réel).
    struct ContinuityDiagnostic: Identifiable, Equatable {
        enum Reason: String, Equatable {
            case engineNotRunning
            case playerNotRendering
            case transportAheadOfRenderedAudio
        }

        let id: UUID
        let date: Date
        let hostTime: TimeInterval
        let trackID: String?
        let reasons: [Reason]
        let engineIsRunning: Bool
        let playerIsPlaying: Bool
        let transportPosition: TimeInterval
        let renderedPosition: TimeInterval?
        let transportRenderDelta: TimeInterval?
        let renderedSampleTime: AVAudioFramePosition?
        let stagnationDuration: TimeInterval
        let sampleRate: Double?
        let bufferSize: UInt32?
        let playbackState: PlaybackState
        let outputDeviceUID: String?
        let activeTrackName: String?
        let activeTrackURL: URL?
    }

    enum AudioRenderHealth: Equatable {
        case healthy
        case suspectedStall(duration: TimeInterval)
        case confirmedStall(duration: TimeInterval)
    }

    enum AudioRecoveryState: Equatable {
        case idle, interrupted, rebuilding, validating, failed
    }

    struct AudioRecoverySnapshot: Equatable {
        let playbackState: PlaybackState
        let trackID: String?
        let trackName: String?
        let transportPosition: TimeInterval
        let renderedPosition: TimeInterval?
        let engineIsRunning: Bool
        let playerIsPlaying: Bool
        let sampleRate: Double?
        let outputDeviceUID: String?
        let hostTime: TimeInterval
        let reason: String
    }

    struct AudioRecoveryEvent: Identifiable, Equatable {
        enum Result: String, Equatable { case success, failed, ignored }
        let id: UUID
        let date: Date
        let startedAt: TimeInterval
        let endedAt: TimeInterval
        let duration: TimeInterval
        let coalescedNotifications: Int
        let snapshot: AudioRecoverySnapshot
        let resumePosition: TimeInterval
        let result: Result
        let engineStartError: String?
        let renderedProofPosition: TimeInterval?
        let renderedProofSampleTime: AVAudioFramePosition?
    }

    // MARK: - État observable

    private(set) var state: PlaybackState = .stopped

    /// URL du fichier actuellement chargé (nil si rien n'est chargé).
    private(set) var currentURL: URL?
    private var diagnosticTrackID: String?
    private var diagnosticTrackName: String?

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

    /// Position théorique du transport, indépendante du rendu CoreAudio.
    /// C'est volontairement la même horloge que `livePosition`.
    private(set) var transportPosition: TimeInterval = 0

    /// Position réellement rendue par le player actif. nil tant que
    /// `lastRenderTime` / `playerTime(forNodeTime:)` ne sont pas disponibles.
    private(set) var renderedAudioPosition: TimeInterval?

    /// Dernière anomalie publiée vers l'interface. Elle reste visible jusqu'à
    /// un nouveau Play afin qu'une coupure transitoire ne disparaisse pas.
    private(set) var latestContinuityDiagnostic: ContinuityDiagnostic?

    /// Historique mémoire borné des diagnostics de la session courante.
    private(set) var continuityDiagnostics: [ContinuityDiagnostic] = []

    /// État synthétique observable du rendu. Informatif uniquement : aucune
    /// transition de transport ou tentative de récupération n'en dépend.
    private(set) var audioRenderHealth: AudioRenderHealth = .healthy
    private(set) var audioRecoveryState: AudioRecoveryState = .idle
    private(set) var audioRecoveryHistory: [AudioRecoveryEvent] = []

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
    // Rampes de volume et de filtre : DispatchSourceTimer sur une queue
    // série dédiée, HORS main thread. Les fades restaient sur le main
    // thread (Timer + Task @MainActor) et se faisaient affamer par les
    // passes de layout SwiftUI pendant la lecture (~10 pas au lieu de 120
    // sur un fondu de 2 s en Release) — paliers audibles.
    //
    // Synchronisation : `rampLock` protège les epochs, les écritures de
    // paramètre des ticks et les compteurs [XFADE METRICS]. Annuler une
    // rampe = incrémenter son epoch sous le lock puis cancel() la source :
    // toute tick ou completion encore en vol voit un epoch différent et
    // devient un no-op — pas de tick zombie, pas de double completion.
    nonisolated(unsafe) private var fadeTimer: DispatchSourceTimer?
    nonisolated(unsafe) private var filterTimer: DispatchSourceTimer?
    nonisolated(unsafe) private let rampLock = NSLock()
    nonisolated(unsafe) private var fadeEpoch = 0
    nonisolated(unsafe) private var filterEpoch = 0
    nonisolated(unsafe) private var crossfadeEpoch = 0
    private static let rampQueue = DispatchQueue(
        label: "fr.loveandlive.velvetshow.audio-ramps",
        qos: .userInteractive
    )

    // ── Horloge scheduler (lecture hors main thread) ─────────────────────
    // Miroir verrouillé des ancres de position, publié à chaque transport.
    // Purement additif : aucun changement de comportement audio. Permet au
    // scheduler MIDI/OSC (queue dédiée) de calculer la même position que
    // `livePosition` / `crossfadeIncomingLivePosition` sans toucher au
    // MainActor. Sémantique identique au tick historique :
    //   - crossfade en cours → position du song ENTRANT ;
    //   - sinon → livePosition du song courant ;
    //   - isPlaying == (state == .playing), comme le guard du scheduler.
    private struct SchedulerClockSnapshot {
        var isPlaying = false
        var isCrossfading = false
        var anchorPosition: TimeInterval = 0     // positionAtPlayStart
        var anchorHostTime: TimeInterval = 0     // playStartHostTime
        var effectiveEnd: TimeInterval = .infinity
        var crossfadeAnchorPosition: TimeInterval = 0
        var crossfadeAnchorHostTime: TimeInterval = 0
        var crossfadeEnd: TimeInterval = .infinity
    }
    nonisolated(unsafe) private var clockSnapshot = SchedulerClockSnapshot()
    nonisolated(unsafe) private let clockLock = NSLock()

    /// Publie l'état courant vers le miroir. À appeler après toute mutation
    /// de state / ancres / trims / crossfade (MainActor).
    private func publishSchedulerClock() {
        let snap = SchedulerClockSnapshot(
            isPlaying: state == .playing,
            isCrossfading: isCrossfading,
            anchorPosition: positionAtPlayStart,
            anchorHostTime: playStartHostTime,
            effectiveEnd: effectiveEnd,
            crossfadeAnchorPosition: crossfadeTrimStart,
            crossfadeAnchorHostTime: crossfadeStartHostTime,
            crossfadeEnd: crossfadeEffectiveEnd
        )
        clockLock.lock()
        clockSnapshot = snap
        clockLock.unlock()
    }

    /// Position lisible depuis n'importe quel thread — même valeur que
    /// `crossfadeIncomingLivePosition ?? livePosition` du tick historique.
    nonisolated func schedulerClockNow() -> (position: TimeInterval, isPlaying: Bool, effectiveEnd: TimeInterval, isCrossfading: Bool) {
        clockLock.lock()
        let snap = clockSnapshot
        clockLock.unlock()
        let now = CACurrentMediaTime()
        if snap.isCrossfading {
            let pos = min(snap.crossfadeEnd, snap.crossfadeAnchorPosition + (now - snap.crossfadeAnchorHostTime))
            return (pos, snap.isPlaying || snap.isCrossfading, snap.crossfadeEnd, true)
        }
        guard snap.isPlaying else { return (snap.anchorPosition, false, snap.effectiveEnd, false) }
        let pos = min(snap.effectiveEnd, snap.anchorPosition + (now - snap.anchorHostTime))
        return (pos, true, snap.effectiveEnd, false)
    }
    private var meterTapInstalled = false
    private var playStartHostTime: TimeInterval = 0
    private var positionAtPlayStart: TimeInterval = 0
    private var didEndishSegment: Bool = false
    private var scheduleEpoch: Int = 0
    private var hasEverPlayed: Bool = false   // [AUDIO-DIAG] premier play détection
    private(set) var isSeeking: Bool = false

    // État du moniteur de continuité — MainActor uniquement, échantillonné
    // par le timer UI à 30 Hz. Aucun de ces champs n'est touché par le tap.
    private static let continuityThreshold: TimeInterval = 0.300
    private static let maximumContinuityDiagnostics = 50
    private var renderAnchorSampleTime: AVAudioFramePosition?
    private var renderAnchorPosition: TimeInterval = 0
    private var lastObservedRenderedSampleTime: AVAudioFramePosition?
    private var lastObservedTransportPosition: TimeInterval = 0
    private var stagnationStartedAt: TimeInterval?
    private var lastRecordedAnomalyReasons: [ContinuityDiagnostic.Reason] = []
    private var lastMonitoredNode: AVAudioPlayerNode?

    private static let recoveryValidationTimeout: TimeInterval = 0.800
    private static let maximumRecoveryPasses = 2
    private static let maximumRecoveryHistory = 30
    // Tolérance empirique couvrant le décalage de lecture entre l'horloge du
    // transport et celle du rendu, échantillonnées successivement à 30 Hz.
    private static let recoveryRenderedLeadTolerance: TimeInterval = 0.050
    // Décision produit : durée maximale d'audio acceptable à rejouer. Au-delà,
    // la reprise privilégie le transport pour rester synchronisée avec le show.
    private static let recoveryMaximumReplayDuration: TimeInterval = 1.000
    private var recoverySnapshot: AudioRecoverySnapshot?
    private var recoveryResumePosition: TimeInterval = 0
    private var recoveryStartedAt: TimeInterval = 0
    private var recoveryValidationDeadline: TimeInterval = 0
    private var recoveryValidationSampleTime: AVAudioFramePosition?
    private var recoveryPassCount = 0
    private var recoveryCoalescedNotifications = 0
    private var recoveryPassPending = false
    private var recoveryStartError: String?

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
    nonisolated(unsafe) private var crossfadeTimer: DispatchSourceTimer?

    /// Durée du mix en cours, mémorisée à `startCrossfade` — réutilisée par
    /// le filet de sécurité de `scheduleSentinelle` pour forcer la
    /// récupération d'un nœud si sa queue CoreAudio n'a pas naturellement
    /// drainé après une marge confortable au-delà de la fin du fondu.
    private var crossfadeMixDuration: TimeInterval = 0

    // ── [XFADE METRICS] Instrumentation temporaire ──────────────────────
    #if DEBUG
    nonisolated(unsafe) private var metricsOutgoingTicks = 0
    nonisolated(unsafe) private var metricsIncomingTicks = 0
    nonisolated(unsafe) private var metricsMaxGapMs = 0.0
    nonisolated(unsafe) private var metricsLastOutgoingTickAt: Double?
    nonisolated(unsafe) private var metricsLastIncomingTickAt: Double?
    private var metricsHALOverloads = 0
    private var metricsOverloadsAtFadeStart = 0
    private var halOverloadListenerInstalled = false
    nonisolated(unsafe) private var halOverloadBlock: AudioObjectPropertyListenerBlock?
    #endif

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
                self?.requestAudioRecovery(reason: "AVAudioEngineConfigurationChange")
            }
        }
    }

    deinit {
        timer?.invalidate()
        fadeTimer?.cancel()
        filterTimer?.cancel()
        crossfadeTimer?.cancel()
        if let url = scopedFolderURL {
            url.stopAccessingSecurityScopedResource()
        }
        if let url = crossfadeScopedFolderURL {
            url.stopAccessingSecurityScopedResource()
        }
        #if DEBUG
        // AudioEngine est @MainActor — deinit est toujours déclenché depuis
        // MainActor. assumeIsolated permet d'accéder aux propriétés isolées.
        MainActor.assumeIsolated {
            if halOverloadListenerInstalled, let block = halOverloadBlock,
               let deviceID = Self.defaultOutputDeviceID() {
                var overloadAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioDeviceProcessorOverload,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                AudioObjectRemovePropertyListenerBlock(deviceID, &overloadAddr, .main, block)
            }
        }
        #endif
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
        diagnosticTrackID: String? = nil,
        diagnosticTrackName: String? = nil,
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
            self.diagnosticTrackID = diagnosticTrackID
            self.diagnosticTrackName = diagnosticTrackName

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
            publishSchedulerClock()

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
        publishSchedulerClock()
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
        diagnosticTrackID = nil
        diagnosticTrackName = nil
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

    func play(fadeInDuration: TimeInterval = 0) {
        guard audioFile != nil else { return }
        guard state != .playing else { return }
        cancelFadeRamp()
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
        if fadeInDuration > 0 {
            print("[AUDIO] fade-in start — vol=0 → target=\(String(format:"%.3f",targetVolume)) dur=\(fadeInDuration)s")
        }
        state = .playing
        resetContinuityMonitor(clearPublishedWarning: true)
        print("[AUDIO] engine state → .playing")
        if !meterTapInstalled {
            installMeterTap()
            meterTapInstalled = true
        }
        didEndishSegment = false
        playStartHostTime = CACurrentMediaTime()
        positionAtPlayStart = currentPosition
        startTimer()
        publishSchedulerClock()
        if fadeInDuration > 0 {
            fadeVolume(to: targetVolume, duration: fadeInDuration) {
                print("[AUDIO] fade-in end — vol=\(String(format:"%.3f",targetVolume))")
            }
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
        publishSchedulerClock()
    }

    func seek(to position: TimeInterval) {
        guard audioFile != nil else { return }
        let target = max(effectiveStart, min(position + effectiveStart, effectiveEnd))
        currentPosition = target

        guard state == .playing else { return }
        cancelFadeRamp()
        activeNode.volume = 0
        scheduleSegment(from: target)
        activeNode.volume = 0
        activeNode.play()
        fadeVolume(to: playbackGain, duration: 0.025)
        didEndishSegment = false
        playStartHostTime = CACurrentMediaTime()
        positionAtPlayStart = target
        resetContinuityMonitor(clearPublishedWarning: false)
        startTimer()
        publishSchedulerClock()
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
        cancelFadeRamp()

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
            self.resetContinuityMonitor(clearPublishedWarning: false)
            self.startTimer()
            self.publishSchedulerClock()
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
        publishSchedulerClock()

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
        publishSchedulerClock()
        fadeVolume(to: 0, duration: fadeOutDuration) { [weak self] in
            print("[AUDIO] fade-out end — calling stopImmediately()")
            self?.stopImmediately()
        }
    }

    func stopImmediately() {
        if isCrossfading { cancelCrossfade() }
        cancelFadeRamp()
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
        publishSchedulerClock()
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
        cancelFadeRamp()

        // Étape 1 — Arme le delay de la chaîne active (peut flusher le buffer si delayTime change).
        // activeNode continue at plein volume → remplit le buffer au nouveau delayTime.
        activeDelayNode.delayTime     = min(2.0, beatDuration)  // AVAudioUnitDelay max = 2 s
        activeDelayNode.feedback      = 65
        activeDelayNode.wetDryMix     = 100
        activeDelayNode.lowPassCutoff = 12000
        activeReverbNode.wetDryMix    = 20
        state = .stopping
        stopTimer()
        publishSchedulerClock()

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
        crossfadeMixDuration = duration
        publishSchedulerClock()
        #if DEBUG
        metricsResetForFade()
        #endif

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
        cancelCrossfadeRamp()
        cancelFadeRamp()
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
        publishSchedulerClock()
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
        #if DEBUG
        metricsPrintSummary(actualDuration: elapsed)
        #endif

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
        publishSchedulerClock()

        // Sentinelle sur le nœud sortant : fire quand sa queue est vide → stop() safe.
        // Aucun stop() ici — outgoing est au volume 0 mais sa queue n'est pas encore vide.
        scheduleSentinelle(on: outgoing)

        let name = activeNode === nodeA ? "nodeA" : activeNode === nodeB ? "nodeB" : "nodeC"
        print("[XFADE] Swap complete: activeNode=\(name) pos=\(String(format:"%.2f",pos))s")
    }

    // MARK: - [XFADE METRICS] Instrumentation temporaire

    #if DEBUG
    private func metricsResetForFade() {
        rampLock.lock()
        metricsOutgoingTicks = 0
        metricsIncomingTicks = 0
        metricsMaxGapMs = 0
        metricsLastOutgoingTickAt = nil
        metricsLastIncomingTickAt = nil
        rampLock.unlock()
        installHALOverloadListenerIfNeeded()
        metricsOverloadsAtFadeStart = metricsHALOverloads
    }

    nonisolated private func metricsRecordFadeTickLocked(outgoing: Bool) {
        let now = CACurrentMediaTime()
        if outgoing {
            if let last = metricsLastOutgoingTickAt {
                metricsMaxGapMs = max(metricsMaxGapMs, (now - last) * 1000)
            }
            metricsLastOutgoingTickAt = now
            metricsOutgoingTicks += 1
        } else {
            if let last = metricsLastIncomingTickAt {
                metricsMaxGapMs = max(metricsMaxGapMs, (now - last) * 1000)
            }
            metricsLastIncomingTickAt = now
            metricsIncomingTicks += 1
        }
    }

    private func metricsPrintSummary(actualDuration: TimeInterval) {
        let (outTicks, inTicks, maxGap): (Int, Int, Double) = rampLock.withLock {
            (metricsOutgoingTicks, metricsIncomingTicks, metricsMaxGapMs)
        }
        let maxFrames = engine.outputNode.auAudioUnit.maximumFramesToRender
        let latencyMs = engine.outputNode.presentationLatency * 1000
        let overloads = metricsHALOverloads - metricsOverloadsAtFadeStart
        let device = Self.defaultOutputDeviceName() ?? "?"
        print("[XFADE METRICS] outgoingTicks=\(outTicks) incomingTicks=\(inTicks) maxGapMs=\(Int(maxGap.rounded())) durationS=\(String(format: "%.2f", actualDuration)) maxFrames=\(maxFrames) latencyMs=\(String(format: "%.1f", latencyMs)) device=\"\(device)\" halOverloads=\(overloads)")
    }

    private func installHALOverloadListenerIfNeeded() {
        guard !halOverloadListenerInstalled else { return }
        guard let deviceID = Self.defaultOutputDeviceID() else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDeviceProcessorOverload,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.metricsHALOverloads += 1
                print("[XFADE METRICS] HAL overload #\(self.metricsHALOverloads)")
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(deviceID, &address, .main, block)
        if status == noErr {
            halOverloadListenerInstalled = true
            halOverloadBlock = block
        }
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private static func defaultOutputDeviceName() -> String? {
        guard let deviceID = defaultOutputDeviceID() else { return nil }
        var name: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }
        guard status == noErr, let name else { return nil }
        return name as String
    }
    #endif

    // MARK: - Annulation des rampes (fade / crossfade / filtre)

    /// Annule la rampe de volume du nœud actif. Le bump d'epoch sous le
    /// lock garantit qu'aucune tick ni completion en vol ne s'exécutera
    /// après le retour de cette fonction (une tick en cours d'écriture
    /// termine d'abord — le lock sérialise).
    private func cancelFadeRamp() {
        rampLock.lock(); fadeEpoch &+= 1; rampLock.unlock()
        fadeTimer?.cancel()
        fadeTimer = nil
    }

    private func cancelCrossfadeRamp() {
        rampLock.lock(); crossfadeEpoch &+= 1; rampLock.unlock()
        crossfadeTimer?.cancel()
        crossfadeTimer = nil
    }

    private func cancelFilterRamp() {
        rampLock.lock(); filterEpoch &+= 1; rampLock.unlock()
        filterTimer?.cancel()
        filterTimer = nil
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
    ///
    /// Filet de sécurité : cette sentinelle ne se déclenche qu'une fois que
    /// TOUT ce qui était programmé sur `node` avant elle a fini de jouer —
    /// potentiellement le reste du morceau entier si la transition a eu
    /// lieu tôt dedans (fréquent en test, remplacements rapprochés). Avec
    /// seulement 3 nœuds, ça peut vider le pool de nœuds disponibles for
    /// plusieurs minutes d'affilée. Un second minuteur, avec la même garde
    /// de génération, force la libération après une marge confortable au-
    /// delà de la fin du fondu — le nœud est alors silencieux depuis
    /// longtemps, stop() n'introduit plus le risque de clic évoqué plus
    /// haut. Le premier des deux (sentinelle réelle ou timeout) qui se
    /// déclenche gagne ; l'autre devient un no-op via la garde `coolingGen`.
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

        let timeoutMs = Int((crossfadeMixDuration + 1.5) * 1000)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(max(timeoutMs, 1500)))
            guard let self, self.coolingGen(capturedNode) == gen else { return }
            capturedNode.stop()
            self.setClean(capturedNode, true)
            let n = capturedNode === self.nodeA ? "nodeA"
                  : capturedNode === self.nodeB ? "nodeB" : "nodeC"
            print("[XFADE] Sentinelle timeout — \(n) forcé propre (buffer pas encore drainé)")
        }
    }

    /// Variante de `fadeVolume` for le nœud entrant.
    /// Source et epoch indépendants — les deux fades coexistent sans
    /// s'invalider mutuellement. `node` est capturé at l'appel.
    /// Tourne sur `rampQueue` (hors main thread) : la cadence 60 Hz est
    /// tenue même quand SwiftUI sature le main actor.
    private func fadeCrossfadeVolume(
        node: AVAudioPlayerNode,
        to target: Float,
        duration: TimeInterval,
        completion: (() -> Void)? = nil
    ) {
        cancelCrossfadeRamp()

        guard duration > 0 else {
            node.volume = target
            completion?()
            return
        }

        let startVolume = node.volume
        let startedAt   = CACurrentMediaTime()
        #if DEBUG
        let recordMetrics = isCrossfading
        #endif
        let epoch = rampLock.withLock { crossfadeEpoch }

        let source = DispatchSource.makeTimerSource(queue: Self.rampQueue)
        source.schedule(deadline: .now() + 1.0 / 60.0, repeating: 1.0 / 60.0, leeway: .milliseconds(2))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let progress = min(1.0, (CACurrentMediaTime() - startedAt) / duration)
            let volume: Float
            if target <= 0 {
                volume = startVolume * Float(cos(Double(progress) * .pi / 2))
            } else if startVolume <= 0 {
                volume = target * Float(sin(Double(progress) * .pi / 2))
            } else {
                volume = startVolume + (target - startVolume) * Float(progress)
            }
            self.rampLock.lock()
            guard self.crossfadeEpoch == epoch else { self.rampLock.unlock(); return }
            node.volume = progress >= 1.0 ? target : volume
            #if DEBUG
            if recordMetrics { self.metricsRecordFadeTickLocked(outgoing: false) }
            #endif
            if progress >= 1.0 {
                // Claim la fin sous le lock : plus aucune tick, une seule completion.
                self.crossfadeEpoch &+= 1
                self.rampLock.unlock()
                source.cancel()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    // Ignorée si une annulation/nouvelle rampe est passée entre-temps.
                    guard self.rampLock.withLock({ self.crossfadeEpoch == epoch &+ 1 }) else { return }
                    MainActor.assumeIsolated {
                        self.crossfadeTimer = nil
                        completion?()
                    }
                }
            } else {
                self.rampLock.unlock()
            }
        }
        crossfadeTimer = source
        source.activate()
    }

    // MARK: - Filter sweep (FILTER transition)

    /// Remet filterNode at l'état transparent (cutoff 20 kHz).
    /// Appelé depuis stopImmediately, cancelCrossfade, finishCrossfade
    /// et handleEngineConfigurationChange.
    private func resetFilter() {
        // L'epoch est bumpé sous le lock avant l'écriture : toute tick de
        // sweep en vol a fini son écriture ou la sautera — le 20000 gagne.
        cancelFilterRamp()
        activeFilterNode.bands[0].frequency = 20000
    }

    /// Anime le cutoff low-pass de 20 kHz → 300 Hz sur `duration` secondes.
    /// Courbe logarithmique (perçue comme linéaire at l'oreille).
    /// Tourne sur `rampQueue` (hors main thread), comme les fades.
    private func startFilterSweep(duration: TimeInterval) {
        cancelFilterRamp()

        let logStart = log10(20000.0)
        let logEnd   = log10(800.0)
        let startedAt = CACurrentMediaTime()
        // Capturé une fois : la rotation des rôles (finishCrossfade) n'a
        // lieu qu'après resetFilter, le nœud visé ne change pas en cours de sweep.
        let eq = activeFilterNode
        let epoch = rampLock.withLock { filterEpoch }

        let source = DispatchSource.makeTimerSource(queue: Self.rampQueue)
        source.schedule(deadline: .now() + 1.0 / 60.0, repeating: 1.0 / 60.0, leeway: .milliseconds(2))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let progress = min(1.0, (CACurrentMediaTime() - startedAt) / duration)
            let logFreq  = logStart + (logEnd - logStart) * progress
            self.rampLock.lock()
            guard self.filterEpoch == epoch else { self.rampLock.unlock(); return }
            eq.bands[0].frequency = progress >= 1.0 ? 800 : Float(pow(10.0, logFreq))
            if progress >= 1.0 {
                self.filterEpoch &+= 1
                self.rampLock.unlock()
                source.cancel()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard self.rampLock.withLock({ self.filterEpoch == epoch &+ 1 }) else { return }
                    MainActor.assumeIsolated { self.filterTimer = nil }
                }
            } else {
                self.rampLock.unlock()
            }
        }
        filterTimer = source
        source.activate()
    }

    // MARK: - Reconfiguration périphérique audio

    private func requestAudioRecovery(reason: String) {
        guard audioRecoveryState == .idle || audioRecoveryState == .failed else {
            recoveryPassPending = true
            recoveryCoalescedNotifications += 1
            return
        }
        recoveryPassCount = 0
        recoveryCoalescedNotifications = 0
        recoveryPassPending = false
        recoveryStartedAt = CACurrentMediaTime()
        recoverySnapshot = makeRecoverySnapshot(reason: reason)
        startRecoveryPass()
    }

    private func makeRecoverySnapshot(reason: String) -> AudioRecoverySnapshot {
        let device = currentOutputDeviceDiagnostic()
        return AudioRecoverySnapshot(
            playbackState: state,
            trackID: diagnosticTrackID,
            trackName: diagnosticTrackName ?? currentURL?.lastPathComponent,
            transportPosition: livePosition,
            renderedPosition: renderedAudioPosition,
            engineIsRunning: engine.isRunning,
            playerIsPlaying: activeNode.isPlaying,
            sampleRate: sampleRenderedPosition()?.sampleRate ?? audioFile?.processingFormat.sampleRate,
            outputDeviceUID: device.uid,
            hostTime: CACurrentMediaTime(),
            reason: reason
        )
    }

    private func startRecoveryPass() {
        guard let snapshot = recoverySnapshot,
              recoveryPassCount < Self.maximumRecoveryPasses else {
            finishRecovery(result: .failed, proof: nil)
            return
        }
        recoveryPassCount += 1
        audioRecoveryState = .interrupted

        let rendered = snapshot.renderedPosition
        let renderedIsPlausible = rendered.map {
            $0 >= effectiveStart && $0 < effectiveEnd
                && snapshot.transportPosition - $0 >= -Self.recoveryRenderedLeadTolerance
                && snapshot.transportPosition - $0 <= Self.recoveryMaximumReplayDuration
        } ?? false
        recoveryResumePosition = renderedIsPlausible
            ? rendered!
            : min(effectiveEnd, max(effectiveStart, snapshot.transportPosition))

        audioRecoveryState = .rebuilding
        scheduleEpoch &+= 1
        coolingGenA &+= 1; coolingGenB &+= 1; coolingGenC &+= 1
        if meterTapInstalled {
            engine.mainMixerNode.removeTap(onBus: 0)
            meterTapInstalled = false
        }
        engine.stop()
        for node in [nodeA, nodeB, nodeC] {
            node.stop()
            setClean(node, true)
        }
        for node in [nodeA, filterNodeA, delayNodeA, reverbNodeA,
                     nodeB, filterNodeB, delayNodeB, reverbNodeB,
                     nodeC, filterNodeC, delayNodeC, reverbNodeC] {
            engine.disconnectNodeOutput(node)
        }
        connectRecoveryChain(nodeA, filterNodeA, delayNodeA, reverbNodeA)
        connectRecoveryChain(nodeB, filterNodeB, delayNodeB, reverbNodeB)
        connectRecoveryChain(nodeC, filterNodeC, delayNodeC, reverbNodeC)
        resetFilter()
        if isCrossfading {
            cancelCrossfade()
            onCrossfadeAborted?()
        }

        do {
            try engine.start()
            installMeterTap()
            meterTapInstalled = true
            currentPosition = recoveryResumePosition
            recoveryStartError = nil
            guard snapshot.playbackState == .playing, audioFile != nil else {
                state = snapshot.playbackState
                finishRecovery(result: .success, proof: nil)
                return
            }
            scheduleSegment(from: recoveryResumePosition)
            activeNode.volume = playbackGain
            activeNode.play()
            state = .playing
            playStartHostTime = CACurrentMediaTime()
            positionAtPlayStart = recoveryResumePosition
            resetContinuityMonitor(clearPublishedWarning: false)
            publishSchedulerClock()
            recoveryValidationSampleTime = sampleRenderedPosition()?.sampleTime
            recoveryValidationDeadline = CACurrentMediaTime() + Self.recoveryValidationTimeout
            audioRecoveryState = .validating
        } catch {
            recoveryStartError = error.localizedDescription
            lastError = "Audio device changed: resume failed (\(error.localizedDescription))"
            finishRecovery(result: .failed, proof: nil)
        }
    }

    private func connectRecoveryChain(
        _ player: AVAudioPlayerNode,
        _ filter: AVAudioUnitEQ,
        _ delay: AVAudioUnitDelay,
        _ reverb: AVAudioUnitReverb
    ) {
        engine.connect(player, to: filter, format: nil)
        engine.connect(filter, to: delay, format: nil)
        engine.connect(delay, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
    }

    private func validateRecovery(now: TimeInterval) {
        guard audioRecoveryState == .validating else { return }
        let proof = sampleRenderedPosition()
        if let sample = proof?.sampleTime,
           recoveryValidationSampleTime == nil || sample > recoveryValidationSampleTime! {
            finishRecovery(result: .success, proof: proof)
        } else if now >= recoveryValidationDeadline {
            finishRecovery(result: .failed, proof: proof)
        }
    }

    private func finishRecovery(
        result: AudioRecoveryEvent.Result,
        proof: (position: TimeInterval, sampleTime: AVAudioFramePosition, sampleRate: Double)?
    ) {
        guard let snapshot = recoverySnapshot else { return }
        let endedAt = CACurrentMediaTime()
        audioRecoveryHistory.append(AudioRecoveryEvent(
            id: UUID(), date: Date(), startedAt: recoveryStartedAt, endedAt: endedAt,
            duration: endedAt - recoveryStartedAt,
            coalescedNotifications: recoveryCoalescedNotifications,
            snapshot: snapshot, resumePosition: recoveryResumePosition,
            result: result, engineStartError: recoveryStartError,
            renderedProofPosition: proof?.position,
            renderedProofSampleTime: proof?.sampleTime
        ))
        if audioRecoveryHistory.count > Self.maximumRecoveryHistory {
            audioRecoveryHistory.removeFirst(audioRecoveryHistory.count - Self.maximumRecoveryHistory)
        }
        let shouldRepeat = recoveryPassPending && recoveryPassCount < Self.maximumRecoveryPasses
        recoveryPassPending = false
        audioRecoveryState = result == .failed ? .failed : .idle
        if shouldRepeat {
            audioRecoveryState = .interrupted
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.recoverySnapshot = self.makeRecoverySnapshot(
                    reason: "coalescedConfigurationChange"
                )
                self.recoveryStartedAt = CACurrentMediaTime()
                self.startRecoveryPass()
            }
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

    /// Réinitialise uniquement les ancres du diagnostic. N'agit ni sur le
    /// moteur, ni sur le player, ni sur le scheduling audio.
    private func resetContinuityMonitor(clearPublishedWarning: Bool) {
        transportPosition = currentPosition
        renderedAudioPosition = nil
        renderAnchorSampleTime = nil
        renderAnchorPosition = currentPosition
        lastObservedRenderedSampleTime = nil
        lastObservedTransportPosition = currentPosition
        stagnationStartedAt = nil
        lastRecordedAnomalyReasons = []
        lastMonitoredNode = activeNode
        audioRenderHealth = .healthy
        if clearPublishedWarning { latestContinuityDiagnostic = nil }
    }

    /// Convertit l'horloge du player en position absolue dans le fichier.
    /// La première valeur valide devient l'ancre de cette séquence de lecture.
    private func sampleRenderedPosition() -> (
        position: TimeInterval,
        sampleTime: AVAudioFramePosition,
        sampleRate: Double
    )? {
        if lastMonitoredNode !== activeNode {
            renderAnchorSampleTime = nil
            lastObservedRenderedSampleTime = nil
            renderAnchorPosition = positionAtPlayStart
            lastMonitoredNode = activeNode
        }
        guard let nodeTime = activeNode.lastRenderTime,
              let playerTime = activeNode.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0 else { return nil }

        if renderAnchorSampleTime == nil
            || playerTime.sampleTime < (renderAnchorSampleTime ?? playerTime.sampleTime) {
            renderAnchorSampleTime = playerTime.sampleTime
            renderAnchorPosition = positionAtPlayStart
        }
        guard let anchor = renderAnchorSampleTime else { return nil }
        let elapsedFrames = max(0, playerTime.sampleTime - anchor)
        let position = min(effectiveEnd, renderAnchorPosition + Double(elapsedFrames) / playerTime.sampleRate)
        return (position, playerTime.sampleTime, playerTime.sampleRate)
    }

    /// Capture CoreAudio effectuée seulement lors de la création d'un
    /// diagnostic confirmé, jamais dans le callback audio ni à chaque tick.
    private func currentOutputDeviceDiagnostic() -> (uid: String?, bufferSize: UInt32?) {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var deviceIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddress,
            0,
            nil,
            &deviceIDSize,
            &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else {
            return (nil, nil)
        }

        var unmanagedUID: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let uidStatus = AudioObjectGetPropertyData(
            deviceID,
            &uidAddress,
            0,
            nil,
            &uidSize,
            &unmanagedUID
        )
        let uid = uidStatus == noErr
            ? unmanagedUID?.takeUnretainedValue() as String?
            : nil

        var frames: UInt32 = 0
        var framesSize = UInt32(MemoryLayout<UInt32>.size)
        var framesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let framesStatus = AudioObjectGetPropertyData(
            deviceID,
            &framesAddress,
            0,
            nil,
            &framesSize,
            &frames
        )
        return (
            uid,
            framesStatus == noErr ? frames : nil
        )
    }

    /// Observe la continuité sans tenter aucune récupération. Toute allocation
    /// liée au diagnostic a lieu ici, sur MainActor, jamais dans le tap audio.
    private func monitorAudioContinuity(now: TimeInterval, transport: TimeInterval) {
        transportPosition = transport
        let engineRunning = engine.isRunning
        let playerPlaying = activeNode.isPlaying
        let rendered = sampleRenderedPosition()
        renderedAudioPosition = rendered?.position

        let transportAdvanced = transport > lastObservedTransportPosition + 0.001
        let sampleAdvanced: Bool
        if let sample = rendered?.sampleTime, let previous = lastObservedRenderedSampleTime {
            sampleAdvanced = sample > previous
        } else {
            sampleAdvanced = rendered != nil && lastObservedRenderedSampleTime == nil
        }

        if transportAdvanced && !sampleAdvanced {
            if stagnationStartedAt == nil { stagnationStartedAt = now }
        } else if sampleAdvanced {
            stagnationStartedAt = nil
            lastRecordedAnomalyReasons = []
        }

        if let sample = rendered?.sampleTime { lastObservedRenderedSampleTime = sample }
        lastObservedTransportPosition = transport
        let stagnantFor = stagnationStartedAt.map { max(0, now - $0) } ?? 0

        if !engineRunning || stagnantFor >= Self.continuityThreshold {
            audioRenderHealth = .confirmedStall(duration: stagnantFor)
        } else if stagnantFor > 0 {
            audioRenderHealth = .suspectedStall(duration: stagnantFor)
        } else {
            audioRenderHealth = .healthy
        }

        var reasons: [ContinuityDiagnostic.Reason] = []
        if !engineRunning { reasons.append(.engineNotRunning) }
        if stagnantFor >= Self.continuityThreshold {
            reasons.append(.playerNotRendering)
        }
        if transportAdvanced && stagnantFor >= Self.continuityThreshold {
            reasons.append(.transportAheadOfRenderedAudio)
        }
        guard !reasons.isEmpty, reasons != lastRecordedAnomalyReasons else { return }
        lastRecordedAnomalyReasons = reasons
        let outputDevice = currentOutputDeviceDiagnostic()

        let diagnostic = ContinuityDiagnostic(
            id: UUID(),
            date: Date(),
            hostTime: now,
            trackID: diagnosticTrackID ?? currentURL?.standardizedFileURL.path,
            reasons: reasons,
            engineIsRunning: engineRunning,
            playerIsPlaying: playerPlaying,
            transportPosition: transport,
            renderedPosition: rendered?.position,
            transportRenderDelta: rendered.map { transport - $0.position },
            renderedSampleTime: rendered?.sampleTime,
            stagnationDuration: stagnantFor,
            sampleRate: rendered?.sampleRate,
            bufferSize: outputDevice.bufferSize,
            playbackState: state,
            outputDeviceUID: outputDevice.uid,
            activeTrackName: diagnosticTrackName ?? currentURL?.lastPathComponent,
            activeTrackURL: currentURL
        )
        latestContinuityDiagnostic = diagnostic
        continuityDiagnostics.append(diagnostic)
        if continuityDiagnostics.count > Self.maximumContinuityDiagnostics {
            continuityDiagnostics.removeFirst(continuityDiagnostics.count - Self.maximumContinuityDiagnostics)
        }
    }

    /// Rampe de volume du nœud actif, sur `rampQueue` (hors main thread) :
    /// la cadence 60 Hz est tenue même quand SwiftUI sature le main actor.
    /// La completion est toujours livrée sur MainActor, une seule fois, et
    /// abandonnée si la rampe a été annulée entre-temps (epoch divergent).
    private func fadeVolume(
        to target: Float,
        duration: TimeInterval,
        completion: (() -> Void)? = nil
    ) {
        cancelFadeRamp()

        guard duration > 0 else {
            activeNode.volume = target
            completion?()
            return
        }

        // Capturé une fois : la rotation des rôles (finishCrossfade) n'a
        // lieu qu'après la fin du fade, le nœud visé ne change pas en cours
        // de rampe.
        let node = activeNode!
        let startVolume = node.volume
        let startedAt = CACurrentMediaTime()
        #if DEBUG
        let recordMetrics = isCrossfading
        #endif
        let epoch = rampLock.withLock { fadeEpoch }

        let source = DispatchSource.makeTimerSource(queue: Self.rampQueue)
        source.schedule(deadline: .now() + 1.0 / 60.0, repeating: 1.0 / 60.0, leeway: .milliseconds(2))
        source.setEventHandler { [weak self] in
            guard let self else { return }
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
            self.rampLock.lock()
            guard self.fadeEpoch == epoch else { self.rampLock.unlock(); return }
            node.volume = progress >= 1.0 ? target : volume  // valeur exacte garantie en fin
            #if DEBUG
            if recordMetrics { self.metricsRecordFadeTickLocked(outgoing: true) }
            #endif
            if progress >= 1.0 {
                // Claim la fin sous le lock AVANT la completion : plus aucune
                // tick, et une seule completion possible (l'équivalent du bump
                // de génération pré-completion — cf. crash log djay 26/06).
                self.fadeEpoch &+= 1
                self.rampLock.unlock()
                source.cancel()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    // Ignorée si une annulation/nouvelle rampe est passée entre-temps.
                    guard self.rampLock.withLock({ self.fadeEpoch == epoch &+ 1 }) else { return }
                    MainActor.assumeIsolated {
                        self.fadeTimer = nil
                        completion?()
                    }
                }
            } else {
                self.rampLock.unlock()
            }
        }
        fadeTimer = source
        source.activate()
    }

    // VU-mètre : le tap arrive ~43×/s (buffers de 1024 frames). Publier
    // chaque valeur créait 43 Task + 43 invalidations SwiftUI par seconde
    // sur le main thread. On lisse côté tap (attaque immédiate, retombée
    // douce — rendu identique à l'œil) et on publie à ~15 Hz.
    @ObservationIgnored nonisolated(unsafe) private var meterSmoothed: Float = 0
    private var meterLastPublish: Double = 0
    private static let meterPublishInterval: Double = 1.0 / 15.0

    private func installMeterTap() {
        let mixer = engine.mainMixerNode
        let format = mixer.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        mixer.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }
            var sum: Float = 0
            for i in 0..<frameCount { sum += channelData[i] * channelData[i] }
            let rms = sqrt(sum / Float(frameCount))

            // Lissage sur le thread du tap (sériel) : attaque immédiate,
            // retombée exponentielle ~70 ms — mêmes crêtes visibles.
            if rms >= self.meterSmoothed {
                self.meterSmoothed = rms
            } else {
                self.meterSmoothed = self.meterSmoothed * 0.72 + rms * 0.28
            }

            // Publication différée par `tick()` sur MainActor : aucune Task,
            // aucun print et aucune allocation dans ce callback temps réel.
        }
    }

    private func tick() {
        guard state == .playing else { return }
        let now = CACurrentMediaTime()
        validateRecovery(now: now)
        let theoreticalPosition = min(effectiveEnd, positionAtPlayStart + (now - playStartHostTime))
        monitorAudioContinuity(now: now, transport: theoreticalPosition)
        if now - meterLastPublish >= Self.meterPublishInterval {
            meterLastPublish = now
            meterLevel = meterSmoothed
        }
        // Garde-fou : si le moteur s'est arrêté sans que
        // AVAudioEngineConfigurationChange ait encore été livré,
        // on délègue at handleEngineConfigurationChange qui reconstruit
        // le graph correctement avant de tenter engine.start().
        if !engine.isRunning, audioRecoveryState == .idle {
            requestAudioRecovery(reason: "engineNotRunningDuringPlayback")
            return
        }
        let elapsed = now - playStartHostTime
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

    #if DEBUG
    /// Hooks LLDB réservés aux tests de continuité. Ils ne sont pas présents
    /// dans une archive Release et ne sont jamais appelés par l'application.
    func debugPauseEngineForContinuityTest() {
        engine.pause()
    }

    func debugPausePlayerForContinuityTest() {
        activeNode.pause()
    }

    func debugResumePlayerAfterContinuityTest() {
        activeNode.play()
    }
    #endif
}
