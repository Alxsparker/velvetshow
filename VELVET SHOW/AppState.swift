//
//  AppState.swift
//  VELVET SHOW
//
//  Source de vérité unique for l'interface.
//  Tout passe par cet objet @Observable : la base ouverte, les collections
//  chargées, le mode courant (Track Library / Show Library), les sélections
//  des deux modes, et les caches relationnels utilisés par la fiche de
//  song.
//
//  Idée directrice :
//  - on charge toutes les petites tables en mémoire au moment de l'import,
//  - on construit en une passe les index FK directs et inverses,
//  - l'UI consomme ensuite des dictionnaires en O(1).
//

import Foundation
import SwiftUI
import CoreMIDI
import AppKit
import AVFoundation

/// Les 5 effets de transition DJ disponibles au remplacement de song.
/// `isAvailable = false` → pad visible mais désactivé ("Bientôt") en Phase 1.
enum TransitionEffect: String, CaseIterable, Codable {
    case fade     = "FADE"
    case slowFade = "SLOW FADE"
    case echo     = "ECHO"
    case filter   = "FILTER"
    case backspin = "BACKSPIN"

    var icon: String {
        switch self {
        case .fade:     return "waveform"
        case .slowFade: return "tortoise.fill"
        case .echo:     return "waveform.path.ecg"
        case .filter:   return "slider.horizontal.3"
        case .backspin: return "arrow.counterclockwise"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .fade, .slowFade, .filter: return true
        case .echo, .backspin:          return false
        }
    }

    /// Duration du fade-out for `audioEngine.stop(fadeOutDuration:)`.
    /// ECHO déclenche `stopWithEchoFade(beatDuration:)` — cette valeur n'est pas utilisée.
    var fadeOutDuration: TimeInterval {
        switch self {
        case .fade:     return 1.2
        case .slowFade: return 3.0
        case .filter:   return 2.0
        default:        return 0.0
        }
    }

    /// Delay statique en ms avant de charger le song suivant.
    /// Pour ECHO, le délai est calculé dynamiquement dans `startReplacement`
    /// at partir du BPM du song en cours.
    /// Pour FADE / SLOW FADE / FILTER, cette valeur sert de fallback si
    /// startCrossfade échoue (fichier illisible).
    var loadDelayMillis: Int {
        switch self {
        case .fade:     return Int(1.2 * 1000) + 40   // 1 240 ms
        case .slowFade: return Int(3.0 * 1000) + 40   // 3 040 ms
        case .filter:   return Int(2.0 * 1000) + 40   // 2 040 ms (fallback)
        case .echo:     return Int(2.5 * 1000) + 40   // fallback sans BPM (2 540 ms)
        default:        return Int(1.2 * 1000) + 40
        }
    }
}

@MainActor
@Observable
final class AppState {

    // MARK: - Persistance Velvet Show
    //
    // Une seule instance, créée avant l'init for pouvoir être lue dès le
    // premier `didSet` des collections observables. L'UI accède au statut
    // via `saveStatus` (toolbar).

    let store = VelvetShowStore()

    var saveStatus: VelvetShowSaveStatus { store.status }

    let remoteServer = VelvetRemoteServer()
    @ObservationIgnored private var remotePositionTimer: Timer?

    /// Vrai pendant l'init : les `didSet` ne doivent pas déclencher de
    /// sauvegarde puisqu'on est en train de recopier l'état chargé depuis
    /// le disque dans les propriétés observables.
    @ObservationIgnored private var isLoadingFromStore: Bool = true
    @ObservationIgnored private var isStartingQueuedPlayback: Bool = false

    /// Vrai pendant qu'un remplacement manuel est en cours (fade-out + chargement
    /// du nouveau song). Empêche `handlePlaybackEndished` de déclencher la
    /// Queue Auto si le segment se termine naturellement pendant le fade.
    /// Remis at false dès que le nouveau song démarre.
    @ObservationIgnored private var isReplacingTrack: Bool = false

    /// Tâche en cours for un remplacement manuel. Annulée si un second
    /// remplacement est demandé avant la fin du premier (double-clic, ↩ rapide).
    @ObservationIgnored private var replacementTask: Task<Void, Never>?

    /// Contexte du song préchargé automatiquement en fin de song.
    /// Posé par `handlePlaybackEndished` (Queue .manual ou suivant setlist).
    /// Effacé dès que `handlePlayPauseShortcut` le consomme, ou lors d'un
    /// stop / load explicite.
    @ObservationIgnored private var preloadedPlaybackContext: (set: ShowSet, element: SetElement?)? = nil

    /// setElementID du prochain song naturel (suivant dans la setlist).
    /// Posé dès qu'un song commence, effacé sur stop explicite.
    private(set) var nextNaturalSongElementID: Int64? = nil

    /// Morceau cible d'un crossfade FADE / SLOW FADE en cours.
    /// Utilisé par `onCrossfadeAborted` for récupérer proprement si
    /// AVAudioEngineConfigurationChange interrompt le crossfade.
    @ObservationIgnored private var pendingCrossfadeTrack: AudioFile? = nil

    // MARK: - Scheduler MIDI timeline
    @ObservationIgnored private var firedMidiTriggers: Set<String> = []
    @ObservationIgnored private var midiSchedulerTask: Task<Void, Never>? = nil
    /// Incrémenté at chaque `startMidiScheduler()`. Chaque task capture sa
    /// valeur at la création et sort immédiatement si elle diverge — élimine
    /// les ticks orphelins des tasks en cours d'annulation coopérative.
    @ObservationIgnored private var midiSchedulerGeneration: Int = 0

    /// Dernière position vue par le scheduler. Permet de détecter un seek
    /// (saut > seekDetectionThreshold) et de réaligner `firedMidiTriggers`
    /// sur la nouvelle position. nil avant le premier tick d'une session.
    @ObservationIgnored private var lastSchedulerPos: TimeInterval? = nil

    /// Au-delà de ce delta entre deux ticks, on considère qu'un seek a eu
    /// lieu (les ticks normaux progressent de ~50 ms — même sous charge le
    /// delta reste < 0.3 s).
    private static let seekDetectionThreshold: TimeInterval = 0.3

    /// Vrai pendant qu'un éditeur de timeline est ouvert en mode plein écran
    /// (non-embedded). Empêche `handlePlaybackEndished()` de marquer le
    /// song comme joué et de lancer automatiquement le suivant depuis la
    /// queue. Remis at false at la fermeture de l'éditeur.
    @ObservationIgnored private(set) var isInEditingMode: Bool = false

    // MARK: - Init
    //
    // L'init existe for charger les préférences persistées (destination
    // MaestroDMX choisie par l'utilisateur lors d'une session précédente).
    // Toutes les more propriétés ont des valeurs par défaut inline.

    init() {
        if let stored = UserDefaults.standard.string(forKey: Self.appThemeKey),
           let theme = AppTheme(rawValue: stored) {
            self.appTheme = theme
        }
        if let stored = UserDefaults.standard.string(forKey: Self.prompterThemeKey),
           let theme = PrompterTheme(rawValue: stored) {
            self.prompterTheme = theme
        }
        if let stored = UserDefaults.standard.object(
            forKey: Self.maestroDestinationKey
        ) as? Int {
            self.maestroDestinationID = MIDIUniqueID(stored)
        }
        if let bookmark = UserDefaults.standard.data(
            forKey: Self.mediaFolderBookmarkKey
        ) {
            self.mediaFolderBookmarkData = bookmark
        }
        // Cue de repos — migration depuis les anciennes clés stopCue si présentes.
        let d = UserDefaults.standard
        if let raw = d.object(forKey: "restCueMidiEventID") as? Int {
            self.restCueMidiEventID = Int64(raw)
        } else if let raw = d.object(forKey: Self.stopCueMidiEventIDKey) as? Int {
            // Migration one-shot : ancienne clé → nouvelle clé
            self.restCueMidiEventID = Int64(raw)
            d.set(raw, forKey: "restCueMidiEventID")
        }
        if let v = d.object(forKey: "restCueEnabled") as? Bool { self.restCueEnabled = v }
        if let v = d.object(forKey: "restCueTriggerOnStop") as? Bool { self.restCueTriggerOnStop = v }
        if let v = d.object(forKey: "restCueTriggerOnNaturalEnd") as? Bool {
            self.restCueTriggerOnNaturalEnd = v
        } else if let v = d.object(forKey: Self.sendStopCueOnNaturalEndKey) as? Bool {
            // Migration one-shot : sendStopCueOnNaturalEnd → restCueTriggerOnNaturalEnd
            self.restCueTriggerOnNaturalEnd = v
            d.set(v, forKey: "restCueTriggerOnNaturalEnd")
        }
        if let v = d.object(forKey: "restCueTriggerOnConcertEnd") as? Bool { self.restCueTriggerOnConcertEnd = v }
        if let v = d.object(forKey: "restCueTriggerBetweenTracks") as? Bool { self.restCueTriggerBetweenTracks = v }
        if let v = d.object(forKey: "restCueDelaySeconds") as? Double { self.restCueDelaySeconds = v }
        if let raw = d.string(forKey: "restCueType"), let t = RestCueType(rawValue: raw) {
            self.restCueType = t
        } // sinon → .midi par défaut, comportement legacy préservé
        if let raw = d.string(forKey: "restOscEventID"), let uuid = UUID(uuidString: raw) {
            self.restOscEventID = uuid
        }

        // Phase Persistance : tout l'état "données" est désormais lu depuis
        // le VelvetShowStore. On migre une seule fois ce qui pouvait
        // traîner dans UserDefaults for ne perdre aucun historique.
        Self.migrateLegacyUserDefaultsIfNeeded(into: store)

        let snapshot = store.state
        self.editableMemosByAudioFileID = snapshot.editableMemosByAudioFileID.keyedByInt64()
        self.memoAttachmentsByMemoID = Self.attachmentsByUUID(from: snapshot.memoAttachmentsByMemoID)
        self.playedSetElementIDsBySetID = Self.playedSet(from: snapshot.playedSetElementIDsBySetID)
        self.velvetTracks = snapshot.velvetTracks
        self.velvetShows = snapshot.velvetShows
        self.velvetShowOrder = snapshot.velvetShowOrder
        self.trashedTracks = snapshot.trashedTracks
        self.liveAdditionsBySetID = snapshot.liveAdditionsBySetID.keyedByInt64()
        self.concertQueueBySetID = snapshot.concertQueueBySetID.keyedByInt64()
        self.concertHistory = snapshot.concertHistory
        self.activeConcertIDBySetID = snapshot.activeConcertIDBySetID.keyedByInt64()
        self.selectedConcertGenre = ConcertGenre(rawValue: snapshot.selectedConcertGenreRaw) ?? .all
        self.isSafePlayEnabled = snapshot.isSafePlayEnabled
        self.isQuickLibraryVisible = snapshot.isQuickLibraryVisible
        self.customOrderBySetID = snapshot.customOrderBySetID.keyedByInt64()
        self.genreColors = Self.genreColors(from: snapshot.genreColors)
        self.customGenreColors = snapshot.customGenreColors
        self.trimsByAudioFileID = snapshot.trimsByAudioFileID.keyedByInt64()
        self.volumeByAudioFileID = snapshot.volumeByAudioFileID.keyedByInt64()
        self.trackColorsByAudioFileID = snapshot.trackColorsByAudioFileID.keyedByInt64()
        self.cuePointsByAudioFileID = snapshot.cuePointsByAudioFileID.keyedByInt64()
        self.midiCuesByAudioFileID    = snapshot.midiCuesByAudioFileID.keyedByInt64()
        self.archivedMidiEventIDs     = Set(snapshot.archivedMidiEventIDs)
        self.oscCuesByAudioFileID     = snapshot.oscCuesByAudioFileID.keyedByInt64()
        self.oscEventsByID            = Dictionary(uniqueKeysWithValues: snapshot.velvetOscEvents.map { ($0.oscEventID, $0) })
        self.songColorsByShowID = snapshot.songColorsByShowID.keyedByInt64()
            .mapValues { $0.keyedByInt64() }
        self.endBehaviorBySetElementID = snapshot.endBehaviorBySetElementID.keyedByInt64()

        // Phase 1 — cache métadonnées : si ShowBuddy.db absente mais cache disponible,
        // reconstituer showBuddyAudioFiles for que la Track Library reste affichable.
        if !snapshot.hasMigratedFromShowBuddy && !snapshot.audioFileMetaCacheByID.isEmpty {
            self.showBuddyAudioFiles = snapshot.audioFileMetaCacheByID
                .compactMap { (key, meta) -> AudioFile? in
                    guard let id = Int64(key) else { return nil }
                    return AudioFile(
                        audioFileID: id,
                        name: meta.name,
                        path: meta.path,
                        note: nil,
                        lengthSecs: meta.lengthSecs,
                        mainAudioFileID: nil
                    )
                }
                .sorted { ($0.name ?? "") < ($1.name ?? "") }
            self.rebuildAudioFileCaches()
        }

        // Après migration : reconstituer les caches MIDI depuis les données Velvet
        // (ShowBuddy.db n'est plus nécessaire).
        if snapshot.hasMigratedFromShowBuddy {
            self.midiEventsByID = Dictionary(
                uniqueKeysWithValues: snapshot.velvetMidiEvents.map { ($0.midiEventID, $0) }
            )
            var byEvent: [Int64: [MidiMessage]] = [:]
            for msg in snapshot.velvetMidiMessages {
                guard let eid = msg.midiEventID else { continue }
                byEvent[eid, default: []].append(msg)
            }
            self.midiMessagesByEventID = byEvent
            self.rebuildAudioFileCaches()
        }

        self.audioEngine.onPlaybackEndished = { [weak self] in
            self?.handlePlaybackEndished()
        }

        // Si AVAudioEngineConfigurationChange interrompt un crossfade, l'engine
        // reprend le song précédent depuis sa position courante. AppState
        // abandonne proprement le remplacement en cours.
        self.audioEngine.onCrossfadeAborted = { [weak self] in
            guard let self else { return }
            self.isReplacingTrack = false
            self.pendingCrossfadeTrack = nil
            self.pendingCrossfadeSetElementID = nil
            self.updateUpcomingTrack()
            print("[XFADE] Aborted (audio reconfiguration): replacement cancelled, previous song resumed")
        }

        if let raw = UserDefaults.standard.string(forKey: Self.seekBehaviorKey),
           let b = SeekBehavior(rawValue: raw) {
            self.seekBehavior = b
        }



        if let stored = UserDefaults.standard.object(forKey: Self.isRehearsalModeKey) as? Bool {
            self.isRehearsalMode = stored
        }

        if let storedOffset = UserDefaults.standard.object(forKey: Self.midiGlobalOffsetKey) as? Int,
           Self.midiGlobalOffsetChoices.contains(storedOffset) {
            self.midiGlobalOffsetMillis = storedOffset
        }

        startDisplayMonitoring()
        // Flush synchrone at la fermeture : sans ça, les debounces (0,4 s
        // store, 2 s mémos) perdent silencieusement les dernières éditions
        // si l'utilisateur quitte juste après avoir tapé.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flushPendingSavesBeforeTermination()
            }
        }
        // Migration douce des cues OSC en format legacy (host/port/address/value
        // inline) vers le nouveau modèle référencé par OscEvent. Crée à la
        // volée les events manquants si l'utilisateur avait placé des cues
        // pendant la V1 inline. No-op si tout est déjà au nouveau format.
        migrateLegacyOscCuesIfNeeded()

        self.isLoadingFromStore = false

        // Résout le bookmark MediaFiles une fois au démarrage for que
        // mediaFolderStatus reflète la réalité. Sans ça, la pastille
        // "MediaFiles: non défini" s'affichait at tort jusqu'à la première
        // lecture (statut initial .notSet jamais rafraîchi).
        _ = resolvedMediaFolderURL()

        // ── Log de démarrage ──────────────────────────────────────────────
        // Résumé de l'état chargé depuis VelvetShowState.json + UserDefaults.
        // Permet de vérifier d'un coup d'œil que tout a bien été restauré.
        let memoCount = snapshot.editableMemosByAudioFileID.values.reduce(0) { $0 + $1.count }
        let trimCount  = snapshot.trimsByAudioFileID.count
        let eventCount = snapshot.velvetMidiEvents.count
        let showCount  = snapshot.velvetShows.count
        let restCueName: String = {
            if let id = self.restCueMidiEventID {
                return self.midiEventsByID[id]?.name.map { "\(id) (\($0))" } ?? "\(id) (inconnu)"
            }
            return "none"
        }()
        let destName: String = {
            if let id = self.maestroDestinationID {
                return self.midiEngine.destination(withID: id)?.displayName ?? "ID \(id) (not connected)"
            }
            return "none"
        }()
        // ── Démo ─────────────────────────────────────────────────────────────
        self.demoManifest = DemoContentStore.shared.manifest

        if store.isFirstLaunch && DemoContentStore.shared.bundleDemoAvailable {
            // Phase 2 : injecter ici le contenu démo depuis DemoVelvetShowState.json.
            // Pour l'instant (Phase 1), DemoVelvetShowState.json est absent — on passe.
            print("[DEMO] First launch detected: DemoVelvetShowState.json not present yet.")
        }

        print("""
        [VELVET] Loaded VelvetShowState — \(store.fileURL.path)
          • \(showCount) show\(showCount > 1 ? "s" : "")
          • \(memoCount) mémo\(memoCount > 1 ? "s" : "")
          • \(eventCount) MIDI event\(eventCount > 1 ? "s" : "")
          • \(trimCount) trim\(trimCount > 1 ? "s" : "") (hasImportedShowBuddyTrims=\(snapshot.hasImportedShowBuddyTrims))
          • restCue = \(restCueName)
          • midiDestination = \(destName)
          • demoInstalled = \(self.demoManifest != nil)
          • isFirstLaunch = \(store.isFirstLaunch)
        """)

        remoteServer.start()
        broadcastState()
        startRemotePositionTimer()

        remoteServer.onCommand = { [weak self] type in
            guard let self else { return }
            switch type {
            case "playPause":
                handlePlayPauseShortcut()
            case "nextTrack":
                guard let setID = currentlyLoadedSetID ?? selectedSetID,
                      let set = sets.first(where: { $0.setID == setID }) else {
                    handleNextSongShortcut()
                    break
                }
                // Priorité 1 : queue (contient le morceau sélectionné via prioritizeNext).
                if let queueItem = concertQueueBySetID[setID]?.first,
                   let track = audioFilesByID[queueItem.audioFileID] {
                    let element = queueItem.setElementID.flatMap { eid in
                        self.songs(in: set).first { $0.element.setElementID == eid }?.element
                    }
                    if let eid = element?.setElementID {
                        selectedShowSetElementIDBySetID[setID] = eid
                    }
                    removeQueueItem(queueItem, from: set)
                    startReplacement(track: track, set: set, element: element, effect: .filter)
                    break
                }
                // Priorité 2 : prochain dans la setlist.
                let setSongs = songs(in: set)
                let anchorID = currentlyLoadedSetID == setID
                    ? currentlyLoadedSetElementID
                    : selectedShowSetElementIDBySetID[setID]
                let startIndex = anchorID.flatMap { id in
                    setSongs.firstIndex { $0.element.setElementID == id }
                } ?? -1
                var idx = startIndex + 1
                while setSongs.indices.contains(idx) {
                    if let audio = setSongs[idx].audio {
                        selectedShowSetElementIDBySetID[setID] = setSongs[idx].element.setElementID
                        startReplacement(track: audio, set: set, element: setSongs[idx].element, effect: .filter)
                        break
                    }
                    idx += 1
                }
            default:
                // "prioritizeNext:<setElementID>" — place le morceau en tête de queue.
                if type.hasPrefix("prioritizeNext:"),
                   let idStr = type.split(separator: ":").last,
                   let elementID = Int64(idStr),
                   let setID = currentlyLoadedSetID,
                   let set = sets.first(where: { $0.setID == setID }),
                   let song = songs(in: set).first(where: { $0.element.setElementID == elementID }) {
                    prioritizeSongNext(song, in: set)
                    updateUpcomingTrack()
                } else {
                    print("[VelvetRemote] Unknown command: \(type)")
                }
            }
        }
    }

    // MARK: - Velvet Remote broadcast

    func buildRemoteState() -> RemoteStateUpdate {
        let memos: [RemoteTimelineMemo] = currentlyLoadedTrack.map { track in
            prompterMemos(for: track).map { memo in
                let title = memo.shortName.isEmpty ? String(memo.memo.prefix(28)) : memo.shortName
                return RemoteTimelineMemo(
                    id: memo.id.uuidString,
                    title: title,
                    startTime: memo.memoTime,
                    duration: max(1, memo.memoLength),
                    hasMidi: memo.hasMidi
                )
            }
        } ?? []

        // Morceau +2 : deux rangs après la position actuelle dans la setlist.
        // Hors contexte show, ou si l'un des rangs n'a pas d'audio : nil.
        let afterNext: String? = {
            guard let setID = currentlyLoadedSetID,
                  let set = sets.first(where: { $0.setID == setID }),
                  let refID = pendingCrossfadeSetElementID ?? currentlyLoadedSetElementID
            else { return nil }
            let all = songs(in: set)
            guard let i0 = all.firstIndex(where: { $0.element.setElementID == refID }) else { return nil }
            let i1 = all.index(after: i0)
            guard i1 < all.endIndex, all[i1].audio != nil else { return nil }
            let i2 = all.index(after: i1)
            guard i2 < all.endIndex else { return nil }
            return all[i2].audio?.name
        }()

        // Setlist à venir : morceaux non encore joués (hors morceau courant),
        // dans l'ordre de la setlist, peu importe leur position relative.
        let upcoming: [RemoteSetlistSong] = {
            guard let setID = currentlyLoadedSetID,
                  let set = sets.first(where: { $0.setID == setID })
            else { return [] }
            let currentElementID = pendingCrossfadeSetElementID ?? currentlyLoadedSetElementID
            let playedElements = playedSetElementIDsBySetID[setID] ?? []
            return songs(in: set).compactMap { song in
                guard let audio = song.audio, let name = audio.name else { return nil }
                guard song.element.setElementID != currentElementID else { return nil }
                guard !playedElements.contains(song.element.setElementID) else { return nil }
                return RemoteSetlistSong(id: String(song.element.setElementID), title: name)
            }
        }()

        return RemoteStateUpdate(
            songTitle:          currentlyLoadedTrack?.name,
            nextSongTitle:      upcomingTrack?.name,
            memoText:           currentMemo()?.memo,
            playbackState:      RemotePlaybackState(audioEngine.state),
            positionSeconds:    audioEngine.effectivePosition,
            durationSeconds:    audioEngine.effectiveDuration,
            timelineMemos:      memos,
            afterNextSongTitle: afterNext,
            upcomingSetlist:    upcoming
        )
    }

    func broadcastState() {
        remoteServer.broadcast(buildRemoteState())
    }

    private func startRemotePositionTimer() {
        remotePositionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Diffuse la position uniquement si quelqu'un est connecté et qu'on joue.
            if self.audioEngine.state == .playing {
                self.broadcastState()
            }
        }
    }

    // MARK: - Seek behavior

    enum SeekBehavior: String, CaseIterable {
        case raw          = "raw"
        case fade         = "fade"
        case fadeSnapBeat = "fadeSnapBeat"

        var label: String {
            switch self {
            case .raw:          return "Brut"
            case .fade:         return "Fondu court"
            case .fadeSnapBeat: return "Fondu + snap au beat"
            }
        }
    }

    private static let seekBehaviorKey = "seekBehavior"

    var seekBehavior: SeekBehavior = .fade {
        didSet {
            UserDefaults.standard.set(seekBehavior.rawValue, forKey: Self.seekBehaviorKey)
        }
    }

    // MARK: - Cue de repos

    /// Master on/off. Si false, aucun cue de repos n'est jamais envoyé.
    var restCueEnabled: Bool = true {
        didSet { UserDefaults.standard.set(restCueEnabled, forKey: "restCueEnabled") }
    }

    /// Protocole utilisé pour le cue de repos. Un seul est actif à la fois —
    /// jamais MIDI + OSC simultanément. Anciens projets : default = .midi
    /// (le seul mode existant historiquement).
    enum RestCueType: String, Codable {
        case midi
        case osc
    }

    var restCueType: RestCueType = .midi {
        didSet { UserDefaults.standard.set(restCueType.rawValue, forKey: "restCueType") }
    }

    /// MidiEvent envoyé comme cue de repos quand restCueType == .midi.
    /// Nil = aucun envoi.
    var restCueMidiEventID: Int64? {
        didSet {
            let d = UserDefaults.standard
            if let id = restCueMidiEventID { d.set(Int(id), forKey: "restCueMidiEventID") }
            else { d.removeObject(forKey: "restCueMidiEventID") }
        }
    }

    /// OscEvent envoyé comme cue de repos quand restCueType == .osc.
    /// Nil = aucun envoi.
    var restOscEventID: UUID? {
        didSet {
            let d = UserDefaults.standard
            if let id = restOscEventID { d.set(id.uuidString, forKey: "restOscEventID") }
            else { d.removeObject(forKey: "restOscEventID") }
        }
    }
    /// Send lors d'un STOP explicite utilisateur.
    var restCueTriggerOnStop: Bool = true {
        didSet { UserDefaults.standard.set(restCueTriggerOnStop, forKey: "restCueTriggerOnStop") }
    }
    /// Send at la fin naturelle d'un song sans enchaînement automatique.
    var restCueTriggerOnNaturalEnd: Bool = true {
        didSet { UserDefaults.standard.set(restCueTriggerOnNaturalEnd, forKey: "restCueTriggerOnNaturalEnd") }
    }
    /// Send en fin de concert (dernier song terminé, pas de suivant).
    var restCueTriggerOnConcertEnd: Bool = true {
        didSet { UserDefaults.standard.set(restCueTriggerOnConcertEnd, forKey: "restCueTriggerOnConcertEnd") }
    }
    /// Send entre deux songs quand AUTO SHOW est désactivé.
    var restCueTriggerBetweenTracks: Bool = false {
        didSet { UserDefaults.standard.set(restCueTriggerBetweenTracks, forKey: "restCueTriggerBetweenTracks") }
    }
    /// Delay avant l'envoi : 0, 1 ou 2 secondes.
    var restCueDelaySeconds: Double = 0 {
        didSet { UserDefaults.standard.set(restCueDelaySeconds, forKey: "restCueDelaySeconds") }
    }

    private static let sendStopCueOnNaturalEndKey = "sendStopCueOnNaturalEnd"

    /// Mode Répétition — quand actif, les songs joués ne passent pas dans
    /// "Joués" et les compteurs/progression du show ne sont pas modifiés.
    /// Tous les more comportements (MIDI, trims, mémos, Stop Cue) restent actifs.
    /// Persisté en UserDefaults — valeur par défaut `false`.
    var isRehearsalMode: Bool = false {
        didSet {
            UserDefaults.standard.set(isRehearsalMode, forKey: Self.isRehearsalModeKey)
            print("[SHOWS] Rehearsal Mode \(isRehearsalMode ? "enabled" : "disabled")")
        }
    }
    private static let isRehearsalModeKey = "isRehearsalMode"

    /// Window de détection des MIDI events de fin (secondes depuis la fin du song).
    static let naturalEndMidiWindowSeconds: Double = 10

    // MARK: - Mode courant

    /// Show Library par défaut : c'est le mode concert, celui que
    /// l'utilisateur veut voir au lancement. La Track Library reste
    /// accessible d'un clic for la préparation / édition des mémos.
    var mode: LibraryMode = .showLibrary

    /// Visibilité de la sidebar Shows (colonne de gauche de la
    /// NavigationSplitView de Show Library). Pilotée par le triangle
    /// "focus concert" et par les raccourcis clavier S / T for ouvrir /
    /// fermer rapidement les colonnes sans toucher la souris.
    var showsSidebarVisibility: NavigationSplitViewVisibility = .all

    /// Visibilité des colonnes Track Library (catégories + songs). En
    /// préparation de mémos, on peut les réduire for garder l'éditeur en
    /// pleine largeur tout en restant dans le même mode.
    var trackLibraryVisibility: NavigationSplitViewVisibility = .all

    /// Vrai quand la fenêtre Queue flottante est affichée at l'écran.
    /// Permet at la fenêtre principale de masquer la carte Queue
    /// embarquée for ne pas dupliquer l'info — soit l'un soit l'autre.
    /// Mise at jour par QueueFloatingView via onAppear / onDisappear.
    var isFloatingQueueVisible: Bool = false

    /// Memoire interne for le toggle "focus concert" : on note l'état
    /// de la Quick Library avant de la cacher, for pouvoir la restaurer
    /// en sortie de focus.
    @ObservationIgnored var quickLibraryWasVisibleBeforeFocus: Bool = true

    /// Toggle de la sidebar Shows (raccourci ⓢ). Ne fait rien si on
    /// n'est pas en Show Library.
    func toggleShowsSidebar() {
        guard mode == .showLibrary else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            showsSidebarVisibility = (showsSidebarVisibility == .detailOnly) ? .all : .detailOnly
        }
    }

    func toggleTrackLibraryColumns() {
        guard mode == .trackLibrary else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            trackLibraryVisibility = (trackLibraryVisibility == .detailOnly) ? .all : .detailOnly
        }
    }

    /// Toggle de la Quick Library (raccourci ⓣ). Ne fait rien si on
    /// n'est pas en Show Library — la Quick Library n'existe que là.
    func toggleQuickLibrary() {
        guard mode == .showLibrary else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            isQuickLibraryVisible.toggle()
        }
    }

    // MARK: - Themes

    /// Theme de la fenetre principale. `.system` laisse macOS decider.
    var appTheme: AppTheme = ThemeManager.defaultAppTheme {
        didSet { persistThemes() }
    }

    /// Theme dedie aux surfaces Prompter, separe du theme de l'app :
    /// un iPad en plein jour n'a pas les memes contraintes que la regie.
    var prompterTheme: PrompterTheme = ThemeManager.defaultPrompterTheme {
        didSet { persistThemes() }
    }

    private static let appThemeKey = "appTheme"
    private static let prompterThemeKey = "prompterTheme"

    private func persistThemes() {
        let defaults = UserDefaults.standard
        defaults.set(appTheme.rawValue, forKey: Self.appThemeKey)
        defaults.set(prompterTheme.rawValue, forKey: Self.prompterThemeKey)
    }

    // MARK: - Base ouverte

    private(set) var database: ShowBuddyDatabase?
    private(set) var stats = LibraryStats()

    // MARK: - Collections principales

    /// Songs ShowBuddy importeds depuis SQLite, conservés séparément des songs Velvet.
    private(set) var showBuddyAudioFiles: [AudioFile] = [] {
        didSet { _audioFilesCache = nil }
    }

    /// Cache invalidé dès que `velvetTracks` ou `showBuddyAudioFiles` changent.
    private var _audioFilesCache: [AudioFile]?

    /// Tous les songs affichables : ShowBuddy + imports Velvet locaux.
    /// Les IDs présents dans velvetTracks ont priorité — évite les doublons
    /// si une migration a été interrompue avant que hasMigratedFromShowBuddy soit posé.
    var audioFiles: [AudioFile] {
        if let cached = _audioFilesCache { return cached }
        let velvetAudioFiles = velvetTracks.map(Self.audioFile(from:))
        let velvetIDs = Set(velvetTracks.map(\.id))
        let filteredShowBuddy = showBuddyAudioFiles.filter { !velvetIDs.contains($0.audioFileID) }
        let result = filteredShowBuddy + velvetAudioFiles
        _audioFilesCache = result
        return result
    }

    /// Sets ShowBuddy importeds depuis SQLite, conservés séparément des Shows Velvet.
    private(set) var showBuddySets: [ShowSet] = []

    /// Tous les sets affichables en Show Library : ShowBuddy + Velvet Shows locaux.
    var sets: [ShowSet] { showBuddySets + velvetShows.map(Self.showSet(from:)) }

    // MARK: - Caches FK directs (lookup O(1) par ID)

    private(set) var audioFilesByID: [Int64: AudioFile] = [:]
    private(set) var lightShowsByID: [Int64: LightShow] = [:]
    private(set) var midiEventsByID: [Int64: MidiEvent] = [:]

    // MARK: - Caches relationnels inversés
    //
    // Ces dictionnaires permettent d'écrire la fiche d'un song sans
    // refaire de requête SQL : un appel direct, on récupère la liste.

    /// Pour un AudioFileID donné, les LightShows qui le référencent
    /// (LightShows.AudioFileID = ce song). Souvent 1 show par song.
    private(set) var lightShowsByAudioFileID: [Int64: [LightShow]] = [:]

    /// Pour un LightShowID donné, les ShowMemos rattachées.
    /// Indirection nécessaire : ShowMemos n'a pas de FK directe vers
    /// AudioFiles — il passe par LightShows.
    private(set) var memosByLightShowID: [Int64: [ShowMemo]] = [:]

    /// Pour un MidiEventID donné, la liste des MidiMessages (déjà triés
    /// par Time côté SQL). Utilisé par la Phase MIDI 0 for afficher et
    /// "simuler" l'envoi d'un événement.
    private(set) var midiMessagesByEventID: [Int64: [MidiMessage]] = [:]

    // MARK: - MIDI Log (Phase MIDI 0 + Phase MIDI 1)
    //
    // Le journal accumule TOUS les déclenchements MIDI passés par
    // l'app — qu'ils soient simulés (Live OFF) ou réellement envoyés
    // via CoreMIDI (Live ON). Le préfixe de chaque ligne distingue
    // explicitement les deux cas :
    //
    //   ENVOI           : Note On channel 16 note 50 ...
    //   ÉCHEC ENVOI     : Note On channel 16 note 50 ...
    //   SANS DESTINATION: Note On channel 16 note 50 ...
    //
    // C'est l'outil de debug central, valable du canapé at la régie.

    private(set) var midiLog: [MidiLogEntry] = []
    /// Nom du dernier MidiEvent dispatché — utilisé par le guide for afficher la bannière cue.
    private(set) var lastDispatchedEventName: String? = nil

    // MARK: - Phase MIDI 1 : moteur CoreMIDI

    /// Moteur CoreMIDI partagé. Créé une seule fois au lancement.
    /// Sa propre liste `destinations` est observable et se met at jour
    /// automatiquement quand un device est branché ou débranché.
    let midiEngine = MIDIEngine()

    /// Moteur OSC partagé (UDP via Network.framework).
    /// Chaque OscEvent référencé par une cue porte son propre host/port.
    let oscEngine = OSCEngine()

    /// Bibliothèque OSC nommée — équivalent OSC de `midiEventsByID`.
    /// Persisté dans `VelvetShowState.velvetOscEvents`.
    private(set) var oscEventsByID: [UUID: OscEvent] = [:]

    /// Identifiant CoreMIDI de la destination choisie for MaestroDMX.
    /// Persisté dans UserDefaults for survivre aux relances.
    /// Résolu en `Destination` at la volée via `midiEngine.destination(withID:)`.
    var maestroDestinationID: MIDIUniqueID? {
        didSet { persistMaestroDestination() }
    }

    private static let maestroDestinationKey = "maestroDestinationID"

    private func persistMaestroDestination() {
        let defaults = UserDefaults.standard
        if let id = maestroDestinationID {
            defaults.set(Int(id), forKey: Self.maestroDestinationKey)
        } else {
            defaults.removeObject(forKey: Self.maestroDestinationKey)
        }
    }

    /// Offset MIDI global en millisecondes (0 ou négatif). −200 = les mémos
    /// MIDI partent 200 ms en avance — compense la latence MaestroDMX /
    /// trame DMX / temps de réponse des projecteurs. N'altère ni les
    /// positions stockées des mémos ni les trims : uniquement la condition
    /// de tir dans tickMidiScheduler.
    var midiGlobalOffsetMillis: Int = 0 {
        didSet {
            UserDefaults.standard.set(midiGlobalOffsetMillis, forKey: Self.midiGlobalOffsetKey)
        }
    }

    static let midiGlobalOffsetChoices = [0, -50, -100, -150, -200, -250, -300]
    private static let midiGlobalOffsetKey = "midiGlobalOffsetMillis"

    private static let stopCueMidiEventIDKey = "stopCueMidiEventID"

    /// La `Destination` actuellement résolue, ou nil si aucune
    /// destination n'est sélectionnée OU si l'ID stocké ne correspond
    /// plus at aucun device présent (interface débranchée par exemple).
    var maestroDestination: MIDIEngine.Destination? {
        guard let id = maestroDestinationID else { return nil }
        return midiEngine.destination(withID: id)
    }

    // MARK: - Dernière scène MaestroDMX envoyée

    /// ID du dernier MidiEvent contenant au moins un message MaestroDMX
    /// réellement envoyé (par mémo auto, stop cue ou envoi manuel).
    /// Utilisé par le panneau d'envoi manuel for surligner la scène active.
    /// État session uniquement — non persisté.
    var lastDispatchedMaestroEventID: MidiEvent.ID? = nil

    // MARK: - Transition Pads — dernier effet utilisé

    /// Dernier effet sélectionné dans le panneau Transition Pads.
    /// Pré-sélectionné at l'ouverture du panneau suivant.
    var lastTransitionEffect: TransitionEffect = {
        if let raw = UserDefaults.standard.string(forKey: "lastTransitionEffect"),
           let effect = TransitionEffect(rawValue: raw) { return effect }
        return .fade
    }() {
        didSet { UserDefaults.standard.set(lastTransitionEffect.rawValue, forKey: "lastTransitionEffect") }
    }

    // MARK: - MaestroDMX — Luminosité globale (CC14, Channel 16)

    /// Dernière valeur envoyée (0-127). Persistée dans UserDefaults.
    /// Non envoyée automatiquement au démarrage — contrôle manuel uniquement.
    var maestroBrightnessValue: Int = UserDefaults.standard.integer(forKey: "maestroBrightnessValue") {
        didSet { UserDefaults.standard.set(maestroBrightnessValue, forKey: "maestroBrightnessValue") }
    }

    /// Envoie CC14 sur Channel 16 at la destination MaestroDMX sélectionnée.
    /// Persiste la valeur même si aucune destination n'est connectée.
    func sendMaestroBrightness(_ value: Int) {
        maestroBrightnessValue = max(0, min(127, value))
        guard let dest = maestroDestination else { return }
        let msg = MidiMessage(
            midiMessageID: -1,
            midiEventID:   nil,
            time:          nil,
            outDevice:     nil,
            channel:       15,     // Channel 16 (0-indexé)
            message:       0xB0,   // Control Change = 176
            data1:         14,     // CC14 = Global Brightness MaestroDMX
            data2:         Int64(maestroBrightnessValue)
        )
        try? midiEngine.send(message: msg, to: dest)
    }

    // MARK: - Phase Audio 0 : moteur audio + dossier des médias
    //
    // Le moteur AVAudioEngine est partagé entre la fenêtre principale
    // et le Prompter — les deux observent `audioEngine.currentPosition`
    // for rester synchros sans avoir at se passer de message.
    //
    // Le sandbox macOS bloque l'accès aux fichiers audio dont les paths
    // sont stockés dans la base ShowBuddy (typiquement
    // ~/Library/Application Support/...). On contourne via un
    // security-scoped bookmark sur le dossier des médias, donné une
    // seule fois par l'utilisateur via NSOpenPanel.

    let audioEngine = AudioEngine()

    /// Morceau actuellement chargé dans le moteur (peut différer de
    /// `selectedAudioFileID` — la sélection est for la navigation, ce
    /// champ est for la lecture en cours).
    var currentlyLoadedTrack: AudioFile?

    /// LightShow utilisé for récupérer trim / volume / mémos lors du
    /// chargement. En général, il n'y en a qu'un seul par song.
    var currentlyLoadedShow: LightShow?

    /// Contexte Show Library du song en cours, si la lecture a été
    /// lancée depuis une setlist. Utilisé for cocher le song joué.
    var currentlyLoadedSetID: ShowSet.ID?
    var currentlyLoadedSetElementID: SetElement.ID?
    /// ID de l'élément préchargé depuis un item de queue en mode .manual (STOP).
    /// Utilisé uniquement for afficher le badge "READY · STOP" dans la setlist.
    /// Mis at nil dès que la lecture démarre sur ce song.
    private(set) var preloadedStopElementID: SetElement.ID? = nil

    /// AUTO SHOW : enchaîne automatiquement les songs de la setlist active
    /// avec une transition FILTER. Non persisté — OFF par défaut at chaque lancement.
    var isAutoShowEnabled: Bool = false
    var selectedShowSetElementIDBySetID: [ShowSet.ID: SetElement.ID] = [:]

    // MARK: - Concert UX : avancement persistant des shows

    private(set) var playedSetElementIDsBySetID: [ShowSet.ID: Set<SetElement.ID>] = [:] {
        didSet { persistPlayedProgress() }
    }

    var selectedConcertGenre: ConcertGenre = .all {
        didSet { persistShowLibraryPreferences() }
    }

    /// Show Safety : exige un double-clic et une confirmation pour
    /// couper le song en cours. Activé par défaut, désactivable depuis
    /// le popover Preferences.
    var isSafePlayEnabled: Bool = true {
        didSet { persistShowLibraryPreferences() }
    }

    /// Track Library rapide visible at gauche du Show. Toggleable depuis
    /// la toolbar ou ⌘B — pratique for récupérer toute la largeur écran
    /// quand la grille des restants prend la priorité.
    var isQuickLibraryVisible: Bool = true {
        didSet { persistShowLibraryPreferences() }
    }

    /// Mode édition du show : drag & drop, suppression et réorganisation
    /// visibles. **Toujours OFF au lancement** — on ne veut JAMAIS qu'un
    /// déplacement accidentel reste possible entre deux ouvertures. Pour
    /// le sortir d'un état accidentel, fermer/rouvrir l'app suffit.
    var isShowEditMode: Bool = false

    /// Ordre personnalisé d'un set ShowBuddy stocké côté Velvet Show.
    /// Les setElementID listés définissent l'ordre ET le contenu visible
    /// du show côté Velvet — un ID absent = song supprimé du show.
    /// Les ajouts live ultérieurs sont automatiquement appended par
    /// `songs(in:)` at la fin for ne jamais être perdus.
    var customOrderBySetID: [ShowSet.ID: [SetElement.ID]] = [:] {
        didSet { persistCustomOrder() }
    }

    /// Overrides utilisateur sur les couleurs de styles. Source de
    /// vérité unique for toute l'app : tout endroit qui affiche un
    /// genre (Track Library, Quick Library, setlist, queue, éditeur,
    /// cartouches, historique) doit appeler `color(for:)` plutôt que de
    /// définir sa propre couleur. Un genre absent retombe sur
    /// `ConcertGenre.defaultColorHex`.
    var genreColors: [ConcertGenre: UInt32] = [:] {
        didSet { persistGenreColors() }
    }

    /// Genres personnalisés créés par l'utilisateur.
    /// Clé = nom du genre (lowercase), valeur = hex 0xRRGGBB.
    var customGenreColors: [String: UInt32] = [:] {
        didSet { store.update { $0.customGenreColors = customGenreColors } }
    }
    var velvetTracks: [VelvetTrack] = [] {
        didSet {
            _audioFilesCache = nil
            rebuildAudioFileCaches()
            persistVelvetTracks()
        }
    }

    var velvetShows: [VelvetShow] = [] {
        didSet { persistVelvetShows() }
    }

    /// Ordre d'affichage manuel des Shows Velvet — tableau d'IDs (Int64 négatifs).
    /// Vide = on utilise l'ordre de `velvetShows` tel quel (ordre de création).
    var velvetShowOrder: [Int64] = [] {
        didSet { persistVelvetShowOrder() }
    }

    /// Shows Velvet dans l'ordre d'affichage souhaité.
    /// Les IDs absents de `velvetShowOrder` sont ajoutés en fin de liste
    /// (robustesse : nouveaux shows créés sans ordre explicite).
    var orderedVelvetShows: [VelvetShow] {
        guard !velvetShowOrder.isEmpty else { return velvetShows }
        let byID = Dictionary(uniqueKeysWithValues: velvetShows.map { ($0.id, $0) })
        var result: [VelvetShow] = velvetShowOrder.compactMap { byID[$0] }
        // Add les shows non encore dans l'ordre (créés depuis la dernière sauvegarde).
        let orderedIDs = Set(velvetShowOrder)
        result += velvetShows.filter { !orderedIDs.contains($0.id) }
        return result
    }

    /// Réordonne les Shows Velvet (appelé depuis le drag-and-drop de la sidebar).
    func moveVelvetShows(fromOffsets: IndexSet, toOffset: Int) {
        var ordered = orderedVelvetShows
        ordered.move(fromOffsets: fromOffsets, toOffset: toOffset)
        velvetShowOrder = ordered.map(\.id)
    }

    var trashedTracks: [TrashedVelvetTrack] = [] {
        didSet { persistTrashedTracks() }
    }

    var liveAdditionsBySetID: [ShowSet.ID: [LiveShowAddition]] = [:] {
        didSet { persistLiveAdditions() }
    }
    var recentlyAddedLiveElementID: SetElement.ID?
    var concertQueueBySetID: [ShowSet.ID: [ConcertQueueItem]] = [:] {
        didSet {
            persistConcertQueue()
            updateUpcomingTrack()
        }
    }
    var concertHistory: [ConcertHistoryEntry] = [] {
        didSet { persistConcertHistory() }
    }
    var activeConcertIDBySetID: [ShowSet.ID: UUID] = [:] {
        didSet { persistActiveConcertIDs() }
    }

    /// Bornes de lecture utilisateur définies dans VELVET SHOW.
    /// Indexées par `audioFileID`. Source de vérité unique consommée par
    /// `effectiveTrim(for:)` et `load(track:)`. Fallback ShowBuddy
    /// (`LightShow.trimStart` / `trimEnd`) si absent.
    var trimsByAudioFileID: [Int64: VelvetTrackTrim] = [:] {
        didSet { persistTrims() }
    }

    /// Volume non destructif par song. Valeur absente = 0 dB.
    /// Appliqué par `load(track:)`, donc valable depuis Track Library,
    /// Show Library, Queue et AutoPlay.
    var volumeByAudioFileID: [Int64: VelvetTrackVolume] = [:] {
        didSet { persistVolumes() }
    }

    /// Color individuelle par song (prioritaire sur la couleur de genre).
    /// Stockée dans VelvetShowStore. Absent = couleur de genre.
    var trackColorsByAudioFileID: [Int64: UInt32] = [:] {
        didSet { persistTrackColors() }
    }

    /// Colors par show — setID → audioFileID → hex.
    /// Prioritaires sur `trackColorsByAudioFileID` dans la Show Library.
    var songColorsByShowID: [Int64: [Int64: UInt32]] = [:] {
        didSet { persistShowSongColors() }
    }

    /// Cue Points placés manuellement dans l'éditeur, indexés par audioFileID.
    var cuePointsByAudioFileID: [Int64: [CuePoint]] = [:] {
        didSet { persistCuePoints() }
    }

    /// Cues MIDI placés directement sur la timeline, indexés par audioFileID.
    var midiCuesByAudioFileID: [Int64: [TimelineMidiCue]] = [:] {
        didSet { persistMidiCues() }
    }

    /// Cues OSC placés directement sur la timeline, indexés par audioFileID.
    /// Cohabite avec les cues MIDI — chaque tick déclenche les deux types
    /// indépendamment via `tickMidiScheduler`.
    var oscCuesByAudioFileID: [Int64: [TimelineOscCue]] = [:] {
        didSet { persistOscCues() }
    }

    /// IDs d'events MIDI masqués des pickers (visibilité uniquement, pas de suppression).
    var archivedMidiEventIDs: Set<Int64> = [] {
        didSet { store.update { $0.archivedMidiEventIDs = Array(self.archivedMidiEventIDs) } }
    }

    // MARK: - Projet démo

    /// Manifest du contenu démo actuellement installé, ou nil si aucun.
    /// Source de vérité réactive for l'UI (section Démo dans les Settings).
    var demoManifest: DemoContentManifest? = nil

    /// Vrai uniquement si `VelvetShowState.json` n'existait pas au démarrage.
    /// Utilisé for afficher l'onboarding au premier lancement.
    var isFirstLaunch: Bool { store.isFirstLaunch }

    /// Crée `VelvetShowState.json` si absent — fait que `isFirstLaunch` sera
    /// false au prochain démarrage. À appeler quelle que soit l'action choisie
    /// dans l'onboarding (Start Tour ou Skip).
    func markFirstLaunchHandled() {
        store.saveNow()
    }

    /// Comportement de fin par setElementID — ShowBuddy shows uniquement.
    /// Pour les Velvet shows, le comportement est dans VelvetShowTrack.endBehavior.
    var endBehaviorBySetElementID: [Int64: TrackEndBehavior] = [:] {
        didSet { persistEndBehaviors() }
    }

    /// Compteur incrémenté uniquement quand un song est ajouté at la file
    /// depuis la colonne Track Library — sert at déclencher l'ouverture auto
    /// de la fenêtre Queue flottante SEULEMENT dans ce cas.
    private(set) var queueAddedFromLibraryTick: Int = 0

    // MARK: - Prompter safety / PANIC

    /// Etat lisible dans la toolbar : utile en concert for savoir si le
    /// Prompter est disponible avant de perdre Sidecar/AirPlay.
    var isSecondDisplayConnected: Bool = NSScreen.screens.count > 1
    var isPrompterActive: Bool = false
    var isPanicPrompterVisible: Bool = false
    @ObservationIgnored private var displayObserver: NSObjectProtocol?

    // Anciennes clés UserDefaults — conservées UNIQUEMENT for la migration
    // initiale to le VelvetShowStore (cf. `migrateLegacyUserDefaultsIfNeeded`).
    fileprivate static let playedProgressKey = "concertPlayedSetElementIDsBySetID"
    fileprivate static let liveAdditionsKey = "liveShowAdditionsBySetID"
    fileprivate static let concertQueueKey = "concertQueueBySetID"
    fileprivate static let concertHistoryKey = "concertHistory"
    fileprivate static let activeConcertIDsKey = "activeConcertIDBySetID"

    /// Fraction des songs introuvables (0..1). Mis at jour au démarrage
    /// et après chaque import/migration. Si > 0,1 l'UI affiche un avertissement.
    private(set) var missingAudioFraction: Double = 0

    /// Vérifie en tâche de fond l'accessibilité d'un échantillon de fichiers audio.
    /// On échantillonne au plus 100 songs for ne pas bloquer le main thread.
    func checkAudioFileAccessibility() {
        let all = audioFiles.filter { $0.path?.isEmpty == false }
        guard !all.isEmpty else { missingAudioFraction = 0; return }
        let sample = all.count <= 100 ? all : (0..<100).map { all[$0 * all.count / 100] }
        Task.detached(priority: .utility) { [weak self] in
            var missing = 0
            for track in sample {
                if await self?.resolvedAudioURL(for: track) == nil { missing += 1 }
            }
            let fraction = Double(missing) / Double(sample.count)
            await MainActor.run { [weak self] in
                self?.missingAudioFraction = fraction
            }
        }
    }

    private func startDisplayMonitoring() {
        isSecondDisplayConnected = NSScreen.screens.count > 1
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPrompterEnvironment()
            }
        }
    }

    func refreshPrompterEnvironment() {
        isSecondDisplayConnected = NSScreen.screens.count > 1
        isPrompterActive = PrompterWindowController.isPrompterVisible
    }

    func setPrompterActive(_ isActive: Bool) {
        isPrompterActive = isActive
    }

    func triggerPrompterPanic() {
        isPanicPrompterVisible.toggle()
        refreshPrompterEnvironment()
    }

    // MARK: - Persistance Velvet Show (via VelvetShowStore)
    //
    // Toutes les fonctions ci-dessous sont des passe-plats simples : elles
    // poussent l'état Swift typé (Int64 keys, Set, etc.) to la forme
    // JSON-friendly (`[String: T]`) attendue par le store.
    //
    // Le store gère lui-même le debouncing : c'est OK d'appeler ces
    // fonctions at chaque didSet, même rapproché.

    private func persistPlayedProgress() {
        guard !isLoadingFromStore else { return }
        let serialised: [String: [Int64]] = Dictionary(
            uniqueKeysWithValues: playedSetElementIDsBySetID.map { (String($0.key), Array($0.value)) }
        )
        store.update { $0.playedSetElementIDsBySetID = serialised }
    }

    private func persistVelvetTracks() {
        guard !isLoadingFromStore else { return }
        let snapshot = velvetTracks
        store.update { $0.velvetTracks = snapshot }
    }

    private func persistVelvetShows() {
        guard !isLoadingFromStore else { return }
        let snapshot = velvetShows
        store.update { $0.velvetShows = snapshot }
    }

    private func persistVelvetShowOrder() {
        guard !isLoadingFromStore else { return }
        let snapshot = velvetShowOrder
        store.update { $0.velvetShowOrder = snapshot }
    }

    private func persistTrashedTracks() {
        guard !isLoadingFromStore else { return }
        let snapshot = trashedTracks
        store.update { $0.trashedTracks = snapshot }
    }

    private func persistLiveAdditions() {
        guard !isLoadingFromStore else { return }
        let serialised = liveAdditionsBySetID.stringKeyed()
        store.update { $0.liveAdditionsBySetID = serialised }
    }

    private func persistConcertQueue() {
        guard !isLoadingFromStore else { return }
        let serialised = concertQueueBySetID.stringKeyed()
        store.update { $0.concertQueueBySetID = serialised }
    }

    private func persistConcertHistory() {
        guard !isLoadingFromStore else { return }
        let snapshot = concertHistory
        store.update { $0.concertHistory = snapshot }
    }

    private func persistActiveConcertIDs() {
        guard !isLoadingFromStore else { return }
        let serialised = activeConcertIDBySetID.stringKeyed()
        store.update { $0.activeConcertIDBySetID = serialised }
    }

    private var memoSaveTask: Task<Void, Never>?

    /// Appelé sur NSApplication.willTerminate : annule le debounce mémos
    /// (2 s), pousse leur snapshot courant dans le store, puis force une
    /// écriture disque synchrone. Garantit zéro perte au ⌘Q.
    func flushPendingSavesBeforeTermination() {
        memoSaveTask?.cancel()
        memoSaveTask = nil
        if !isLoadingFromStore {
            let snapshot = editableMemosByAudioFileID.stringKeyed()
            store.update { $0.editableMemosByAudioFileID = snapshot }
        }
        store.saveNowBlocking()
    }

    private func persistEditableMemos() {
        guard !isLoadingFromStore else { return }
        memoSaveTask?.cancel()
        let snapshot = editableMemosByAudioFileID.stringKeyed()
        memoSaveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            store.update { $0.editableMemosByAudioFileID = snapshot }
        }
    }

    private func persistMemoAttachments() {
        guard !isLoadingFromStore else { return }
        var serialised: [String: [MemoAttachment]] = [:]
        for (memoID, attachments) in memoAttachmentsByMemoID {
            serialised[memoID.uuidString] = attachments
        }
        store.update { $0.memoAttachmentsByMemoID = serialised }
    }

    private func persistCustomOrder() {
        guard !isLoadingFromStore else { return }
        let serialised = customOrderBySetID.stringKeyed()
        store.update { $0.customOrderBySetID = serialised }
    }

    private func persistGenreColors() {
        guard !isLoadingFromStore else { return }
        var serialised: [String: UInt32] = [:]
        for (genre, hex) in genreColors {
            serialised[genre.rawValue] = hex
        }
        store.update { $0.genreColors = serialised }
    }

    private func persistTrims() {
        guard !isLoadingFromStore else { return }
        let serialised = trimsByAudioFileID.stringKeyed()
        store.update { $0.trimsByAudioFileID = serialised }
    }

    private func persistVolumes() {
        guard !isLoadingFromStore else { return }
        let serialised = volumeByAudioFileID.stringKeyed()
        store.update { $0.volumeByAudioFileID = serialised }
    }

    private func persistTrackColors() {
        guard !isLoadingFromStore else { return }
        let serialised = trackColorsByAudioFileID.stringKeyed()
        store.update { $0.trackColorsByAudioFileID = serialised }
    }

    private func persistCuePoints() {
        guard !isLoadingFromStore else { return }
        let serialised = cuePointsByAudioFileID.stringKeyed()
        store.update { $0.cuePointsByAudioFileID = serialised }
    }

    private func persistMidiCues() {
        guard !isLoadingFromStore else { return }
        let serialised = midiCuesByAudioFileID.stringKeyed()
        store.update { $0.midiCuesByAudioFileID = serialised }
    }

    private func persistOscCues() {
        guard !isLoadingFromStore else { return }
        let serialised = oscCuesByAudioFileID.stringKeyed()
        store.update { $0.oscCuesByAudioFileID = serialised }
    }

    private func persistEndBehaviors() {
        guard !isLoadingFromStore else { return }
        store.update { $0.endBehaviorBySetElementID = self.endBehaviorBySetElementID.stringKeyed() }
    }

    private func persistShowSongColors() {
        guard !isLoadingFromStore else { return }
        let serialised = songColorsByShowID.reduce(into: [String: [String: UInt32]]()) { result, pair in
            let innerSerialized = pair.value.reduce(into: [String: UInt32]()) { r, p in r[String(p.key)] = p.value }
            result[String(pair.key)] = innerSerialized
        }
        store.update { $0.songColorsByShowID = serialised }
    }

    // MARK: - Cue Points CRUD

    func cuePoints(for track: AudioFile) -> [CuePoint] {
        (cuePointsByAudioFileID[track.audioFileID] ?? [])
            .sorted { $0.time < $1.time }
    }

    func saveCuePoints(_ points: [CuePoint], for track: AudioFile) {
        cuePointsByAudioFileID[track.audioFileID] = points
    }

    func addCuePoint(at time: Double, for track: AudioFile) {
        let existing = cuePointsByAudioFileID[track.audioFileID] ?? []
        let index = existing.count + 1
        let cue = CuePoint(name: "Cue \(index)", time: time)
        cuePointsByAudioFileID[track.audioFileID, default: []].append(cue)
    }

    func updateCuePoint(_ cuePoint: CuePoint, for track: AudioFile) {
        guard var list = cuePointsByAudioFileID[track.audioFileID],
              let i = list.firstIndex(where: { $0.id == cuePoint.id }) else { return }
        list[i] = cuePoint
        cuePointsByAudioFileID[track.audioFileID] = list
    }

    func deleteCuePoint(_ cuePoint: CuePoint, for track: AudioFile) {
        cuePointsByAudioFileID[track.audioFileID]?.removeAll { $0.id == cuePoint.id }
    }

    // MARK: - Cues MIDI timeline

    func midiCues(for track: AudioFile) -> [TimelineMidiCue] {
        (midiCuesByAudioFileID[track.audioFileID] ?? [])
            .sorted { $0.time < $1.time }
    }

    func saveMidiCues(_ cues: [TimelineMidiCue], for track: AudioFile) {
        midiCuesByAudioFileID[track.audioFileID] = cues
    }

    func addMidiCue(_ cue: TimelineMidiCue, for track: AudioFile) {
        midiCuesByAudioFileID[track.audioFileID, default: []].append(cue)
    }

    func deleteMidiCue(_ cue: TimelineMidiCue, for track: AudioFile) {
        midiCuesByAudioFileID[track.audioFileID]?.removeAll { $0.id == cue.id }
    }

    // MARK: - Cues OSC timeline

    func oscCues(for track: AudioFile) -> [TimelineOscCue] {
        (oscCuesByAudioFileID[track.audioFileID] ?? [])
            .sorted { $0.time < $1.time }
    }

    func saveOscCues(_ cues: [TimelineOscCue], for track: AudioFile) {
        oscCuesByAudioFileID[track.audioFileID] = cues
    }

    func addOscCue(_ cue: TimelineOscCue, for track: AudioFile) {
        oscCuesByAudioFileID[track.audioFileID, default: []].append(cue)
    }

    func deleteOscCue(_ cue: TimelineOscCue, for track: AudioFile) {
        oscCuesByAudioFileID[track.audioFileID]?.removeAll { $0.id == cue.id }
    }

    // MARK: - Velvet OSC Library (CRUD + persistance)

    /// Liste triée par nom des OscEvents nommés — utilisée par les pickers
    /// et la section Settings.
    var sortedOscEvents: [OscEvent] {
        oscEventsByID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Crée un OscEvent nommé. Retourne l'event créé pour pouvoir le lier
    /// immédiatement à une cue.
    @discardableResult
    func createOscEvent(
        name: String,
        category: String? = nil,
        host: String = "127.0.0.1",
        port: Int = 8000,
        address: String = "/cue/scene/1",
        value: OSCValue? = nil
    ) -> OscEvent {
        let event = OscEvent(
            name: name.isEmpty ? "New OSC Event" : name,
            category: category,
            host: host,
            port: port,
            address: address,
            value: value
        )
        oscEventsByID[event.oscEventID] = event
        persistVelvetOscEvents()
        return event
    }

    func updateOscEvent(_ event: OscEvent) {
        oscEventsByID[event.oscEventID] = event
        persistVelvetOscEvents()
    }

    func deleteOscEvent(_ event: OscEvent) {
        oscEventsByID.removeValue(forKey: event.oscEventID)
        // Les cues qui pointaient sur cet event ne sont pas supprimées :
        // leur `oscEventID` reste, mais le dispatch les ignorera proprement
        // (logué « event introuvable »). L'utilisateur peut les ré-éditer.
        persistVelvetOscEvents()
    }

    /// Recherche un OscEvent qui matche EXACTEMENT (address, value, category).
    /// Utilisé par les flux d'import pour la déduplication. Le host/port
    /// n'entre PAS dans le critère — un changement d'IP MaestroDMX ne doit
    /// pas re-créer la même cue.
    func findOscEvent(
        matchingAddress address: String,
        value: OSCValue?,
        category: String?
    ) -> OscEvent? {
        oscEventsByID.values.first { e in
            e.address == address
                && e.value == value
                && (e.category ?? "") == (category ?? "")
        }
    }

    /// Usage d'un OscEvent dans la timeline — utilisé par la Settings UI.
    func oscEventUsage(for eventID: UUID) -> Int {
        var n = 0
        for cues in oscCuesByAudioFileID.values {
            n += cues.lazy.filter { $0.oscEventID == eventID }.count
        }
        return n
    }

    private func persistVelvetOscEvents() {
        guard !isLoadingFromStore else { return }
        let all = sortedOscEvents
        store.update { $0.velvetOscEvents = all }
    }

    /// Migration des anciennes cues OSC (champs host/port/address/value inline)
    /// vers le nouveau modèle référencé. Pour chaque cue legacy :
    ///   1) cherche un OscEvent existant qui matche EXACTEMENT host/port/address/value ;
    ///   2) sinon en crée un nouveau, nommé d'après le label de la cue ou
    ///      l'adresse OSC si le label est vide ;
    ///   3) remplace `oscEventID` sur la cue et efface `legacyInline`.
    /// Idempotente — si aucun cue legacy n'est trouvé, ne fait rien.
    private func migrateLegacyOscCuesIfNeeded() {
        var migratedAnything = false
        for (audioFileID, cues) in oscCuesByAudioFileID {
            var updated = cues
            var changedThisTrack = false
            for i in updated.indices {
                guard updated[i].oscEventID == nil, let legacy = updated[i].legacyInline else { continue }
                let match = oscEventsByID.values.first {
                    $0.host == legacy.host
                        && $0.port == legacy.port
                        && $0.address == legacy.address
                        && $0.value == legacy.value
                }
                let event: OscEvent
                if let existing = match {
                    event = existing
                } else {
                    let baseName = updated[i].label.isEmpty ? legacy.address : updated[i].label
                    event = OscEvent(
                        name: baseName,
                        category: "Imported",
                        host: legacy.host,
                        port: legacy.port,
                        address: legacy.address,
                        value: legacy.value
                    )
                    oscEventsByID[event.oscEventID] = event
                    print("[OSC] migration: created OscEvent \"\(event.name)\" from legacy inline cue")
                }
                updated[i].oscEventID   = event.oscEventID
                updated[i].legacyInline = nil
                changedThisTrack = true
                migratedAnything = true
            }
            if changedThisTrack {
                oscCuesByAudioFileID[audioFileID] = updated
            }
        }
        if migratedAnything {
            // On force la persistance même pendant isLoadingFromStore — sinon
            // la migration ne serait jamais réécrite sur disque.
            let events = sortedOscEvents
            let cues   = oscCuesByAudioFileID.stringKeyed()
            store.update {
                $0.velvetOscEvents = events
                $0.oscCuesByAudioFileID = cues
            }
            print("[OSC] migration complete — \(oscEventsByID.count) named event(s) total")
        }
    }

    /// Restaure la map typée `[ConcertGenre: UInt32]` depuis sa forme JSON.
    fileprivate static func genreColors(from raw: [String: UInt32]) -> [ConcertGenre: UInt32] {
        var result: [ConcertGenre: UInt32] = [:]
        for (key, value) in raw {
            if let genre = ConcertGenre(rawValue: key) {
                result[genre] = value
            }
        }
        return result
    }

    private func persistShowLibraryPreferences() {
        guard !isLoadingFromStore else { return }
        let genre = selectedConcertGenre.rawValue
        let safePlay = isSafePlayEnabled
        let quickLib = isQuickLibraryVisible
        store.update {
            $0.selectedConcertGenreRaw = genre
            $0.isSafePlayEnabled = safePlay
            $0.isQuickLibraryVisible = quickLib
        }
    }

    // MARK: - Helpers de chargement / migration

    /// Convertit `[String: [MemoAttachment]]` (clé sérialisée) en
    /// `[UUID: [MemoAttachment]]` (clé typée).
    fileprivate static func attachmentsByUUID(
        from raw: [String: [MemoAttachment]]
    ) -> [UUID: [MemoAttachment]] {
        var result: [UUID: [MemoAttachment]] = [:]
        for (rawID, attachments) in raw {
            if let id = UUID(uuidString: rawID) {
                result[id] = attachments
            }
        }
        return result
    }

    /// Convertit la forme stockée `[String: [Int64]]` (JSON-friendly) en
    /// `[Int64: Set<Int64>]` (forme native for les tests d'appartenance).
    fileprivate static func playedSet(
        from raw: [String: [Int64]]
    ) -> [ShowSet.ID: Set<SetElement.ID>] {
        var result: [ShowSet.ID: Set<SetElement.ID>] = [:]
        for (key, values) in raw {
            if let setID = Int64(key) {
                result[setID] = Set(values)
            }
        }
        return result
    }

    /// Migration ponctuelle des anciennes données UserDefaults to le
    /// store. Une seule fois, at la première ouverture après mise at jour
    /// (détectée par l'absence de fichier `VelvetShowState.json` ET la
    /// présence d'au moins une clé UserDefaults connue). Les clés sont
    /// ensuite supprimées d'UserDefaults for éviter une seconde lecture.
    fileprivate static func migrateLegacyUserDefaultsIfNeeded(into store: VelvetShowStore) {
        // Si le fichier existe déjà, c'est qu'on a déjà migré.
        if FileManager.default.fileExists(atPath: store.fileURL.path) { return }

        let defaults = UserDefaults.standard
        var hasLegacy = false
        var migrated = VelvetShowState()

        if let raw = defaults.dictionary(forKey: playedProgressKey) as? [String: [Int64]] {
            migrated.playedSetElementIDsBySetID = raw
            hasLegacy = true
        }
        if let data = defaults.data(forKey: liveAdditionsKey),
           let decoded = try? JSONDecoder().decode([Int64: [LiveShowAddition]].self, from: data) {
            migrated.liveAdditionsBySetID = decoded.stringKeyed()
            hasLegacy = true
        }
        if let data = defaults.data(forKey: concertQueueKey),
           let decoded = try? JSONDecoder().decode([Int64: [ConcertQueueItem]].self, from: data) {
            migrated.concertQueueBySetID = decoded.stringKeyed()
            hasLegacy = true
        }
        if let data = defaults.data(forKey: concertHistoryKey),
           let decoded = try? JSONDecoder().decode([ConcertHistoryEntry].self, from: data) {
            migrated.concertHistory = decoded
            hasLegacy = true
        }
        if let data = defaults.data(forKey: activeConcertIDsKey),
           let decoded = try? JSONDecoder().decode([Int64: UUID].self, from: data) {
            migrated.activeConcertIDBySetID = decoded.stringKeyed()
            hasLegacy = true
        }

        guard hasLegacy else { return }

        store.update { $0 = migrated }
        store.saveNow()

        for key in [
            playedProgressKey, liveAdditionsKey, concertQueueKey,
            concertHistoryKey, activeConcertIDsKey
        ] {
            defaults.removeObject(forKey: key)
        }
    }

    func playedCount(in set: ShowSet, songs: [Song]) -> Int {
        songs.filter { isPlayed($0, in: set) }.count
    }

    func isPlayed(_ song: Song, in set: ShowSet) -> Bool {
        playedSetElementIDsBySetID[set.setID]?.contains(song.element.setElementID) == true
    }

    func markPlayed(_ song: Song, in set: ShowSet) {
        // En Mode Répétition, les songs ne passent jamais dans "Joués".
        guard !isRehearsalMode else { return }
        playedSetElementIDsBySetID[set.setID, default: []].insert(song.element.setElementID)
    }

    func resetProgress(for set: ShowSet) {
        playedSetElementIDsBySetID[set.setID] = []
        activeConcertIDBySetID[set.setID] = nil
        concertQueueBySetID[set.setID] = []
        if currentlyLoadedSetID == set.setID {
            preloadedStopElementID = nil
        }
    }

    /// Réinitialise l'état concert de **tous** les shows :
    ///   - songs joués → remis en "restants"
    ///   - files "À suivre" → vidées
    ///
    /// Crée un backup `.resetall.bak` avant toute modification.
    /// Les shows, songs, mémos, MIDI events, trims et réglages sont conservés.
    func resetAllShows() {
        // Backup préventif (copie de VelvetShowState.json → .resetall.bak)
        let jsonURL    = store.fileURL
        let bakURL     = jsonURL.deletingPathExtension().appendingPathExtension("resetall.bak")
        try? FileManager.default.removeItem(at: bakURL)
        try? FileManager.default.copyItem(at: jsonURL, to: bakURL)

        playedSetElementIDsBySetID = [:]
        activeConcertIDBySetID     = [:]
        concertQueueBySetID        = [:]
        store.saveNow()

        print("[SHOWS] All shows reset")
    }

    func selectShowSong(_ song: Song, in set: ShowSet) {
        selectedShowSetElementIDBySetID[set.setID] = song.element.setElementID
    }

    func addTrackToCurrentShow(_ track: AudioFile) {
        guard let setID = selectedSetID,
              let set = sets.first(where: { $0.setID == setID }) else {
            lastError = "Select a show before adding a live song."
            return
        }
        addTrack(track, to: set)
    }

    func queueTrackToPlayNext(_ track: AudioFile) {
        guard let setID = selectedSetID,
              let set = sets.first(where: { $0.setID == setID }) else {
            lastError = "Select a show before preparing the queue."
            return
        }
        queueTrack(track, in: set, atFront: true)
    }

    func enqueueTrack(_ track: AudioFile) {
        guard let setID = selectedSetID,
              let set = sets.first(where: { $0.setID == setID }) else {
            lastError = "Select a show before preparing the queue."
            return
        }
        queueTrack(track, in: set, atFront: false)
    }

    func queueTrack(_ track: AudioFile, in set: ShowSet, atFront: Bool) {
        let item = ConcertQueueItem(setID: set.setID, audioFileID: track.audioFileID)
        insertQueueItem(item, in: set, atFront: atFront)
        queueAddedFromLibraryTick += 1
    }

    func queueSong(_ song: Song, in set: ShowSet, atFront: Bool) {
        guard let track = song.audio else { return }
        let item = ConcertQueueItem(
            setID: set.setID,
            setElementID: song.element.setElementID,
            audioFileID: track.audioFileID
        )
        insertQueueItem(item, in: set, atFront: atFront)
    }

    func prioritizeSongNext(_ song: Song, in set: ShowSet) {
        guard let track = song.audio else { return }
        var queue = concertQueueBySetID[set.setID] ?? []
        queue.removeAll { item in
            item.setElementID == song.element.setElementID || item.audioFileID == track.audioFileID
        }
        let item = ConcertQueueItem(
            setID: set.setID,
            setElementID: song.element.setElementID,
            audioFileID: track.audioFileID,
            playbackMode: .automatic
        )
        queue.insert(item, at: 0)
        concertQueueBySetID[set.setID] = queue
    }

    private func insertQueueItem(_ item: ConcertQueueItem, in set: ShowSet, atFront: Bool) {
        if atFront {
            concertQueueBySetID[set.setID, default: []].insert(item, at: 0)
        } else {
            concertQueueBySetID[set.setID, default: []].append(item)
        }
    }

    func queueItems(for set: ShowSet) -> [ConcertQueueItem] {
        concertQueueBySetID[set.setID] ?? []
    }

    func setQueuePlaybackMode(_ mode: QueuePlaybackMode, for item: ConcertQueueItem, in set: ShowSet) {
        guard var queue = concertQueueBySetID[set.setID],
              let index = queue.firstIndex(where: { $0.id == item.id }) else { return }
        queue[index].playbackMode = mode
        concertQueueBySetID[set.setID] = queue
    }

    func removeQueueItem(_ item: ConcertQueueItem, from set: ShowSet) {
        concertQueueBySetID[set.setID]?.removeAll { $0.id == item.id }
    }

    func queuePlaybackContext(
        for item: ConcertQueueItem,
        in set: ShowSet
    ) -> (track: AudioFile, element: SetElement?)? {
        guard let track = audioFilesByID[item.audioFileID] else { return nil }
        let element = item.setElementID.flatMap { elementID in
            songs(in: set).first { $0.element.setElementID == elementID }?.element
        }
        return (track, element)
    }

    func playQueueItem(_ item: ConcertQueueItem, in set: ShowSet) {
        guard let context = queuePlaybackContext(for: item, in: set) else { return }
        removeQueueItem(item, from: set)
        startPlayback(track: context.track, set: set, element: context.element)
    }

    func addTrack(_ track: AudioFile, to set: ShowSet) {
        if let index = velvetShows.firstIndex(where: { $0.id == set.setID }) {
            velvetShows[index].tracks.append(VelvetShowTrack(
                id: nextVelvetTrackID(),
                audioFileID: track.audioFileID
            ))
            return
        }

        let anchor: SetElement.ID?
        if currentlyLoadedSetID == set.setID, let current = currentlyLoadedSetElementID {
            anchor = current
        } else {
            anchor = selectedShowSetElementIDBySetID[set.setID]
        }

        let existing = liveAdditionsBySetID[set.setID] ?? []
        let nextID = min(-1, (existing.map(\.id).min() ?? 0) - 1)
        let addition = LiveShowAddition(
            id: nextID,
            setID: set.setID,
            audioFileID: track.audioFileID,
            anchorSetElementID: anchor,
            createdAt: Date()
        )
        liveAdditionsBySetID[set.setID, default: []].append(addition)
        recentlyAddedLiveElementID = nextID

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.recentlyAddedLiveElementID == nextID {
                self?.recentlyAddedLiveElementID = nil
            }
        }
    }

    private func markCurrentShowSongPlayed() {
        guard let setID = currentlyLoadedSetID,
              let elementID = currentlyLoadedSetElementID else { return }
        markShowSongPlayed(setID: setID, elementID: elementID)
    }

    private func markShowSongPlayed(setID: ShowSet.ID, elementID: SetElement.ID) {
        guard let set = sets.first(where: { $0.setID == setID }),
              let song = songs(in: set).first(where: { $0.element.setElementID == elementID }) else { return }
        markPlayed(song, in: set)
    }

    /// Vérifie si un MIDI event (start ou end de mémo) a été déclenché dans
    /// les `seconds` final seconds du song chargé.
    /// Utilisé for décider si le Stop Cue automatique doit être envoyé.
    private func hasRecentMidiTrigger(for track: AudioFile, withinLastSeconds seconds: Double) -> Bool {
        let trackEnd   = audioEngine.effectiveEnd          // position absolue de fin (trimEnd ou durée totale)
        let threshold  = max(0, trackEnd - seconds)
        let memos      = editableMemos(for: track)

        for memo in memos {
            // Trigger END : déclenché at memoTime + memoLength
            if memo.endMidiEventID != nil {
                let endTime = memo.memoTime + memo.memoLength
                if endTime >= threshold && firedMidiTriggers.contains("\(memo.id)-end") {
                    return true
                }
            }
            // Trigger START : déclenché at memoTime
            if memo.startMidiEventID != nil {
                if memo.memoTime >= threshold && firedMidiTriggers.contains("\(memo.id)-start") {
                    return true
                }
            }
        }
        return false
    }

    enum RestCueTrigger { case stop, naturalEnd, concertEnd, betweenTracks }

    /// Envoie le cue de repos si les conditions sont réunies for le déclencheur donné.
    /// Respecte le délai configuré. N'envoie jamais pendant un crossfade ou si AUTO SHOW
    /// va enchaîner un song suivant. Le type de cue (MIDI ou OSC) est exclusif —
    /// un seul protocole part au STOP, jamais les deux.
    private func sendRestCueIfNeeded(trigger: RestCueTrigger) {
        guard restCueEnabled else { return }

        // Vérifier le toggle correspondant au déclencheur — partagé MIDI/OSC.
        switch trigger {
        case .stop:          guard restCueTriggerOnStop         else { return }
        case .naturalEnd:    guard restCueTriggerOnNaturalEnd   else { return }
        case .concertEnd:    guard restCueTriggerOnConcertEnd   else { return }
        case .betweenTracks: guard restCueTriggerBetweenTracks  else { return }
        }

        // Ne jamais envoyer pendant un crossfade ou si AUTO SHOW va lancer le suivant.
        if trigger != .stop {
            guard !isReplacingTrack else { return }
            if isAutoShowEnabled, nextNaturalSongElementID != nil { return }
        }

        // Pour les fins naturelles : ignorer si un mémo MIDI de fin a déjà été envoyé.
        // Ce check reste basé sur l'activité MIDI car c'est elle qui peut tenir le
        // contrôle des lumières en fin de morceau — indépendant du type de rest cue.
        if trigger == .naturalEnd || trigger == .concertEnd || trigger == .betweenTracks {
            if let track = currentlyLoadedTrack {
                let window = Self.naturalEndMidiWindowSeconds
                if hasRecentMidiTrigger(for: track, withinLastSeconds: window) {
                    midiLog.append(MidiLogEntry(timestamp: Date(),
                        text: "Rest cue (\(trigger)) · skipped, recent end memo"))
                    return
                }
            }
        }

        // Branche exclusive selon le type sélectionné.
        switch restCueType {
        case .midi:
            guard let eventID = restCueMidiEventID,
                  let event   = midiEventsByID[eventID] else { return }
            let name = event.name ?? "MidiEvent \(eventID)"
            scheduleRestCueDispatch(trigger: trigger, label: "MIDI · \(name)") { [weak self] in
                self?.dispatch(event: event)
            }
        case .osc:
            guard let eventID = restOscEventID,
                  let event   = oscEventsByID[eventID] else { return }
            scheduleRestCueDispatch(trigger: trigger, label: "OSC · \(event.name)") { [weak self] in
                self?.dispatch(oscEvent: event)
            }
        }
    }

    /// Encapsule la logique de délai + re-check des conditions après attente,
    /// partagée entre les deux branches MIDI/OSC.
    private func scheduleRestCueDispatch(
        trigger: RestCueTrigger,
        label: String,
        perform: @escaping () -> Void
    ) {
        let delay = restCueDelaySeconds
        if delay > 0 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard let self else { return }
                // Re-vérifier après le délai : un song a pu démarrer entretemps.
                if trigger != .stop {
                    guard !self.isReplacingTrack else { return }
                    if self.isAutoShowEnabled, self.nextNaturalSongElementID != nil { return }
                }
                self.midiLog.append(MidiLogEntry(timestamp: Date(),
                    text: "Rest cue (\(trigger)) · \(label) (delay \(Int(delay))s)"))
                perform()
            }
        } else {
            midiLog.append(MidiLogEntry(timestamp: Date(),
                text: "Rest cue (\(trigger)) · \(label)"))
            perform()
        }
    }

    private func handlePlaybackEndished() {
        midiSchedulerTask?.cancel()
        midiSchedulerTask = nil
        guard !isStartingQueuedPlayback else { return }
        // Éditeur ouvert : ne pas marquer le song joué, ne pas lancer
        // le suivant depuis la queue. L'arrêt vient de l'édition, pas de
        // la fin naturelle d'un concert.
        guard !isInEditingMode else { return }
        // Remplacement manuel en cours : le segment peut se terminer
        // naturellement pendant le fade-out. On ne doit pas déclencher
        // la Queue Auto — `startReplacement` gère la suite lui-même.
        guard !isReplacingTrack else { return }

        let finishedSetID = currentlyLoadedSetID
        let finishedElementID = currentlyLoadedSetElementID
        if let finishedSetID, let finishedElementID {
            markShowSongPlayed(setID: finishedSetID, elementID: finishedElementID)
        }
        // Résolution du set for la queue :
        // 1. Set du song qui vient de terminer (cas normal Show Library).
        // 2. Fallback sur le set sélectionné si :
        //    – pas de contexte set (lancé depuis Track Library, finishedSetID nil), ou
        //    – la queue du set terminé est vide mais l'utilisateur a cliqué
        //      "À suivre" dans un autre show après avoir navigué.
        let queueSetID: ShowSet.ID?
        if let id = finishedSetID, !(concertQueueBySetID[id]?.isEmpty ?? true) {
            queueSetID = id
        } else {
            queueSetID = selectedSetID
        }
        // ── Résolution du set actif ──────────────────────────────────────────
        // On a besoin du set for chercher dans la Queue ET dans la setlist.
        // Si finishedSetID n'a pas de queue et que selectedSetID est différent,
        // le fallback sur selectedSetID s'applique uniquement for la Queue
        // (comportement d'origine). Pour le préchargement setlist on préfère
        // le set du song qui vient de terminer.
        let activeSet: ShowSet? = {
            if let id = finishedSetID, let s = sets.first(where: { $0.setID == id }) { return s }
            if let id = selectedSetID, let s = sets.first(where: { $0.setID == id }) { return s }
            return nil
        }()

        // ── Queue .automatic : comportement d'origine inchangé ───────────────
        if let setID = queueSetID,
           let set = sets.first(where: { $0.setID == setID }),
           let nextItem = concertQueueBySetID[setID]?.first,
           nextItem.playbackMode == .automatic,
           let track = audioFilesByID[nextItem.audioFileID] {
            let element = nextItem.setElementID.flatMap { eid in
                songs(in: set).first { $0.element.setElementID == eid }?.element
            }
            removeQueueItem(nextItem, from: set)
            isStartingQueuedPlayback = true
            // 60 ms : laisse CoreAudio flusher son buffer après stopImmediately
            // avant d'enchaîner load → scheduleSegment → play.
            // Stockée dans replacementTask for que requestStop() puisse
            // l'annuler — sinon Stop pressé dans cette fenêtre n'empêche
            // pas le song suivant de démarrer.
            replacementTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(60)) } catch {
                    self?.isStartingQueuedPlayback = false
                    return
                }
                guard let self else { return }
                self.startPlayback(track: track, set: set, element: element)
                try? await Task.sleep(for: .milliseconds(300))
                self.isStartingQueuedPlayback = false
            }
            return
        }

        // ── AUTO SHOW fallback : song terminé avant que tickAutoNext ait
        //    pu lancer le crossfade (durée très courte, activation tardive...).
        //    Le nœud est déjà arrêté → startPlayback propre après 60 ms.
        if isAutoShowEnabled,
           let set = activeSet, let finishedElementID,
           let next = nextSong(after: finishedElementID, in: set),
           let nextTrack = next.audio {
            isStartingQueuedPlayback = true
            // Stockée dans replacementTask — annulable par requestStop().
            replacementTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(60)) } catch {
                    self?.isStartingQueuedPlayback = false
                    return
                }
                guard let self else { return }
                self.startPlayback(track: nextTrack, set: set, element: next.element)
                try? await Task.sleep(for: .milliseconds(300))
                self.isStartingQueuedPlayback = false
            }
            return
        }

        // ── Queue .manual : précharger le song de la Queue ───────────────
        if let setID = queueSetID,
           let set = sets.first(where: { $0.setID == setID }),
           let nextItem = concertQueueBySetID[setID]?.first,
           let track = audioFilesByID[nextItem.audioFileID] {
            let element = nextItem.setElementID.flatMap { eid in
                songs(in: set).first { $0.element.setElementID == eid }?.element
            }
            removeQueueItem(nextItem, from: set)
            load(track: track)
            currentlyLoadedSetID = set.setID
            currentlyLoadedSetElementID = element?.setElementID
            preloadedPlaybackContext = (set, element)
            preloadedStopElementID = element?.setElementID
            // Entre deux songs, AUTO SHOW off : cue de repos si demandé.
            sendRestCueIfNeeded(trigger: .betweenTracks)
            return
        }

        // ── Pas de Queue : précharger le suivant de la setlist ───────────────
        guard let set = activeSet, let finishedElementID else {
            // Aucun contexte set — fin naturelle sans enchaînement possible.
            sendRestCueIfNeeded(trigger: .naturalEnd)
            return
        }
        guard let next = nextSong(after: finishedElementID, in: set),
              let track = next.audio else {
            // Dernier song du concert, pas de suivant.
            sendRestCueIfNeeded(trigger: .concertEnd)
            return
        }
        // Il y a un suivant mais AUTO SHOW est off : entre deux songs.
        sendRestCueIfNeeded(trigger: .betweenTracks)
        load(track: track)
        currentlyLoadedSetID = set.setID
        currentlyLoadedSetElementID = next.element.setElementID
        preloadedPlaybackContext = (set, next.element)
    }

    private func updateNextNaturalIndicator() {
        guard let setID = currentlyLoadedSetID,
              let elementID = currentlyLoadedSetElementID,
              let set = sets.first(where: { $0.setID == setID }) else {
            nextNaturalSongElementID = nil
            updateUpcomingTrack()
            return
        }
        nextNaturalSongElementID = nextSong(after: elementID, in: set)?.element.setElementID
        updateUpcomingTrack()
    }

    // MARK: - Morceau suivant réel (affichage prompteur)

    /// Le song qui sera RÉELLEMENT joué ensuite, toutes sources confondues.
    /// Priorité identique at la logique de lecture (tickAutoNext /
    /// handlePlaybackEndished) : tête de queue d'abord, prochain naturel
    /// de la setlist ensuite. nil en fin de setlist sans queue.
    ///
    /// Stocké (pas computed) for éviter le recalcul at 30 Hz par le body du
    /// prompteur : mis at jour uniquement sur changement de song, de queue
    /// ou de crossfade via updateUpcomingTrack().
    private(set) var upcomingTrack: AudioFile?

    /// Élément de destination du crossfade en cours. Pendant le fade,
    /// currentlyLoadedSetElementID pointe encore l'ancien song — le
    /// "suivant" doit être calculé depuis le song ENTRANT.
    @ObservationIgnored private var pendingCrossfadeSetElementID: Int64?

    private func updateUpcomingTrack() {
        upcomingTrack = computeUpcomingTrack()
        broadcastState()
    }

    private func computeUpcomingTrack() -> AudioFile? {
        guard let setID = currentlyLoadedSetID,
              let set = sets.first(where: { $0.setID == setID }) else { return nil }
        // 1. La queue est prioritaire (mode auto ou manuel : c'est le
        //    song armé, "Jouer juste après" inclus).
        if let first = concertQueueBySetID[setID]?.first,
           let track = audioFilesByID[first.audioFileID] {
            return track
        }
        // 2. Prochain naturel — depuis le song entrant si un crossfade
        //    est en cours, sinon depuis le song chargé.
        guard let refElementID = pendingCrossfadeSetElementID ?? currentlyLoadedSetElementID else {
            return nil
        }
        return nextSong(after: refElementID, in: set)?.audio
    }


    private func recordHistory(song: Song, in set: ShowSet) {
        guard let track = song.audio else { return }
        let genre = concertGenre(for: song).label
        recordHistory(track: track, genre: genre, in: set)
    }

    private func recordHistory(track: AudioFile, in set: ShowSet) {
        let genre = concertGenre(for: Song(
            element: SetElement(
                setElementID: -1,
                setID: set.setID,
                lightShowID: -1,
                playOrder: nil,
                note: nil,
                autoStart: nil,
                loop: nil,
                colour: nil
            ),
            show: nil,
            audio: track
        )).label
        recordHistory(track: track, genre: genre, in: set)
    }

    private func recordHistory(track: AudioFile, genre: String, in set: ShowSet) {
        let concertID = activeConcertIDBySetID[set.setID] ?? UUID()
        if activeConcertIDBySetID[set.setID] == nil {
            activeConcertIDBySetID[set.setID] = concertID
        }

        if let index = concertHistory.firstIndex(where: { $0.id == concertID }) {
            let position = concertHistory[index].playedTracks.count + 1
            concertHistory[index].playedTracks.append(ConcertPlayedTrack(
                audioFileID: track.audioFileID,
                title: track.name ?? "Untitled",
                genre: genre,
                playPosition: position
            ))
        } else {
            concertHistory.append(ConcertHistoryEntry(
                id: concertID,
                setID: set.setID,
                setName: set.name ?? "Show sans nom",
                playedTracks: [
                    ConcertPlayedTrack(
                        audioFileID: track.audioFileID,
                        title: track.name ?? "Untitled",
                        genre: genre,
                        playPosition: 1
                    )
                ]
            ))
        }
    }

    func playStats(limit: Int = 5) -> [TrackPlayStat] {
        var grouped: [AudioFile.ID: [ConcertPlayedTrack]] = [:]
        for entry in concertHistory {
            for played in entry.playedTracks {
                grouped[played.audioFileID, default: []].append(played)
            }
        }

        return grouped.map { audioFileID, plays in
            TrackPlayStat(
                audioFileID: audioFileID,
                title: audioFilesByID[audioFileID]?.name ?? plays.last?.title ?? "Untitled",
                count: plays.count,
                lastPlayedAt: plays.map(\.playedAt).max()
            )
        }
        .sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast)
        }
        .prefix(limit)
        .map { $0 }
    }

    func lastPlayedDate(for track: AudioFile) -> Date? {
        concertHistory
            .flatMap(\.playedTracks)
            .filter { $0.audioFileID == track.audioFileID }
            .map(\.playedAt)
            .max()
    }

    func riskLevel(for track: AudioFile) -> TrackRiskLevel {
        guard let lastPlayed = lastPlayedDate(for: track) else { return .unknown }
        let months = Calendar.current.dateComponents([.month], from: lastPlayed, to: Date()).month ?? 0
        if months >= 12 {
            return .oneYear(months: months)
        }
        if months >= 6 {
            return .sixMonths(months: months)
        }
        return .recent
    }

    /// Bookmark du dossier des médias (persisté). nil si l'utilisateur
    /// n'a pas encore localisé le dossier.
    var mediaFolderBookmarkData: Data? {
        didSet {
            audioURLCache.removeAll()
            unresolvedAudioIDs.removeAll()
            persistMediaFolderBookmark()
        }
    }

    /// Cache de résolution AudioFiles.Path -> URL réelle dans MediaFiles.
    /// On évite ainsi une recherche récursive at chaque rafraîchissement UI.
    @ObservationIgnored private var audioURLCache: [AudioFile.ID: URL] = [:]
    @ObservationIgnored private var unresolvedAudioIDs: Set<AudioFile.ID> = []

    // MARK: - Track Library : édition timeline locale

    /// Memos éditables par song. Initialisés depuis ShowBuddy au premier
    /// accès quand l'utilisateur n'a encore rien sauvegardé, puis persistés
    /// via le VelvetShowStore.
    var editableMemosByAudioFileID: [AudioFile.ID: [EditableMemo]] = [:] {
        didSet { persistEditableMemos() }
    }

    /// Pièces jointes locales par mémo éditable. Les fichiers eux-mêmes
    /// vivent dans Application Support/VELVET SHOW/Attachments/ — c'est
    /// l'index qui est sérialisé ici.
    var memoAttachmentsByMemoID: [EditableMemo.ID: [MemoAttachment]] = [:] {
        didSet { persistMemoAttachments() }
    }

    private static let mediaFolderBookmarkKey = "mediaFolderBookmark"

    private func persistMediaFolderBookmark() {
        let defaults = UserDefaults.standard
        if let data = mediaFolderBookmarkData {
            defaults.set(data, forKey: Self.mediaFolderBookmarkKey)
        } else {
            defaults.removeObject(forKey: Self.mediaFolderBookmarkKey)
        }
    }

    /// Crée et persiste un bookmark security-scoped for le dossier
    /// choisi par l'utilisateur. Appelé après un fileImport.
    func setMediaFolder(_ url: URL) {
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            self.mediaFolderBookmarkData = data
        } catch {
            self.lastError = "Media folder bookmark: \(error.localizedDescription)"
        }
    }

    /// Résout le bookmark en URL. Retourne nil si pas de bookmark
    /// stocké, ou si le bookmark est devenu invalide (dossier supprimé,
    /// déplacé sans relink, etc.).
    /// Statut du dossier MediaFiles — utilisé par l'UI for afficher un avertissement.
    enum MediaFolderStatus {
        case ok
        case notSet
        case stale
        case inaccessible
    }

    private(set) var mediaFolderStatus: MediaFolderStatus = .notSet

    func resolvedMediaFolderURL() -> URL? {
        guard let data = mediaFolderBookmarkData else {
            mediaFolderStatus = .notSet
            return nil
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            mediaFolderStatus = .inaccessible
            return nil
        }
        if isStale {
            // Tenter de renouveler le bookmark silencieusement.
            if let fresh = try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(fresh, forKey: Self.mediaFolderBookmarkKey)
                mediaFolderBookmarkData = fresh
            } else {
                mediaFolderStatus = .stale
                return nil
            }
        }
        // Vérifier que le dossier est physiquement accessible.
        let scoped = url.startAccessingSecurityScopedResource()
        let exists = FileManager.default.fileExists(atPath: url.path)
        if scoped { url.stopAccessingSecurityScopedResource() }
        if exists {
            mediaFolderStatus = .ok
            return url
        } else {
            mediaFolderStatus = .inaccessible
            return nil
        }
    }

    /// Affichage humain du dossier des médias actuellement autorisé
    /// (pour le bouton "Localiser...").
    var mediaFolderDisplayPath: String? {
        resolvedMediaFolderURL()?.path
    }

    // MARK: - Change Audio Library (remap des fileURL)

    /// Résultat d'une vérification de rebasage (preview, sans écriture).
    struct MediaRemapPreview {
        let newRoot: URL
        /// Tracks dont le fichier existe dans newRoot → prêts at remapper.
        let remappable: [(track: VelvetTrack, newURL: URL)]
        /// Tracks dont le fichier n'est PAS trouvé → conservent l'ancienne URL.
        let notFound: [VelvetTrack]

        var remappableCount: Int { remappable.count }
        var notFoundCount:   Int { notFound.count }
        var total:           Int { remappable.count + notFound.count }
    }

    /// Résultat final après application du remap.
    struct MediaRemapResult {
        let remapped: Int
        let kept:     Int
        let notFoundTitles: [String]
        let newRootPath: String
    }

    /// Calcule le préfixe commun de tous les fileURL velvetTracks.
    /// Retourne nil si la bibliothèque est vide ou hétérogène.
    private func currentMediaRootPath() -> String? {
        let paths = velvetTracks.map { $0.fileURL.path }
        guard !paths.isEmpty else { return nil }
        var components = paths[0].components(separatedBy: "/")
        for path in paths.dropFirst() {
            let other = path.components(separatedBy: "/")
            var i = 0
            while i < components.count && i < other.count && components[i] == other[i] { i += 1 }
            components = Array(components.prefix(i))
        }
        let common = components.joined(separator: "/")
        return common.isEmpty ? nil : common
    }

    /// Preview — aucune écriture. Calcule for chaque track si son fichier
    /// existe dans `newRoot` avec le même chemin relatif.
    func previewMediaRemap(to newRoot: URL) -> MediaRemapPreview {
        let currentRoot = currentMediaRootPath() ?? ""
        var remappable: [(track: VelvetTrack, newURL: URL)] = []
        var notFound:   [VelvetTrack] = []

        for track in velvetTracks {
            let currentPath = track.fileURL.path
            // Chemin relatif depuis la racine commune (ex: "IMPACT/!! Butterfly.mp3")
            let relativePath: String
            if !currentRoot.isEmpty && currentPath.hasPrefix(currentRoot) {
                relativePath = String(currentPath.dropFirst(currentRoot.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            } else {
                // Fallback : derniers 2 composants (FOLDER/file)
                let comps = currentPath.components(separatedBy: "/").filter { !$0.isEmpty }
                relativePath = comps.suffix(2).joined(separator: "/")
            }
            let candidate = newRoot.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                remappable.append((track: track, newURL: candidate))
            } else {
                notFound.append(track)
            }
        }
        return MediaRemapPreview(newRoot: newRoot, remappable: remappable, notFound: notFound)
    }

    /// Application — sauvegarde un .bak, puis réécrit les fileURL des tracks
    /// dont le fichier est trouvé. Les tracks manquants conservent leur ancienne URL.
    @discardableResult
    func applyMediaRemap(_ preview: MediaRemapPreview) -> MediaRemapResult {
        // 1. Backup daté avant toute modification
        backupVelvetShowState(tag: "pre-remap")

        // 2. Construire un mapping id → newURL
        let remapByID = Dictionary(uniqueKeysWithValues: preview.remappable.map { ($0.track.id, $0.newURL) })

        // 3. Réécrire les fileURL en place
        for idx in velvetTracks.indices {
            if let newURL = remapByID[velvetTracks[idx].id] {
                velvetTracks[idx].fileURL = newURL
            }
        }

        // 4. Mettre at jour le bookmark du dossier médias to la nouvelle racine
        setMediaFolder(preview.newRoot)

        // 5. Forcer une sauvegarde immédiate
        store.saveNow()

        return MediaRemapResult(
            remapped: preview.remappableCount,
            kept:     preview.notFoundCount,
            notFoundTitles: preview.notFound.map(\.title),
            newRootPath: preview.newRoot.path
        )
    }

    /// Nom métier plus explicite for les nouvelles phases audio.
    var mediaRootURL: URL? {
        resolvedMediaFolderURL()
    }

    /// Tente de détecter automatiquement `SbsBackup/MediaFiles` quand le
    /// fichier imported est `SbsBackup/ShowBuddy.db`.
    private func detectMediaFolder(nextToDatabase dbURL: URL) {
        let folder = dbURL.deletingLastPathComponent()
        guard folder.lastPathComponent == "SbsBackup" else { return }

        let candidate = folder.appendingPathComponent("MediaFiles", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }

        setMediaFolder(candidate)
    }

    /// Résout l'URL audio réelle for un AudioFile ShowBuddy.
    ///
    /// Ordre demandé :
    /// 1. Path absolu existant.
    /// 2. mediaRootURL + Path relatif.
    /// 3. mediaRootURL + nom du fichier.
    /// 4. recherche récursive limitée par filename exact.
    func resolvedAudioURL(for track: AudioFile) -> URL? {
        if let cached = audioURLCache[track.audioFileID] {
            return cached
        }
        if unresolvedAudioIDs.contains(track.audioFileID) {
            return nil
        }

        guard let rawPath = track.path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else {
            unresolvedAudioIDs.insert(track.audioFileID)
            return nil
        }

        let normalizedPath = rawPath.replacingOccurrences(of: "\\", with: "/")
        let isAbsolutePath = (normalizedPath as NSString).isAbsolutePath
        let absoluteURL = URL(fileURLWithPath: normalizedPath)
        if isAbsolutePath,
           FileManager.default.fileExists(atPath: absoluteURL.path) {
            audioURLCache[track.audioFileID] = absoluteURL
            return absoluteURL
        }

        guard let mediaRoot = mediaRootURL else {
            unresolvedAudioIDs.insert(track.audioFileID)
            return nil
        }

        let scoped = mediaRoot.startAccessingSecurityScopedResource()
        defer { if scoped { mediaRoot.stopAccessingSecurityScopedResource() } }

        if !isAbsolutePath {
            let relativeURL = mediaRoot.appendingPathComponent(normalizedPath)
            if FileManager.default.fileExists(atPath: relativeURL.path) {
                audioURLCache[track.audioFileID] = relativeURL
                return relativeURL
            }
        }

        let filename = (normalizedPath as NSString).lastPathComponent
        let directFilenameURL = mediaRoot.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: directFilenameURL.path) {
            audioURLCache[track.audioFileID] = directFilenameURL
            return directFilenameURL
        }

        if let recursiveURL = findAudioFile(named: filename, under: mediaRoot) {
            audioURLCache[track.audioFileID] = recursiveURL
            return recursiveURL
        }

        unresolvedAudioIDs.insert(track.audioFileID)
        return nil
    }

    func isAudioFileFound(for track: AudioFile) -> Bool {
        resolvedAudioURL(for: track) != nil
    }

    private func findAudioFile(named filename: String, under root: URL) -> URL? {
        guard !filename.isEmpty,
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else { return nil }

        var inspectedCount = 0
        for case let url as URL in enumerator {
            inspectedCount += 1
            if inspectedCount > 10_000 { break }
            guard url.lastPathComponent == filename else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                return url
            }
        }
        return nil
    }

    // MARK: - Chargement d'un song dans le moteur audio

    /// Charge le song dans `audioEngine` et mémorise le contexte
    /// (track + show) for que le Prompter puisse résoudre les mémos.
    func load(track: AudioFile) {
        guard track.path?.isEmpty == false else {
            self.lastError = AudioEngine.AudioError.noPath.localizedDescription
            return
        }
        guard let fileURL = resolvedAudioURL(for: track),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            self.lastError = "Audio file not found for \"\(track.name ?? "Untitled")\". Choose the MediaFiles folder from the ShowBuddy backup."
            return
        }
        let show = lightShows(for: track).first
        let trim = effectiveTrim(for: track)
        let volumeOffsetDB = volumeOffsetDB(for: track)
        let normDB = effectiveNormGainDB(for: track)
        let folder = mediaRootURL

        do {
            audioEngine.normGainDB = normDB
            try audioEngine.load(
                url: fileURL,
                trimStart: trim.start,
                trimEnd: trim.end,
                volumeOffsetDB: volumeOffsetDB,
                accessFolder: folder
            )
            self.currentlyLoadedTrack = track
            self.currentlyLoadedShow = show
            self.firedMidiTriggers = []
            self.broadcastState()
            self.preloadedPlaybackContext = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    // MARK: - Trim Velvet (non destructif)

    /// Trim effectif d'un song : priorité au trim défini par
    /// l'utilisateur dans VELVET SHOW, fallback sur les valeurs
    /// éventuellement présentes dans le `LightShow` ShowBuddy d'origine.
    /// `end == 0` signifie "pas de trim de fin" (lecture jusqu'au bout).
    func effectiveTrim(for track: AudioFile) -> (start: TimeInterval, end: TimeInterval) {
        if let velvet = trimsByAudioFileID[track.audioFileID] {
            return (velvet.trimStart, velvet.trimEnd)
        }
        let show = lightShows(for: track).first
        return (show?.trimStart ?? 0, show?.trimEnd ?? 0)
    }

    /// Définit (ou met at jour) le trim Velvet d'un song. Si le song
    /// est actuellement chargé dans l'AudioEngine, les nouvelles bornes
    /// sont également appliquées en mémoire for que la prochaine action
    /// transport en tienne compte sans avoir at recharger le fichier.
    func setTrim(for track: AudioFile, start: TimeInterval, end: TimeInterval) {
        let trim = VelvetTrackTrim(
            audioFileID: track.audioFileID,
            trimStart: max(0, start),
            trimEnd: max(0, end),
            updatedAt: Date()
        )
        trimsByAudioFileID[track.audioFileID] = trim
        if currentlyLoadedTrack?.audioFileID == track.audioFileID {
            audioEngine.setTrims(start: trim.trimStart, end: trim.trimEnd)
        }
    }

    /// Retire le trim Velvet d'un song. Le fallback ShowBuddy (s'il
    /// existe) redevient actif.
    func clearTrim(for track: AudioFile) {
        trimsByAudioFileID.removeValue(forKey: track.audioFileID)
        if currentlyLoadedTrack?.audioFileID == track.audioFileID {
            let fallback = effectiveTrim(for: track)
            audioEngine.setTrims(start: fallback.start, end: fallback.end)
        }
    }

    /// Vrai si l'utilisateur a un trim Velvet stocké for ce song
    /// (utilisé par l'UI for afficher "Réinitialiser trim").
    func hasVelvetTrim(for track: AudioFile) -> Bool {
        trimsByAudioFileID[track.audioFileID] != nil
    }

    // MARK: - Volume Velvet (non destructif)

    func volumeOffsetDB(for track: AudioFile) -> Double {
        volumeByAudioFileID[track.audioFileID]?.volumeOffsetDB ?? 0
    }

    func setVolumeOffsetDB(_ offsetDB: Double, for track: AudioFile) {
        let safe = VelvetTrackVolume.clamped(offsetDB)
        if abs(safe) < 0.05 {
            resetVolume(for: track)
            return
        }
        volumeByAudioFileID[track.audioFileID] = VelvetTrackVolume(
            audioFileID: track.audioFileID,
            volumeOffsetDB: safe,
            updatedAt: Date()
        )
        if currentlyLoadedTrack?.audioFileID == track.audioFileID {
            audioEngine.setVolumeOffsetDB(safe)
        }
    }

    func resetVolume(for track: AudioFile) {
        volumeByAudioFileID.removeValue(forKey: track.audioFileID)
        if currentlyLoadedTrack?.audioFileID == track.audioFileID {
            audioEngine.setVolumeOffsetDB(0)
        }
    }

    // MARK: - Normalisation de lecture

    /// Active ou désactive la normalisation LUFS.
    var isNormalizationEnabled: Bool {
        get { store.state.isNormalizationEnabled }
        set {
            store.update { $0.isNormalizationEnabled = newValue }
            if let track = currentlyLoadedTrack {
                audioEngine.setNormGainDB(effectiveNormGainDB(for: track))
            }
        }
    }

    /// Gain de normalisation effectif at appliquer for un song (dB).
    /// Formule : min(gainLUFS, gainSafe), clampé dans [−4, +4].
    /// Retourne 0 si la normalisation est désactivée ou si le song n'a
    /// pas encore été analysé.
    func effectiveNormGainDB(for track: AudioFile) -> Double {
        guard store.state.isNormalizationEnabled,
              let info = volumeByAudioFileID[track.audioFileID],
              let lufs = info.measuredLUFS,
              let tp   = info.measuredTruePeakDB else { return 0 }
        let target    = store.state.normTargetLUFS
        let gainLUFS  = target - lufs
        // Plafond True Peak : ne jamais dépasser −1 dBTP après gain
        let gainSafe  = -1.0 - tp
        let gainEndal = min(gainLUFS, gainSafe)
        return max(-4.0, min(4.0, gainEndal))
    }

    /// Mesure le LUFS-I, le True Peak et calcule le gain de normalisation
    /// for `track`. Stocke les résultats dans `volumeByAudioFileID`.
    /// Ne modifie pas `playbackGain` ni `AudioEngine`.
    func analyzeLoudness(for track: AudioFile) async throws {
        guard let url = resolvedAudioURL(for: track) else {
            throw LoudnessError.invalidFile
        }
        let target = store.state.normTargetLUFS
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let result = try await LoudnessAnalyzer().analyze(url: url, targetLUFS: target)

        let existing   = volumeByAudioFileID[track.audioFileID]
        let offsetDB   = existing?.volumeOffsetDB ?? 0
        volumeByAudioFileID[track.audioFileID] = VelvetTrackVolume(
            audioFileID:        track.audioFileID,
            volumeOffsetDB:     offsetDB,
            updatedAt:          existing?.updatedAt ?? Date(),
            measuredLUFS:       result.integratedLUFS,
            measuredTruePeakDB: result.truePeakDB,
            measuredPcmPeakDB:  result.pcmPeakDB,
            normGainDB:         result.normGainDB,
            normTarget:         target,
            normAnalysedAt:     Date()
        )
    }

    /// Résultat d'analyse LUFS for un song, ou nil si non analysé.
    func loudnessInfo(for track: AudioFile) -> VelvetTrackVolume? {
        guard let v = volumeByAudioFileID[track.audioFileID],
              v.measuredLUFS != nil else { return nil }
        return v
    }

    func editableMemos(for track: AudioFile) -> [EditableMemo] {
        if let existing = editableMemosByAudioFileID[track.audioFileID] {
            return existing.sorted { $0.memoTime < $1.memoTime }
        }
        let seeded = memos(for: track).map { memo in
            EditableMemo(showMemo: memo)
        }
        editableMemosByAudioFileID[track.audioFileID] = seeded
        return seeded.sorted { $0.memoTime < $1.memoTime }
    }

    func saveEditableMemos(_ memos: [EditableMemo], for track: AudioFile) {
        editableMemosByAudioFileID[track.audioFileID] = memos.sorted { $0.memoTime < $1.memoTime }
    }

    // MARK: - Nettoyage des mémos MIDI de fin

    /// Un mémo MIDI déclenché dans les final seconds d'un song.
    /// Repéré par le scan : c'est l'utilisateur qui décide de l'action.
    struct TailMidiEndding: Identifiable {
        let id: UUID                  // = memo.id
        let track: AudioFile
        let memo: EditableMemo
        /// Heure de déclenchement du trigger concerné (start ou fin du mémo).
        let triggerTime: TimeInterval
        /// End effective de lecture du song (trim de fin ou durée fichier).
        let effectiveEnd: TimeInterval
        let eventName: String
        /// Vrai si l'event est le Stop Cue global ou ressemble at une
        /// ambiance de sécurité (nom contenant "purple").
        let isStopCueLike: Bool
    }

    /// Scanne toute la bibliothèque : mémos avec MIDI dont le déclenchement
    /// tombe dans les `seconds` final seconds de la fenêtre de lecture.
    /// Lecture seule — aucune modification.
    func scanTailMidiMemos(within seconds: TimeInterval) -> [TailMidiEndding] {
        var findings: [TailMidiEndding] = []
        for track in audioFiles {
            let trim = effectiveTrim(for: track)
            let end: TimeInterval
            if trim.end > 0 {
                end = trim.end
            } else if let len = track.lengthSecs, len > 0 {
                end = len
            } else {
                continue  // durée inconnue → fenêtre incalculable
            }
            let windowStart = max(0, end - seconds)
            // Lecture sans effet de bord : on n'appelle pas editableMemos(for:)
            // qui seed le dictionnaire — scan pur.
            let memos = editableMemosByAudioFileID[track.audioFileID] ?? []
            for memo in memos {
                func eventInfo(_ id: Int64) -> (String, Bool) {
                    let name = midiEventsByID[id]?.name ?? "MidiEvent \(id)"
                    let isStopLike = id == restCueMidiEventID
                    return (name, isStopLike)
                }
                if let eventID = memo.startMidiEventID,
                   memo.memoTime >= windowStart, memo.memoTime <= end {
                    let (name, stopLike) = eventInfo(eventID)
                    findings.append(TailMidiEndding(
                        id: memo.id, track: track, memo: memo,
                        triggerTime: memo.memoTime, effectiveEnd: end,
                        eventName: name, isStopCueLike: stopLike
                    ))
                } else if let eventID = memo.endMidiEventID {
                    let endTrigger = memo.memoTime + memo.memoLength
                    if endTrigger >= windowStart, endTrigger <= end {
                        let (name, stopLike) = eventInfo(eventID)
                        findings.append(TailMidiEndding(
                            id: memo.id, track: track, memo: memo,
                            triggerTime: endTrigger, effectiveEnd: end,
                            eventName: name, isStopCueLike: stopLike
                        ))
                    }
                }
            }
        }
        return findings.sorted {
            ($0.track.name ?? "") < ($1.track.name ?? "")
        }
    }

    /// Retire l'envoi MIDI (start + end) d'un mémo sans toucher au texte,
    /// au timestamp ni at la durée. Le mémo reste visible dans le prompteur.
    func disableMidi(memoID: UUID, in track: AudioFile) {
        guard var memos = editableMemosByAudioFileID[track.audioFileID],
              let idx = memos.firstIndex(where: { $0.id == memoID }) else { return }
        memos[idx].startMidiEventID = nil
        memos[idx].endMidiEventID = nil
        editableMemosByAudioFileID[track.audioFileID] = memos
    }

    /// Supprime entièrement un mémo. Appelé uniquement après confirmation
    /// explicite de l'utilisateur dans l'outil de nettoyage.
    func deleteMemo(memoID: UUID, in track: AudioFile) {
        guard var memos = editableMemosByAudioFileID[track.audioFileID] else { return }
        memos.removeAll { $0.id == memoID }
        editableMemosByAudioFileID[track.audioFileID] = memos
    }

    /// Memos réellement affichés par les vues live (Prompter, timeline de
    /// prompter). Cette source inclut les imports/éditions Velvet locaux et
    /// ne modifie jamais ShowBuddy.db.
    func prompterMemos(for track: AudioFile) -> [EditableMemo] {
        editableMemos(for: track)
    }

    func attachments(for memoID: EditableMemo.ID) -> [MemoAttachment] {
        memoAttachmentsByMemoID[memoID] ?? []
    }

    /// Copie un fichier source dans `Application Support/VELVET SHOW/Attachments/`
    /// puis enregistre la référence dans l'état Velvet Show. Le fichier
    /// d'origine n'est jamais lu après cet appel : la copie devient la
    /// source de vérité.
    func addAttachment(
        sourceURL: URL,
        to memoID: EditableMemo.ID,
        type: MemoAttachmentType
    ) {
        do {
            let copied = try store.importAttachment(from: sourceURL)
            let attachment = MemoAttachment(
                memoID: memoID,
                fileName: sourceURL.lastPathComponent,
                fileURL: copied,
                type: type
            )
            memoAttachmentsByMemoID[memoID, default: []].append(attachment)
        } catch {
            lastError = "Could not import attachment: \(error.localizedDescription)"
        }
    }

    /// Retire une pièce jointe de l'index et supprime sa copie locale.
    func removeAttachment(_ attachment: MemoAttachment) {
        memoAttachmentsByMemoID[attachment.memoID]?.removeAll { $0.id == attachment.id }
        store.discardAttachmentFile(at: attachment.fileURL)
    }

    /// Point d'entrée unique Play/Stop for Track Library et Show Library.
    /// Le MIDI n'est pas touché ici : on charge seulement l'audio local.
    func togglePlayback(track: AudioFile, set: ShowSet? = nil, element: SetElement? = nil) {
        let isSameTrack = currentlyLoadedTrack?.audioFileID == track.audioFileID
        let isResume = isSameTrack && audioEngine.state == .paused
        let isAudiblyRunning = audioEngine.state == .playing || audioEngine.state == .stopping

        if isSameTrack, isAudiblyRunning {
            // Stop manuel : NE PAS marquer le song comme joué.
            // Seule la fin naturelle (handlePlaybackEndished) doit le faire.
            audioEngine.stop()
            return
        }

        if !isSameTrack {
            load(track: track)
        }

        currentlyLoadedSetID = set?.setID
        currentlyLoadedSetElementID = element?.setElementID
        preloadedStopElementID = nil
        if let set, !isResume {
            recordHistory(track: track, in: set)
        }
        if !isResume { firedMidiTriggers = [] }
        audioEngine.play()
        broadcastState()
        startMidiScheduler()
        // Indicateur "prochain song" dès le premier lancement manuel —
        // startPlayback le faisait déjà, ce chemin (double-clic setlist)
        // l'omettait : rien ne clignotait avant le premier enchaînement.
        updateNextNaturalIndicator()
    }

    func isCurrentTrack(_ track: AudioFile?) -> Bool {
        guard let track else { return false }
        return currentlyLoadedTrack?.audioFileID == track.audioFileID
            && (audioEngine.state == .playing || audioEngine.state == .stopping)
    }

    // MARK: - Show Safety : remplacement avec fade-out
    //
    // En mode sécurisé, un double-clic sur une tuile setlist déclenche une
    // confirmation explicite si un autre song est déjà en lecture. Le
    // bouton "Lancer avec fade-out" passe ensuite par `startReplacement` :
    // on stoppe le song courant avec un fade audible, puis on charge
    // et démarre le nouveau juste après la fin du fade.

    /// Retourne `true` si l'UI doit afficher la confirmation "Replace le
    /// song en cours ?" avant de lancer ce song. Le mode sécurisé
    /// neutralise complètement cette fonction quand il est désactivé.
    func shouldConfirmReplacement(for song: Song) -> Bool {
        guard let audio = song.audio else { return false }
        return shouldConfirmReplacement(for: audio)
    }

    func shouldConfirmReplacement(for track: AudioFile) -> Bool {
        guard isSafePlayEnabled else { return false }
        // Confirmation uniquement si du son sort réellement (état .playing).
        // En pause ou at l'arrêt, aucun son n'est audible — lancement direct.
        guard audioEngine.state == .playing, let current = currentlyLoadedTrack else { return false }
        return current.audioFileID != track.audioFileID
    }

    /// Stoppe le song en cours avec un fade-out doux, puis enchaîne sur
    /// le nouveau song. Utilisé par le dialogue de confirmation et par
    /// les actions live qui veulent éviter une coupure brutale.
    ///
    /// - Jeton d'annulation : si appelé une seconde fois avant la fin du
    ///   premier fade, la tâche précédente est annulée avant d'en créer une
    ///   nouvelle — élimine la race condition du double-clic / double-↩.
    /// - `isReplacingTrack` : posé pendant tout le remplacement for que
    ///   `handlePlaybackEndished` ne déclenche pas la Queue Auto si le segment
    ///   se termine naturellement pendant le fade.
    func startReplacement(
        track: AudioFile,
        set: ShowSet,
        element: SetElement?,
        effect: TransitionEffect = .fade
    ) {
        // Annule un remplacement déjà en cours (double-clic, ↩ rapide).
        replacementTask?.cancel()
        replacementTask = nil
        isReplacingTrack = true
        lastTransitionEffect = effect

        // Arrête immédiatement le scheduler MIDI de l'ancien song.
        // Sans ça, le scheduler zombie continue de ticker pendant tout le
        // délai du fade et reprend avec le nouveau currentlyLoadedTrack,
        // pouvant déclencher les mémos de l'ancien song au mauvais moment.
        midiSchedulerTask?.cancel()
        midiSchedulerTask = nil

        // Marque le song courant joué avant le fade — il a été quitté
        // volontairement, doit sortir des "restants".
        markCurrentShowSongPlayed()

        // Lance l'effet de sortie adapté.

        if effect == .echo {
            // ── ECHO ────────────────────────────────────────────────────────
            // Calcul du beat depuis le BPM du song en cours.
            // Clampage [60–140 BPM] → beat [428 ms–1 000 ms] → total [1.7–4.0 s].
            // Fallback sans BPM : 625 ms/beat ≈ 96 BPM, total 2.5 s.
            let bpm = currentlyLoadedTrack.flatMap { effectiveTempo(for: $0) } ?? 96.0
            let clampedBPM = max(60.0, min(140.0, bpm))
            let beatMs = Int(60_000.0 / clampedBPM)
            // 5 beats : 1 beat de pre-arm (remplissage buffer) + 4 beats de répétitions.
            let echoDurationMs = beatMs * 5
            audioEngine.stopWithEchoFade(beatDuration: Double(beatMs) / 1_000.0)
            let delayMillis = echoDurationMs + 40
            print("[ECHO] BPM=\(String(format: "%.1f", clampedBPM)) beat=\(beatMs)ms total=\(echoDurationMs)ms")
            replacementTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(delayMillis)) } catch { return }
                guard let self else { return }
                self.load(track: track)
                self.currentlyLoadedSetID = set.setID
                self.currentlyLoadedSetElementID = element?.setElementID
                self.recordHistory(track: track, in: set)
                self.audioEngine.play()
                self.startMidiScheduler()
                self.updateNextNaturalIndicator()
                self.isReplacingTrack = false
                self.replacementTask = nil
            }

        } else if effect == .fade || effect == .slowFade || effect == .filter {
            // ── CROSSFADE (FADE / SLOW FADE / FILTER) ──────────────────────
            // Les deux fades (out sur l'ancien nœud, in sur le nouveau)
            // courent en parallèle — aucun silence entre les songs.
            // FILTER ajoute un sweep low-pass 20 kHz → 300 Hz sur playerNode.
            // Pas de replacementTask : le timing est piloté par les completions
            // de fade audio, pas par Task.sleep.
            audioEngine.cancelCrossfade()

            guard let fileURL = resolvedAudioURL(for: track),
                  FileManager.default.fileExists(atPath: fileURL.path) else {
                lastError = "File not found for \"\(track.name ?? "Untitled")\"."
                isReplacingTrack = false
                return
            }
            let trim         = effectiveTrim(for: track)
            let newVolDB     = volumeOffsetDB(for: track)
            let newNormDB    = effectiveNormGainDB(for: track)
            pendingCrossfadeTrack = track

            do {
                try audioEngine.startCrossfade(
                    url: fileURL,
                    trimStart: trim.start,
                    trimEnd: trim.end,
                    volumeOffsetDB: newVolDB,
                    normGainDB: newNormDB,
                    accessFolder: mediaRootURL,
                    duration: effect.fadeOutDuration,
                    withFilter: effect == .filter
                ) { [weak self] in
                    guard let self else { return }
                    // finishCrossfade() a déjà été appelé par AudioEngine.
                    // On met at jour le contexte AppState avec le nouveau song.
                    self.currentlyLoadedTrack = track
                    self.currentlyLoadedShow  = self.lightShows(for: track).first
                    self.currentlyLoadedSetID = set.setID
                    self.currentlyLoadedSetElementID = element?.setElementID
                    self.recordHistory(track: track, in: set)
                    // Le scheduler tourne déjà depuis le début du crossfade
                    // (il suivait pendingCrossfadeTrack) — on ne le redémarre
                    // pas et on ne vide pas firedMidiTriggers, sinon les mémos
                    // déjà déclenchés pendant le fade repartiraient.
                    self.pendingCrossfadeSetElementID = nil
                    self.updateNextNaturalIndicator()
                    self.isReplacingTrack = false
                    self.pendingCrossfadeTrack = nil
                    print("[XFADE] Crossfade complete: scheduler continues on \(track.name ?? "?")")
                }
                // Scheduler du song ENTRANT, démarré immédiatement :
                // tickMidiScheduler le suit via crossfadeIncomingLivePosition.
                // startMidiScheduler annule l'ancien (génération) — pas de
                // double scheduler. Le pre-arm de la première tick déclenche
                // at l'heure les mémos placés au tout début du song.
                firedMidiTriggers = []
                startMidiScheduler()
                // Le "suivant" affiché bascule immédiatement sur celui du
                // song entrant — pas d'info périmée pendant le fade.
                pendingCrossfadeSetElementID = element?.setElementID
                updateUpcomingTrack()
            } catch {
                // Fichier illisible : fallback sur fade-out + délai classique.
                lastError = error.localizedDescription
                pendingCrossfadeTrack = nil
                audioEngine.stop(fadeOutDuration: effect.fadeOutDuration)
                let delayMillis = effect.loadDelayMillis
                replacementTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .milliseconds(delayMillis)) } catch { return }
                    guard let self else { return }
                    self.load(track: track)
                    self.currentlyLoadedSetID = set.setID
                    self.currentlyLoadedSetElementID = element?.setElementID
                    self.recordHistory(track: track, in: set)
                    self.audioEngine.play()
                    self.startMidiScheduler()
                    self.updateNextNaturalIndicator()
                    self.isReplacingTrack = false
                    self.replacementTask = nil
                }
            }

        } else {
            // ── FILTER / BACKSPIN (bientôt) — comportement actuel ───────────
            audioEngine.stop(fadeOutDuration: effect.fadeOutDuration)
            let delayMillis = effect.loadDelayMillis
            replacementTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(delayMillis)) } catch { return }
                guard let self else { return }
                self.load(track: track)
                self.currentlyLoadedSetID = set.setID
                self.currentlyLoadedSetElementID = element?.setElementID
                self.recordHistory(track: track, in: set)
                self.audioEngine.play()
                self.startMidiScheduler()
                self.updateNextNaturalIndicator()
                self.isReplacingTrack = false
                self.replacementTask = nil
            }
        }
    }

    // MARK: - Transports utilisateur (cohérence des fades)
    //
    // Tous les chemins qui peuvent lancer ou suspendre la lecture
    // (raccourcis clavier, boutons de l'UI, futur footswitch) passent par
    // ces helpers — ils centralisent les durées de fade for qu'on
    // n'entende jamais de coupure sèche pendant un concert.

    /// Duration du fade-out at la pause utilisateur. Plus court que le stop
    /// for que la reprise se sente immédiate.
    static let pauseFadeOutSeconds: TimeInterval = 1.2

    /// Duration du fade-in at la reprise / au lancement utilisateur.
    static let resumeFadeInSeconds: TimeInterval = 0.4

    func requestPause() {
        audioEngine.pause(fadeOutDuration: Self.pauseFadeOutSeconds)
        broadcastState()
    }

    func requestResume() {
        // Stop → Resume sans passer par requestStop() (ex : audioEngine.stop()
        // direct dans togglePlayback, puis Space ou bouton Play) : les
        // firedMidiTriggers n'ont pas été vidés par requestStop(). On les
        // remet at zéro ici for que les cues repassent depuis le début.
        // Pause → Resume : .paused, on ne touche pas firedMidiTriggers. ✅
        if audioEngine.state == .stopped { firedMidiTriggers = [] }
        audioEngine.play(fadeInDuration: Self.resumeFadeInSeconds)
        // Le scheduler MIDI doit être (re)lancé dans tous les cas :
        // - Pause → Resume : le scheduler était toujours vivant mais en veille
        //   (guard state == .playing), startMidiScheduler() annule la tâche
        //   existante et en crée une propre. firedMidiTriggers est intact. ✅
        // - Stop → Resume : le scheduler avait été annulé par requestStop(),
        //   firedMidiTriggers avait été remis at [] par requestStop(). Sans
        //   ce startMidiScheduler(), aucun MIDI ne partait jamais. ✅
        startMidiScheduler()
    }

    /// Repositionne le song chargé au début effectif (trimStart).
    ///
    /// - Si en lecture : reprend depuis le début sans interruption.
    /// - Si en pause : repositionne et reste en pause.
    /// - Ne marque pas le song comme joué.
    /// - Ne touche pas la Queue ni l'historique.
    func returnToBeginning() {
        // seek(to: 0) est relatif at effectiveStart — 0 = trimStart.
        audioEngine.seek(to: 0)
    }

    func requestStop() {
        // Si un remplacement automatique est en vol (fade + délai), on
        // l'annule : l'utilisateur a décidé de tout stopper, le nouveau
        // song ne doit pas démarrer après le délai.
        replacementTask?.cancel()
        replacementTask = nil
        isReplacingTrack = false
        pendingCrossfadeTrack = nil
        pendingCrossfadeSetElementID = nil
        preloadedPlaybackContext = nil
        nextNaturalSongElementID = nil
        updateUpcomingTrack()

        // Cue de repos — stop explicite utilisateur.
        sendRestCueIfNeeded(trigger: .stop)
        midiSchedulerTask?.cancel()
        midiSchedulerTask = nil
        // Réinitialiser les triggers MIDI après STOP explicite, for que les
        // mémos du song puissent repartir normalement au prochain Play.
        // Le Stop Cue a déjà été envoyé ci-dessus — ce reset ne l'affecte pas.
        firedMidiTriggers = []
        print("[MIDI] firedMidiTriggers reset after STOP")
        audioEngine.cancelCrossfade()
        audioEngine.stop(fadeOutDuration: 0.8)
        broadcastState()
    }

    /// Appelé at l'ouverture du TimelineEditorView plein écran (non-embedded).
    ///
    /// - Pose le flag `isInEditingMode` AVANT le stop for que
    ///   `handlePlaybackEndished` ne marque pas le song joué et ne
    ///   lance pas la queue automatiquement.
    /// - Arrêt rapide (fondu 0.2 s) for ne pas laisser l'audio trainer.
    /// - La queue et l'état du show ne sont PAS modifiés.
    func enterEditingMode() {
        guard !isInEditingMode else { return }
        isInEditingMode = true
        // Arrêt propre mais silencieux vis-à-vis de la logique concert.
        audioEngine.stop(fadeOutDuration: 0.2)
    }

    /// Appelé at la fermeture du TimelineEditorView plein écran.
    ///
    /// - Retire le flag : la queue et l'auto-play redeviennent actifs.
    /// - NE relance PAS la lecture : l'utilisateur doit agir volontairement.
    func exitEditingMode() {
        isInEditingMode = false
    }

    /// BPM du song : override utilisateur en priorité, puis Velvet,
    /// puis LightShow ShowBuddy.
    func effectiveTempo(for track: AudioFile) -> Double? {
        if let o = store.state.tempoOverridesByAudioFileID[String(track.audioFileID)], o > 0 { return o }
        if let vt = velvetTrack(for: track), let t = vt.tempo, t > 0 { return t }
        return lightShowsByAudioFileID[track.audioFileID]?.first?.tempo
    }

    /// Définit (ou efface avec nil) le BPM édité par l'utilisateur.
    func setTempoOverride(_ bpm: Double?, for track: AudioFile) {
        let key = String(track.audioFileID)
        store.update {
            if let bpm, bpm > 0 {
                $0.tempoOverridesByAudioFileID[key] = bpm
            } else {
                $0.tempoOverridesByAudioFileID.removeValue(forKey: key)
            }
        }
    }

    /// Snapper la position au beat le plus proche si BPM connu.
    private func snapToBeat(position: TimeInterval, track: AudioFile) -> TimeInterval {
        guard let bpm = effectiveTempo(for: track), bpm > 0 else { return position }
        let beatDuration = 60.0 / bpm
        let origin = audioEngine.effectiveStart
        let relative = position - origin
        let snapped = (relative / beatDuration).rounded() * beatDuration
        return max(audioEngine.effectiveStart,
                   min(origin + snapped, audioEngine.effectiveEnd))
    }

    func seek(track: AudioFile, to position: TimeInterval) {
        if currentlyLoadedTrack?.audioFileID != track.audioFileID {
            load(track: track)
        }
        guard currentlyLoadedTrack?.audioFileID == track.audioFileID else { return }

        // Résoudre le comportement effectif (snap sans BPM → fondu)
        var effective = seekBehavior
        if effective == .fadeSnapBeat, effectiveTempo(for: track) == nil {
            effective = .fade
        }

        switch effective {
        case .raw:
            audioEngine.seek(to: position)
        case .fade:
            audioEngine.seekWithFade(to: position)
        case .fadeSnapBeat:
            let snapped = snapToBeat(position: position + audioEngine.effectiveStart, track: track)
            audioEngine.seekWithFade(to: snapped - audioEngine.effectiveStart)
        }
    }

    // MARK: - Raccourcis clavier globaux

    func handlePlayPauseShortcut() {
        switch audioEngine.state {
        case .playing:
            requestPause()
        case .paused:
            requestResume()
        case .stopping:
            break
        case .stopped:
            // En Track Library, si l'utilisateur a sélectionné une track différente
            // du dernier song chargé (ex. venant du mode Show), on joue la sélection.
            if mode == .trackLibrary,
               let selectedAudioFileID,
               let track = audioFilesByID[selectedAudioFileID],
               track.audioFileID != currentlyLoadedTrack?.audioFileID {
                preloadedPlaybackContext = nil
                startPlayback(track: track)
            } else if let ctx = preloadedPlaybackContext, let track = currentlyLoadedTrack {
                // Morceau préchargé automatiquement (fin naturelle ou Queue .manual).
                // startPlayback enregistre l'historique et relance le scheduler MIDI.
                preloadedPlaybackContext = nil
                startPlayback(track: track, set: ctx.set, element: ctx.element)
            } else if currentlyLoadedTrack != nil {
                requestResume()
            } else if let songContext = preferredShowSongContext(),
                      let audio = songContext.song.audio {
                startPlayback(track: audio, set: songContext.set, element: songContext.song.element)
            } else if let selectedAudioFileID,
                      let track = audioFilesByID[selectedAudioFileID] {
                startPlayback(track: track)
            }
        }
    }

    func handleStopShortcut() {
        requestStop()
    }

    func handleNextSongShortcut() {
        moveInCurrentShow(direction: 1)
    }

    func handlePreviousSongShortcut() {
        moveInCurrentShow(direction: -1)
    }

    private func startPlayback(track: AudioFile, set: ShowSet? = nil, element: SetElement? = nil) {
        let isResume = currentlyLoadedTrack?.audioFileID == track.audioFileID
            && audioEngine.state == .paused
        if currentlyLoadedTrack?.audioFileID != track.audioFileID {
            load(track: track)
        }
        currentlyLoadedSetID = set?.setID
        currentlyLoadedSetElementID = element?.setElementID
        preloadedStopElementID = nil
        if let set, !isResume {
            recordHistory(track: track, in: set)
        }
        if !isResume { firedMidiTriggers = [] }
        audioEngine.play()
        startMidiScheduler()
        updateNextNaturalIndicator()
    }

    private func preferredShowSongContext() -> (set: ShowSet, song: Song)? {
        guard let setID = selectedSetID,
              let set = sets.first(where: { $0.setID == setID }) else { return nil }
        let setSongs = songs(in: set)
        if let selectedElementID = selectedShowSetElementIDBySetID[setID],
           let selectedSong = setSongs.first(where: { $0.element.setElementID == selectedElementID }) {
            return (set, selectedSong)
        }
        if let firstRemaining = setSongs.first(where: { !isPlayed($0, in: set) }) {
            return (set, firstRemaining)
        }
        return setSongs.first.map { (set, $0) }
    }

    private func moveInCurrentShow(direction: Int) {
        guard let setID = currentlyLoadedSetID ?? selectedSetID,
              let set = sets.first(where: { $0.setID == setID }) else { return }
        let setSongs = songs(in: set)
        guard !setSongs.isEmpty else { return }

        let anchorID = currentlyLoadedSetID == setID
            ? currentlyLoadedSetElementID
            : selectedShowSetElementIDBySetID[setID]
        let startIndex = anchorID.flatMap { id in
            setSongs.firstIndex { $0.element.setElementID == id }
        } ?? (direction > 0 ? -1 : setSongs.count)

        var index = startIndex + direction
        while setSongs.indices.contains(index) {
            let song = setSongs[index]
            if let audio = song.audio {
                selectedShowSetElementIDBySetID[setID] = song.element.setElementID
                // Lecture active → crossfade Filter (même pipeline que tickAutoNext).
                // Silence (stopped/paused) → startPlayback direct, pas de fondu.
                if audioEngine.state == .playing || audioEngine.state == .stopping {
                    startReplacement(track: audio, set: set, element: song.element, effect: .filter)
                } else {
                    startPlayback(track: audio, set: set, element: song.element)
                }
                return
            }
            index += direction
        }
    }

    // MARK: - Helpers Prompter
    //
    // Le Prompter consomme directement `currentlyLoadedTrack` +
    // `audioEngine.currentPosition`. On expose deux helpers : le mémo
    // "actif" (dont la fenêtre [memoTime, memoTime + memoLength]
    // contient la position), et le "suivant" (premier mémo dont
    // memoTime > position).

    /// Memo actif at la position de lecture courante, ou nil.
    /// Si plusieurs mémos se chevauchent, on prend le plus récent
    /// (celui qui a démarré le plus tard avant la position courante).
    func currentMemo() -> EditableMemo? {
        guard let track = currentlyLoadedTrack else { return nil }
        let pos = audioEngine.currentPosition
        let candidates = prompterMemos(for: track).filter { memo in
            let start = memo.memoTime
            let end = start + memo.memoLength
            return start <= pos && pos <= end
        }
        // Le `.sorted` aurait été plus lisible mais on est déjà triés par
        // memoTime (cf. `memos(for:)`), donc le dernier qui matche est
        // forcément le plus récemment démarré.
        return candidates.last
    }

    /// Premier mémo non encore atteint, ou nil si on est en fin de song.
    func nextMemo() -> EditableMemo? {
        guard let track = currentlyLoadedTrack else { return nil }
        let pos = audioEngine.currentPosition
        return prompterMemos(for: track).first { memo in
            memo.memoTime > pos
        }
    }

    // MARK: - Sélections UI

    /// Set sélectionné (Show Library).
    var selectedSetID: ShowSet.ID?

    /// Catégorie sélectionnée (colonne 1 de la Track Library).
    var selectedCategoryID: TrackCategory.ID?

    /// Morceau sélectionné (colonne 2 de la Track Library).
    var selectedAudioFileID: AudioFile.ID?

    // MARK: - Divers UI

    /// Dernière erreur utilisateur — affichée dans un .alert.
    var lastError: String?

    var fileName: String { database?.fileURL.lastPathComponent ?? "—" }
    /// Vrai si ShowBuddy.db est ouverte OU si la migration structurelle a été faite.
    var isLoaded: Bool { database != nil || store.state.hasMigratedFromShowBuddy }

    // MARK: - Cache audio unifié

    private static func audioFile(from track: VelvetTrack) -> AudioFile {
        AudioFile(
            audioFileID: track.id,
            name: track.title,
            path: track.fileURL.path,
            note: track.note,
            lengthSecs: track.duration,
            mainAudioFileID: nil
        )
    }

    private func rebuildAudioFileCaches() {
        let allAudioFiles = audioFiles.sorted { ($0.name ?? "") < ($1.name ?? "") }
        audioFilesByID = Dictionary(uniqueKeysWithValues: allAudioFiles.map { ($0.audioFileID, $0) })
        categories = Self.buildCategories(from: allAudioFiles)
    }

    /// Met at jour le cache Velvet des métadonnées ShowBuddy.
    /// Appelé après chaque ouverture réussie de ShowBuddy.db.
    /// Les VelvetTracks natifs sont exclus : leurs métadonnées vivent déjà dans VelvetShowState.
    private func updateAudioFileMetaCache(from files: [AudioFile]) {
        let velvetIDs = Set(velvetTracks.map(\.id))
        var updated = store.state.audioFileMetaCacheByID
        for file in files where !velvetIDs.contains(file.audioFileID) {
            guard let name = file.name, let path = file.path else { continue }
            updated[String(file.audioFileID)] = AudioFileMetaCache(
                name: name,
                path: path,
                lengthSecs: file.lengthSecs
            )
        }
        store.update { $0.audioFileMetaCacheByID = updated }
    }

    /// Vrai si la track appartient au système Velvet (import manuel ou migré depuis ShowBuddy).
    func isVelvetTrack(_ track: AudioFile) -> Bool {
        velvetTrack(for: track) != nil
    }

    func velvetTrack(for audio: AudioFile) -> VelvetTrack? {
        velvetTracks.first { $0.id == audio.audioFileID }
    }

    func importVelvetTrack(from sourceURL: URL) {
        do {
            let copiedURL = try store.importMediaFile(from: sourceURL)
            let audioFile = try? AVAudioFile(forReading: copiedURL)
            let duration = audioFile.map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
            let title = sourceURL.deletingPathExtension().lastPathComponent
            let track = VelvetTrack(
                id: nextVelvetTrackAudioID(),
                title: title.isEmpty ? "New Song" : title,
                fileURL: copiedURL,
                duration: duration.isFinite && duration > 0 ? duration : nil
            )
            velvetTracks.append(track)
            selectedCategoryID = Self.category(for: copiedURL.path)
            selectedAudioFileID = track.id
        } catch {
            lastError = "Import song Velvet impossible : \(error.localizedDescription)"
        }
    }

    func updateVelvetTrack(
        _ track: AudioFile,
        title: String,
        genre: String,
        note: String,
        color: Color?,
        tempo: Double?
    ) {
        guard let index = velvetTracks.firstIndex(where: { $0.id == track.audioFileID }) else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        velvetTracks[index].title = trimmedTitle.isEmpty ? "Velvet Song" : trimmedTitle
        velvetTracks[index].genre = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        velvetTracks[index].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        velvetTracks[index].colorHex = color?.hexComponents
        velvetTracks[index].tempo = tempo
    }

    func deleteVelvetTrack(_ track: AudioFile) {
        guard let velvetTrack = velvetTrack(for: track) else { return }
        velvetTracks.removeAll { $0.id == velvetTrack.id }
        store.discardMediaFile(at: velvetTrack.fileURL)
        for index in velvetShows.indices {
            velvetShows[index].tracks.removeAll { $0.audioFileID == velvetTrack.id }
        }
        editableMemosByAudioFileID[velvetTrack.id] = nil
        if selectedAudioFileID == velvetTrack.id {
            selectedAudioFileID = audioFiles.first?.id
        }
    }

    private func nextVelvetTrackAudioID() -> Int64 {
        let minExisting = min(0,
            velvetTracks.map(\.id).min() ?? 0,
            velvetShows.flatMap { $0.tracks.map(\.audioFileID) }.min() ?? 0
        )
        let candidate = minExisting - 1
        if DemoIDRange.tracks.contains(candidate) { return DemoIDRange.tracks.lowerBound - 1 }
        return candidate
    }

    // MARK: - Import audio to MediaFiles

    /// Retourne les noms de sous-dossiers (catégories) présents dans MediaFiles.
    /// Utilisé for populer le picker de catégorie lors d'un import.
    func mediaCategories() -> [String] {
        guard let root = mediaRootURL else { return [] }
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ) else { return [] }
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { $0.lastPathComponent }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Résolution de conflit lors d'un import.
    enum AudioImportConflict {
        case replace       // Écrase le fichier existant
        case keepBoth      // Renomme le nouveau (ajoute " (2)", " (3)"...)
        case cancel
    }

    /// Importe un fichier audio dans MediaFiles/category/ et crée le VelvetTrack correspondant.
    ///
    /// - Parameters:
    ///   - sourceURL: fichier source (hors sandbox si nécessaire)
    ///   - category: nom du sous-dossier destination (sera créé s'il n'existe pas)
    ///   - conflict: comportement si un fichier du même nom existe déjà
    ///
    /// Constante-clé : cette méthode écrit dans MediaFiles (sandbox étendu via
    /// security-scoped bookmark). Elle NE touche PAS ShowBuddy.db.
    func importAudioToMediaFiles(
        from sourceURL: URL,
        category: String,
        conflict: AudioImportConflict
    ) throws {
        guard let root = mediaRootURL else {
            throw AudioFileError.noMediaFolder
        }

        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        // Scope refusé = bookmark dégradé (remontage volume, changement
        // d'entitlement...). Sans cette garde, copyItem échoue avec un
        // message "permission" trompeur sur le dossier catégorie.
        guard scoped else {
            print("[IMPORT] startAccessingSecurityScopedResource failed for \(root.path)")
            throw AudioFileError.mediaFolderAccessExpired
        }

        let fm = FileManager.default

        // Crée le sous-dossier si besoin
        let categoryDir = root.appendingPathComponent(category, isDirectory: true)
        try fm.createDirectory(at: categoryDir, withIntermediateDirectories: true)

        let filename = sourceURL.lastPathComponent
        var destURL = categoryDir.appendingPathComponent(filename)

        if fm.fileExists(atPath: destURL.path) {
            switch conflict {
            case .cancel:
                return
            case .replace:
                try fm.removeItem(at: destURL)
            case .keepBoth:
                destURL = uniqueDestinationURL(base: destURL, in: categoryDir)
            }
        }

        let sourcedScoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if sourcedScoped { sourceURL.stopAccessingSecurityScopedResource() } }
        try fm.copyItem(at: sourceURL, to: destURL)

        // Duration via AVAudioFile
        let audioFile = try? AVAudioFile(forReading: destURL)
        let duration: Double? = audioFile.map { Double($0.length) / $0.fileFormat.sampleRate }
        let title = destURL.deletingPathExtension().lastPathComponent

        let track = VelvetTrack(
            id: nextVelvetTrackAudioID(),
            title: title.isEmpty ? "New Song" : title,
            genre: category,
            fileURL: destURL,
            duration: duration.map { $0.isFinite && $0 > 0 ? $0 : nil } ?? nil
        )
        velvetTracks.append(track)
        // Invalide les caches for forcer la re-résolution
        audioURLCache.removeAll()
        unresolvedAudioIDs.removeAll()
        rebuildAudioFileCaches()
        selectedCategoryID = category
        selectedAudioFileID = track.id
    }

    // MARK: - Remplacement sécurisé d'un fichier audio

    /// Crée une sauvegarde horodatée du fichier audio dans AudioBackups/.
    /// Retourne l'URL de la sauvegarde créée.
    @discardableResult
    func backupAudioFile(for track: AudioFile) throws -> URL {
        guard let src = resolvedAudioURL(for: track) else {
            throw AudioFileError.fileNotFound
        }
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let backupDir = store.audioBackupsDirectoryURL
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let stamp = Self.backupTimestamp()
        let base  = src.deletingPathExtension().lastPathComponent
        let ext   = src.pathExtension
        let name  = ext.isEmpty ? "\(base)_\(stamp)" : "\(base)_\(stamp).\(ext)"
        let dest  = backupDir.appendingPathComponent(name)
        try fm.copyItem(at: src, to: dest)
        return dest
    }

    /// Remplace physiquement le fichier audio d'un song par `newURL`.
    ///
    /// Séquence :
    ///   1. Sauvegarde horodatée dans AudioBackups/
    ///   2. Copie newURL → chemin physique du song (écrasement)
    ///   3. Invalide le cache URL for forcer la re-résolution
    ///   4. Met at jour la durée dans VelvetTrack si applicable
    ///   5. Recharge le song dans AudioEngine si c'est le song courant
    ///
    /// Ne modifie jamais ShowBuddy.db. Le chemin du fichier ne change pas.
    func replaceAudioFile(for track: AudioFile, with newURL: URL) throws {
        guard let destURL = resolvedAudioURL(for: track) else {
            throw AudioFileError.fileNotFound
        }

        // 1. Backup
        try backupAudioFile(for: track)

        // 2. Copie physique
        let scopedMedia = mediaRootURL?.startAccessingSecurityScopedResource() ?? false
        defer { if scopedMedia { mediaRootURL?.stopAccessingSecurityScopedResource() } }
        let scopedNew = newURL.startAccessingSecurityScopedResource()
        defer { if scopedNew { newURL.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        try fm.copyItem(at: newURL, to: destURL)

        // 3. Cache invalide
        audioURLCache[track.audioFileID] = nil
        unresolvedAudioIDs.remove(track.audioFileID)

        // 4. Duration
        let newAudioFile = try? AVAudioFile(forReading: destURL)
        let newDuration: Double? = newAudioFile.map { Double($0.length) / $0.fileFormat.sampleRate }
        if let idx = velvetTracks.firstIndex(where: { $0.id == track.audioFileID }),
           let d = newDuration, d.isFinite, d > 0 {
            velvetTracks[idx].duration = d
        }

        // 5. Rechargement si song courant
        if currentlyLoadedTrack?.audioFileID == track.audioFileID {
            load(track: track)
        }
    }

    /// Items Velvet (cue points, trim, mémos) qui dépassent `newDuration`.
    /// Utilisé for l'alerte post-remplacement. Ne supprime rien.
    func outOfRangeVelvetItems(for track: AudioFile, newDuration: Double) -> [String] {
        var items: [String] = []
        let trim = effectiveTrim(for: track)
        if trim.end > 0, trim.end > newDuration {
            items.append("Trim end: \(Self.formatSeconds(trim.end)) > duration \(Self.formatSeconds(newDuration))")
        }
        for cue in cuePoints(for: track) where cue.time > newDuration {
            items.append("Cue \"\(cue.name)\" at \(Self.formatSeconds(cue.time))")
        }
        for memo in editableMemos(for: track) where memo.memoTime > newDuration {
            items.append("Memo \"\(memo.displayTitle)\" at \(Self.formatSeconds(memo.memoTime))")
        }
        return items
    }

    /// Invalide l'entrée de cache URL for un song donné.
    func invalidateAudioURLCache(for track: AudioFile) {
        audioURLCache[track.audioFileID] = nil
        unresolvedAudioIDs.remove(track.audioFileID)
    }

    // MARK: - Helpers audio privés

    private static func backupTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm"
        return f.string(from: Date())
    }

    private static func formatSeconds(_ s: Double) -> String {
        let m = Int(s) / 60
        let sec = Int(s) % 60
        return String(format: "%d:%02d", m, sec)
    }

    /// Retourne une URL qui n'existe pas encore dans `directory`.
    /// Essaye "base (2).ext", "base (3).ext"... jusqu'à trouver un nom libre.
    private func uniqueDestinationURL(base destURL: URL, in directory: URL) -> URL {
        let fm = FileManager.default
        let ext  = destURL.pathExtension
        let name = destURL.deletingPathExtension().lastPathComponent
        var counter = 2
        var candidate = destURL
        while fm.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(name) (\(counter))" : "\(name) (\(counter)).\(ext)"
            candidate = directory.appendingPathComponent(newName)
            counter += 1
        }
        return candidate
    }

    /// Errors spécifiques aux opérations de fichiers audio.
    enum AudioFileError: LocalizedError {
        case noMediaFolder
        case mediaFolderAccessExpired
        case fileNotFound
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .noMediaFolder:
                return "MediaFiles folder is not configured. Go to Preferences → Media Folder."
            case .mediaFolderAccessExpired:
                return "Audio folder: access expired; reselect the folder in Settings."
            case .fileNotFound:
                return "Audio file not found for this song."
            case .writeFailed(let msg):
                return "Write failed: \(msg)"
            }
        }
    }

    // MARK: - Categories (Track Library)

    /// Categories de Track Library, construites une seule fois at l'import.
    /// La sélection d'un song ne doit pas retrier toute la bibliothèque.
    private(set) var categories: [TrackCategory] = []

    private static func buildCategories(from audioFiles: [AudioFile]) -> [TrackCategory] {
        let groups = Dictionary(grouping: audioFiles) {
            Self.category(for: $0.path)
        }
        return groups
            .map { (name, tracks) in
                TrackCategory(
                    name: name,
                    tracks: tracks.sorted { ($0.name ?? "") < ($1.name ?? "") }
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Extrait un nom de catégorie depuis un Path. On prend le dernier
    /// composant du dossier parent (ex. "/.../Setlist 2024/song.mp3" →
    /// "Setlist 2024"). Robuste aux paths vides ou nils.
    /// Retourne l'identifiant de la catégorie contenant `track`.
    /// Utilisé for synchroniser la sélection sidebar lors d'un clic
    /// depuis les résultats de recherche.
    func categoryID(for track: AudioFile) -> TrackCategory.ID {
        Self.category(for: track.path)
    }

    /// Bascule en mode Track Library et sélectionne le song donné.
    /// N'affecte pas la lecture, la queue, l'état joué ni l'AudioEngine.
    func openInTrackLibrary(_ track: AudioFile) {
        selectedCategoryID  = categoryID(for: track)
        selectedAudioFileID = track.audioFileID
        mode                = .trackLibrary
    }

    private static func category(for path: String?) -> String {
        guard let path, !path.isEmpty else { return "Uncategorized" }
        let parent = (path as NSString).deletingLastPathComponent
        let name = (parent as NSString).lastPathComponent
        return name.isEmpty ? "Uncategorized" : name
    }

    func concertGenre(for song: Song) -> ConcertGenre {
        guard let audio = song.audio else { return .other }
        return concertGenre(for: audio)
    }

    /// Variante utilisée par les vues qui n'ont pas de `Song` agrégé sous
    /// la main (Track Library, Quick Library) — on déduit directement du
    /// path du fichier audio.
    func concertGenre(for audio: AudioFile) -> ConcertGenre {
        if let velvet = velvetTrack(for: audio) {
            let source = velvet.genre.lowercased()
            if source.contains("rock") { return .rock }
            if source.contains("disco") { return .disco }
            if source.contains("electro") || source.contains("dance") { return .electro }
            if source.contains("funk") { return .funk }
            if source.contains("lounge") { return .lounge }
            if source.contains("jazz") { return .jazz }
            if source.contains("sax") { return .sax }
            if source.contains("ambiance") { return .ambiance }
            return .other
        }
        let source = Self.category(for: audio.path).lowercased()
        if source.contains("rock") { return .rock }
        if source.contains("disco") { return .disco }
        if source.contains("electro") || source.contains("dance") { return .electro }
        if source.contains("funk") { return .funk }
        if source.contains("lounge") { return .lounge }
        if source.contains("jazz") { return .jazz }
        if source.contains("sax") { return .sax }
        if source.contains("ambiance") { return .ambiance }
        return .other
    }

    // MARK: - Gestionnaire centralisé des couleurs de styles
    //
    // Source de vérité unique. Toute vue qui affiche une couleur liée à
    // un genre — Track Library, Quick Library, Setlist, Queue, Éditeur,
    // Cartouches, Historique — doit appeler `color(for:)` plutôt que
    // d'avoir sa propre palette. Persiste via `VelvetShowStore`.

    /// Color effective d'un genre : override utilisateur si présent,
    /// sinon couleur par défaut définie sur `ConcertGenre.defaultColorHex`.
    func color(for genre: ConcertGenre) -> Color {
        Color(hex: hex(for: genre))
    }

    /// Color effective associée au genre d'un song.
    /// Si `inSet` est fourni, la couleur locale au show est prioritaire.
    func color(for song: Song, inSet set: ShowSet? = nil) -> Color {
        if let audio = song.audio {
            // 1. Color locale au show (prioritaire dans la Show Library)
            if let set, let hex = songColorsByShowID[set.setID]?[audio.audioFileID] {
                return Color(hex: hex)
            }
            // 2. Color globale du song (Track Library)
            return color(for: audio)
        }
        return color(for: concertGenre(for: song))
    }

    /// Color effective associée at un AudioFile.
    /// Priorité : couleur individuelle Velvet > couleur VelvetTrack > genre perso > genre prédéfini.
    func color(for audio: AudioFile) -> Color {
        if let hex = trackColorsByAudioFileID[audio.audioFileID] {
            return Color(hex: hex)
        }
        if let hex = velvetTrack(for: audio)?.colorHex {
            return Color(hex: hex)
        }
        if let velvet = velvetTrack(for: audio) {
            let key = velvet.genre.lowercased().trimmingCharacters(in: .whitespaces)
            if let hex = customGenreColors[key] {
                return Color(hex: hex)
            }
        }
        return color(for: concertGenre(for: audio))
    }

    func setTrackColor(_ color: Color, for track: AudioFile) {
        trackColorsByAudioFileID[track.audioFileID] = color.hexComponents
    }

    func resetTrackColor(for track: AudioFile) {
        trackColorsByAudioFileID.removeValue(forKey: track.audioFileID)
    }

    func hasCustomTrackColor(for track: AudioFile) -> Bool {
        trackColorsByAudioFileID[track.audioFileID] != nil
    }

    // MARK: Genres personnalisés

    /// Noms des genres perso (lowercase keys → affichés capitalisés).
    var customGenreNames: [String] {
        customGenreColors.keys.sorted()
    }

    func colorForCustomGenre(_ name: String) -> Color {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        return Color(hex: customGenreColors[key] ?? 0x888888)
    }

    func setCustomGenreColor(_ color: Color, for name: String) {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        customGenreColors[key] = color.hexComponents
    }

    func deleteCustomGenre(_ name: String) {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        customGenreColors.removeValue(forKey: key)
    }

    /// Applique un genre (prédéfini ou perso) au VelvetTrack d'un song.
    func setGenre(_ genreName: String, for track: AudioFile) {
        guard let index = velvetTracks.firstIndex(where: { $0.id == track.audioFileID }) else { return }
        velvetTracks[index].genre = genreName.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Colors locales au show

    /// Color locale at un show for un song donné. Nil = utiliser la couleur globale.
    func showSongColor(forAudioFileID audioFileID: Int64, in set: ShowSet) -> Color? {
        guard let hex = songColorsByShowID[set.setID]?[audioFileID] else { return nil }
        return Color(hex: hex)
    }

    /// Définit la couleur locale at un show for un song.
    func setShowSongColor(_ color: Color, forAudioFileID audioFileID: Int64, in set: ShowSet) {
        if songColorsByShowID[set.setID] == nil { songColorsByShowID[set.setID] = [:] }
        songColorsByShowID[set.setID]![audioFileID] = color.hexComponents
    }

    /// Supprime la couleur locale au show — revient at la couleur globale.
    func resetShowSongColor(forAudioFileID audioFileID: Int64, in set: ShowSet) {
        songColorsByShowID[set.setID]?.removeValue(forKey: audioFileID)
    }

    /// Indique si une couleur locale au show existe for ce song.
    func hasShowSongColor(forAudioFileID audioFileID: Int64, in set: ShowSet) -> Bool {
        songColorsByShowID[set.setID]?[audioFileID] != nil
    }

    /// Valeur hex effective — utilisée par le ColorPicker du panneau
    /// "Styles & Colors" for seed le picker at la couleur courante.
    func hex(for genre: ConcertGenre) -> UInt32 {
        genreColors[genre] ?? genre.defaultColorHex
    }

    /// Met at jour la couleur d'un genre. Sauvegarde déclenchée
    /// automatiquement par le `didSet` de `genreColors`.
    func setColor(_ color: Color, for genre: ConcertGenre) {
        genreColors[genre] = color.hexComponents
    }

    /// Restaure la couleur par défaut for un genre précis.
    func resetColor(for genre: ConcertGenre) {
        genreColors[genre] = nil
    }

    /// Restaure toutes les couleurs par défaut — bouton "Réinitialiser"
    /// global du panneau "Styles & Colors".
    func resetAllColors() {
        genreColors = [:]
    }

    /// Nombre de songs détectés for un genre — affiché dans le
    /// panneau "Styles & Colors" for donner du contexte.
    func trackCount(for genre: ConcertGenre) -> Int {
        if genre == .all { return audioFiles.count }
        return audioFiles.reduce(0) { count, audio in
            count + (concertGenre(for: audio) == genre ? 1 : 0)
        }
    }

    // MARK: - Ouverture d'une base

    /// Ouvre la base SQLite et précharge tout ce dont l'UI a besoin.
    /// En cas d'erreur, l'erreur est convertie en message dans `lastError`.
    func open(url: URL) {
        do {
            // Sandbox macOS : il faut explicitement activer l'accès au
            // fichier choisi via NSOpenPanel (.fileImport).
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            // On charge tout dans des variables locales avant de toucher
            // l'état observable. Comme ça, si le fichier n'est pas la bonne
            // base ou si une table manque, l'UI ne se retrouve pas dans un
            // état at moitié imported.
            let db = try ShowBuddyDatabase(url: url)

            let loadedStats = db.loadStats()
            let loadedSets = try db.loadSets()
            let loadedAudioFiles = try db.loadAudioFiles().sorted {
                ($0.name ?? "") < ($1.name ?? "")
            }

            let shows = try db.loadLightShows()
            let loadedLightShowsByID = Dictionary(
                uniqueKeysWithValues: shows.map { ($0.lightShowID, $0) }
            )

            let events = try db.loadMidiEvents()
            let loadedMidiEventsByID = Dictionary(
                uniqueKeysWithValues: events.map { ($0.midiEventID, $0) }
            )

            var byAudio: [Int64: [LightShow]] = [:]
            for show in shows {
                guard let audioID = show.audioFileID else { continue }
                byAudio[audioID, default: []].append(show)
            }

            let memos = try db.loadShowMemos()
            var byShow: [Int64: [ShowMemo]] = [:]
            for memo in memos {
                guard let showID = memo.lightShowID else { continue }
                byShow[showID, default: []].append(memo)
            }

            let messages = try db.loadMidiMessages()
            var byEvent: [Int64: [MidiMessage]] = [:]
            for message in messages {
                guard let eventID = message.midiEventID else { continue }
                byEvent[eventID, default: []].append(message)
            }

            // Toutes les lectures ont réussi : on publie le nouvel état.
            self.database = db
            self.stats = loadedStats
            self.showBuddySets = loadedSets
            self.showBuddyAudioFiles = loadedAudioFiles
            self.rebuildAudioFileCaches()
            self.lightShowsByID = loadedLightShowsByID
            // Préserver les events natifs Velvet (IDs négatifs) lors du chargement DB.
            var mergedEvents = loadedMidiEventsByID
            var mergedMessages = byEvent
            for (id, event) in midiEventsByID where id < 0 { mergedEvents[id] = event }
            for (id, msgs) in midiMessagesByEventID where id < 0 { mergedMessages[id] = msgs }
            self.midiEventsByID = mergedEvents
            self.lightShowsByAudioFileID = byAudio
            self.memosByLightShowID = byShow
            self.midiMessagesByEventID = mergedMessages

            // Phase 1 — mettre at jour le cache métadonnées for chaque AudioFile chargé.
            self.updateAudioFileMetaCache(from: loadedAudioFiles)

            // Migration incrémentale des trims ShowBuddy → trimsByAudioFileID.
            // Exécutée une seule fois (flag hasImportedShowBuddyTrims).
            self.importShowBuddyTrims()

            // On repart d'un log vierge at chaque nouvelle base ouverte.
            self.midiLog = []

            // Sélections par défaut, for ne pas atterrir sur du vide.
            self.selectedSetID = self.sets.first?.id
            let firstCategory = self.categories.first
            self.selectedCategoryID = firstCategory?.id
            self.selectedAudioFileID = firstCategory?.tracks.first?.id
            self.lastError = nil
            detectMediaFolder(nextToDatabase: url)

        } catch {
            self.lastError = error.localizedDescription
        }
    }

    // MARK: - Relations utilisées par la fiche d'édition (Track Library)

    /// Tous les LightShows attachés at un song (souvent un seul).
    func lightShows(for audioFile: AudioFile) -> [LightShow] {
        lightShowsByAudioFileID[audioFile.audioFileID] ?? []
    }

    /// Tous les mémos rattachés at un song (via ses LightShows),
    /// triés chronologiquement par MemoTime.
    func memos(for audioFile: AudioFile) -> [ShowMemo] {
        lightShows(for: audioFile)
            .flatMap { memosByLightShowID[$0.lightShowID] ?? [] }
            .sorted { ($0.memoTime ?? 0) < ($1.memoTime ?? 0) }
    }

    /// Résout un `MidiEvent` at partir d'un identifiant éventuel
    /// (utilisé for les FK StartMidiEventID / EndMidiEventID des mémos).
    func midiEvent(id: Int64?) -> MidiEvent? {
        guard let id else { return nil }
        return midiEventsByID[id]
    }

    /// Messages MIDI rattachés at un événement (déjà triés par Time).
    func midiMessages(for event: MidiEvent) -> [MidiMessage] {
        midiMessagesByEventID[event.midiEventID] ?? []
    }

    // MARK: - Migration structurelle depuis ShowBuddy

    /// Résultat retourné at l'UI après migration.
    struct MigrationResult: Identifiable {
        let id = UUID()
        let tracksConverted: Int
        let showsConverted: Int
        let memosSeedées: Int
        let midiEventsConverted: Int
        let tracksConflicted: Int
        let showsConflicted: Int
        let backupURL: URL?
    }

    /// Aperçu des conflits avant migration : ne modifie rien.
    struct MigrationConflictPreview {
        let tracksToConvert: Int
        let showsToConvert: Int
        let tracksConflicted: Int
        let showsConflicted: Int
        var hasConflicts: Bool { tracksConflicted > 0 || showsConflicted > 0 }
    }

    func previewMigration() -> MigrationConflictPreview {
        let existingVelvetIDs = Set(velvetTracks.map(\.id))
        let existingShowIDs   = Set(velvetShows.map(\.id))
        let conflictedTracks  = showBuddyAudioFiles.filter { existingVelvetIDs.contains($0.audioFileID) }.count
        let conflictedShows   = showBuddySets.filter       { existingShowIDs.contains($0.setID) }.count
        return MigrationConflictPreview(
            tracksToConvert:   showBuddyAudioFiles.count - conflictedTracks,
            showsToConvert:    showBuddySets.count - conflictedShows,
            tracksConflicted:  conflictedTracks,
            showsConflicted:   conflictedShows
        )
    }

    /// Crée un backup daté de VelvetShowState.json.
    /// Retourne l'URL du backup créé, ou nil en cas d'échec.
    @discardableResult
    func backupVelvetShowState(tag: String = "") -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let ts     = formatter.string(from: Date())
        let suffix = tag.isEmpty ? ts : "\(ts)-\(tag)"
        let jsonURL = store.fileURL
        let bakURL  = jsonURL.deletingPathExtension().appendingPathExtension("\(suffix).bak")
        do {
            if FileManager.default.fileExists(atPath: bakURL.path) {
                try FileManager.default.removeItem(at: bakURL)
            }
            try FileManager.default.copyItem(at: jsonURL, to: bakURL)
            return bakURL
        } catch {
            print("[BACKUP] VelvetShowState backup failed: \(error)")
            return nil
        }
    }

    /// Copie la structure ShowBuddy dans VelvetShowState.json.
    /// ShowBuddy.db n'est jamais modifié. Les fichiers audio ne sont pas dupliqués —
    /// ils sont référencés par leur URL d'origine dans MediaFiles.
    @discardableResult
    func migrateFromShowBuddy() -> MigrationResult {
        guard let db = database else {
            return MigrationResult(tracksConverted: 0, showsConverted: 0, memosSeedées: 0,
                                   midiEventsConverted: 0, tracksConflicted: 0, showsConflicted: 0, backupURL: nil)
        }

        // ── 0. Backup daté avant toute modification ─────────────────────────
        let backupURL = backupVelvetShowState(tag: "pre-migration")
        print("[MIGRATION] Backup created: \(backupURL?.lastPathComponent ?? "failed")")

        var tracksConverted = 0
        var tracksConflicted = 0
        var memosSeedées = 0

        // ── 1. Songs → VelvetTrack ──────────────────────────────────────
        let existingVelvetIDs = Set(velvetTracks.map(\.id))
        var newTracks = velvetTracks

        for audioFile in showBuddyAudioFiles {
            guard !existingVelvetIDs.contains(audioFile.audioFileID) else {
                tracksConflicted += 1
                continue
            }

            // Résoudre l'URL : URL absolue existante si possible, sinon path brut ShowBuddy.
            let fileURL: URL
            if let resolved = resolvedAudioURL(for: audioFile) {
                fileURL = resolved
            } else if let rawPath = audioFile.path, !rawPath.isEmpty {
                fileURL = URL(fileURLWithPath: rawPath)
            } else {
                continue  // pas de chemin du tout → on ne peut pas créer un VelvetTrack
            }

            let tempo = lightShowsByAudioFileID[audioFile.audioFileID]?.first?.tempo
            let genre = concertGenre(for: audioFile).rawValue

            // Pré-seeder les mémos si pas encore édités dans Velvet.
            if editableMemosByAudioFileID[audioFile.audioFileID] == nil {
                let showMemoList = memos(for: audioFile)
                if !showMemoList.isEmpty {
                    let seeded = showMemoList.map { EditableMemo(showMemo: $0) }
                    editableMemosByAudioFileID[audioFile.audioFileID] = seeded
                    memosSeedées += seeded.count
                }
            }

            newTracks.append(VelvetTrack(
                id: audioFile.audioFileID,
                title: audioFile.name ?? "Untitled",
                genre: genre,
                note: audioFile.note ?? "",
                colorHex: trackColorsByAudioFileID[audioFile.audioFileID],
                tempo: tempo,
                fileURL: fileURL,
                duration: audioFile.lengthSecs
            ))
            tracksConverted += 1
        }
        // Vider showBuddyAudioFiles AVANT d'affecter velvetTracks :
        // velvetTracks.didSet appelle rebuildAudioFileCaches() immédiatement,
        // et les deux collections auraient les mêmes IDs → crash.
        showBuddyAudioFiles = []
        velvetTracks = newTracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        // ── 2. Sets → VelvetShow ────────────────────────────────────────────
        let existingShowIDs = Set(velvetShows.map(\.id))
        var newShows = velvetShows
        var showsConverted = 0
        var showsConflicted = 0

        for set in showBuddySets {
            guard !existingShowIDs.contains(set.setID) else {
                showsConflicted += 1
                continue
            }

            let elements = (try? db.loadSetElements(forSetID: set.setID)) ?? []
            let showTracks: [VelvetShowTrack] = elements.compactMap { element in
                guard let lightShow = lightShowsByID[element.lightShowID],
                      let audioID = lightShow.audioFileID,
                      audioFilesByID[audioID] != nil else { return nil }
                return VelvetShowTrack(
                    id: element.setElementID,
                    audioFileID: audioID,
                    playbackMode: element.autoStart == 1 ? .automatic : .manual
                )
            }

            newShows.append(VelvetShow(
                id: set.setID,
                name: set.name ?? "Untitled",
                note: set.note ?? "",
                colorHex: 0xC9A769,
                tracks: showTracks,
                folder: set.folder
            ))
            showsConverted += 1
        }
        velvetShows = newShows

        // ── 3. MIDI ─────────────────────────────────────────────────────────
        let allEvents  = Array(midiEventsByID.values).sorted { $0.midiEventID < $1.midiEventID }
        let allMessages = Array(midiMessagesByEventID.values.joined()).sorted { $0.midiMessageID < $1.midiMessageID }

        // ── 4. Valider la migration ─────────────────────────────────────────
        store.update {
            $0.hasMigratedFromShowBuddy = true
            $0.velvetMidiEvents  = allEvents
            $0.velvetMidiMessages = allMessages
        }

        // On peut désormais travailler sans la base — on la ferme proprement.
        self.database = nil
        self.showBuddySets = []
        checkAudioFileAccessibility()

        return MigrationResult(
            tracksConverted:     tracksConverted,
            showsConverted:      showsConverted,
            memosSeedées:        memosSeedées,
            midiEventsConverted: allEvents.count,
            tracksConflicted:    tracksConflicted,
            showsConflicted:     showsConflicted,
            backupURL:           backupURL
        )
    }

    // MARK: - Migration incrémentale des trims ShowBuddy

    /// Copie les `TrimStart`/`TrimEnd` depuis un dictionnaire `[Int64: [LightShow]]`
    /// to `trimsByAudioFileID`, uniquement for les songs sans trim Velvet.
    ///
    /// Règles :
    /// - Ne touche pas les trims Velvet existants (priorité préservée).
    /// - N'écrit rien dans ShowBuddy.db.
    /// - Pose `hasImportedShowBuddyTrims = true` et force une sauvegarde.
    /// - Retourne le nombre de trims nouvellement importeds.
    @discardableResult
    private func applyShowBuddyTrims(from byAudio: [Int64: [LightShow]]) -> Int {
        var count = 0

        for (audioFileID, lightShows) in byAudio {
            // Priorité absolue aux trims Velvet définis par l'utilisateur.
            guard trimsByAudioFileID[audioFileID] == nil else { continue }

            // Premier LightShow ayant au moins une borne non nulle.
            guard let lightShow = lightShows.first(where: {
                ($0.trimStart ?? 0) > 0 || ($0.trimEnd ?? 0) > 0
            }) else { continue }

            trimsByAudioFileID[audioFileID] = VelvetTrackTrim(
                audioFileID: audioFileID,
                trimStart: max(0, lightShow.trimStart ?? 0),
                trimEnd:   max(0, lightShow.trimEnd   ?? 0),
                updatedAt: Date()
            )
            count += 1
        }

        store.update { $0.hasImportedShowBuddyTrims = true }
        store.saveNow()

        print("[VELVET] importShowBuddyTrims · Migrated ShowBuddy trims: \(count) tracks")
        return count
    }

    /// Chemin automatique : appelé depuis `open(url:)` quand ShowBuddy.db vient
    /// d'être chargée et que `lightShowsByAudioFileID` est déjà peuplé.
    /// Ne fait rien si la migration one-shot a déjà eu lieu.
    func importShowBuddyTrims() {
        guard !store.state.hasImportedShowBuddyTrims else { return }
        guard !lightShowsByAudioFileID.isEmpty else {
            print("[VELVET] importShowBuddyTrims: lightShowsByAudioFileID empty; DB not loaded?")
            return
        }
        applyShowBuddyTrims(from: lightShowsByAudioFileID)
    }

    /// Chemin manuel : lit **uniquement** les LightShows du fichier ShowBuddy.db
    /// fourni, sans toucher aux mémos, MIDI, sets ou tracks.
    /// Utilisé par le bouton "Import les trims ShowBuddy" for les
    /// utilisateurs déjà migrés qui n'ouvrent plus ShowBuddy.db normalement.
    ///
    /// - Peut être relancé plusieurs fois : idempotent for les trims already presents.
    /// - Retourne le nombre de nouveaux trims importeds, 0 si rien at faire.
    @discardableResult
    func importShowBuddyTrimsFromURL(_ url: URL) throws -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        // Lecture minimale : on n'a besoin que des LightShows.
        let db = try ShowBuddyDatabase(url: url)
        let shows = try db.loadLightShows()

        var byAudio: [Int64: [LightShow]] = [:]
        for show in shows {
            guard let audioID = show.audioFileID else { continue }
            byAudio[audioID, default: []].append(show)
        }

        return applyShowBuddyTrims(from: byAudio)
    }

    // MARK: - Correction sémantique TrimEnd ShowBuddy

    /// Relit ShowBuddy.db depuis l'URL fournie et recalcule tous les trimEnd
    /// en appliquant la conversion correcte :
    ///
    ///   ShowBuddy.TrimEnd = secondes at supprimer depuis la FIN du song
    ///   velvetTrimEnd     = trackDuration - ShowBuddy.TrimEnd   (position absolue)
    ///   velvetTrimEnd     = 0 si ShowBuddy.TrimEnd == 0         (pas de tail trim)
    ///
    /// Seuls les audioFileIDs présents dans les LightShows ShowBuddy sont
    /// réécrits — les trims Velvet manuels (IDs absents de ShowBuddy) ne sont
    /// jamais touchés. Un backup `.fix.bak` est créé avant toute écriture.
    ///
    /// Retourne (fixed: nombre de trims recalculés, skipped: durée inconnue).
    @discardableResult
    func fixShowBuddyTrimsFromURL(_ url: URL) throws -> (fixed: Int, skipped: Int) {
        // ── Backup préventif ────────────────────────────────────────────────
        let jsonURL    = store.fileURL
        let fixBakURL  = jsonURL.deletingPathExtension().appendingPathExtension("fix.bak")
        try? FileManager.default.removeItem(at: fixBakURL)
        try? FileManager.default.copyItem(at: jsonURL, to: fixBakURL)
        print("[VELVET] fixShowBuddyTrims · backup → \(fixBakURL.lastPathComponent)")

        // ── Lecture ShowBuddy.db ────────────────────────────────────────────
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let db       = try ShowBuddyDatabase(url: url)
        let shows    = try db.loadLightShows()
        let audFiles = try db.loadAudioFiles()

        // Index durée réelle par audioFileID (depuis AudioFiles ShowBuddy).
        let durationByID: [Int64: Double] = Dictionary(
            uniqueKeysWithValues: audFiles.compactMap { af -> (Int64, Double)? in
                guard let len = af.lengthSecs, len > 0 else { return nil }
                return (af.audioFileID, len)
            }
        )

        // Regrouper LightShows par audioFileID.
        var byAudio: [Int64: [LightShow]] = [:]
        for show in shows {
            guard let aid = show.audioFileID else { continue }
            byAudio[aid, default: []].append(show)
        }

        var fixed   = 0
        var skipped = 0

        for (audioFileID, lightShows) in byAudio {
            guard let lightShow = lightShows.first else { continue }

            let rawStart = lightShow.trimStart ?? 0
            let rawEnd   = lightShow.trimEnd   ?? 0

            // Aucun trim ShowBuddy for ce song → supprimer un trim imported erroné.
            if rawStart == 0 && rawEnd == 0 {
                if trimsByAudioFileID[audioFileID] != nil {
                    trimsByAudioFileID.removeValue(forKey: audioFileID)
                    fixed += 1
                }
                continue
            }

            let trimStart = max(0.0, rawStart)

            // Conversion TrimEnd tail-offset → position absolue.
            let trimEnd: Double
            if rawEnd == 0 {
                // Pas de tail trim : AudioEngine lit jusqu'à la vraie fin. ✅
                trimEnd = 0
            } else if let dur = durationByID[audioFileID], dur > 0 {
                let absEnd = dur - rawEnd
                // Valider : l'end doit être strictement après le start.
                trimEnd = absEnd > trimStart ? absEnd : 0
            } else {
                // Duration inconnue → conversion impossible, on conserve l'existant.
                skipped += 1
                continue
            }

            // Ne pas stocker de trim vide (start=0, end=0) : inutile.
            if trimStart == 0 && trimEnd == 0 {
                trimsByAudioFileID.removeValue(forKey: audioFileID)
                fixed += 1
                continue
            }

            let before = trimsByAudioFileID[audioFileID]
            trimsByAudioFileID[audioFileID] = VelvetTrackTrim(
                audioFileID: audioFileID,
                trimStart:   trimStart,
                trimEnd:     trimEnd,
                updatedAt:   Date()
            )

            let bStart = before?.trimStart ?? -1
            let bEnd   = before?.trimEnd   ?? -1
            if abs(bStart - trimStart) > 0.01 || abs(bEnd - trimEnd) > 0.01 {
                fixed += 1
            }
        }

        store.saveNow()

        print("""
        [VELVET] fixShowBuddyTrims · résultat :
          • trims recalculés : \(fixed)
          • trims skippeds (unknown duration) : \(skipped)
          • total trims en mémoire : \(trimsByAudioFileID.count)
        """)
        return (fixed, skipped)
    }

    func maestroMidiEvents() -> [MidiEvent] {
        midiEventsByID.values
            .filter { event in
                !archivedMidiEventIDs.contains(event.midiEventID)
                && midiMessages(for: event).contains { $0.maestroDescription != nil }
            }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    // MARK: - Archivage MIDI (visibilité uniquement)

    func isArchived(_ eventID: Int64) -> Bool {
        archivedMidiEventIDs.contains(eventID)
    }

    func archiveMidiEvent(_ eventID: Int64) {
        archivedMidiEventIDs.insert(eventID)
    }

    func unarchiveMidiEvent(_ eventID: Int64) {
        archivedMidiEventIDs.remove(eventID)
    }

    // MARK: - End Behavior

    func endBehavior(for song: Song, in set: ShowSet) -> TrackEndBehavior {
        if isVelvetShow(set) {
            return velvetShow(for: set)?
                .tracks.first(where: { $0.id == song.element.setElementID })?
                .endBehavior ?? .autoStop
        } else {
            return endBehaviorBySetElementID[song.element.setElementID] ?? .autoStop
        }
    }

    func setEndBehavior(_ behavior: TrackEndBehavior, for song: Song, in set: ShowSet) {
        if isVelvetShow(set) {
            guard let si = velvetShows.firstIndex(where: { $0.id == set.setID }),
                  let ti = velvetShows[si].tracks.firstIndex(where: { $0.id == song.element.setElementID })
            else { return }
            velvetShows[si].tracks[ti].endBehavior = behavior
        } else {
            endBehaviorBySetElementID[song.element.setElementID] = behavior
        }
    }

    private func nextSong(after elementID: SetElement.ID, in set: ShowSet) -> Song? {
        let all = songs(in: set)
        guard let idx = all.firstIndex(where: { $0.element.setElementID == elementID }) else { return nil }
        let next = all.index(after: idx)
        guard next < all.endIndex else { return nil }
        return all[next]
    }

    /// Déclenchement anticipatoire de l'Auto Next (appelé par le scheduler MIDI).
    /// Calcule le temps restant et démarre `startReplacement` si on entre dans
    /// la fenêtre de crossfade — avant que le moteur ne s'arrête naturellement.
    private func tickAutoNext() {
        guard audioEngine.state == .playing, !isReplacingTrack else { return }
        guard let setID = currentlyLoadedSetID,
              let elementID = currentlyLoadedSetElementID,
              let set = sets.first(where: { $0.setID == setID }) else { return }

        // La queue est prioritaire sur l'Auto Next.
        if let q = concertQueueBySetID[setID], !q.isEmpty { return }

        let allSongs = songs(in: set)
        guard let currentSong = allSongs.first(where: { $0.element.setElementID == elementID }) else { return }

        let triggerEffect: TransitionEffect
        switch endBehavior(for: currentSong, in: set) {
        case .autoStop, .smart:
            guard isAutoShowEnabled else { return }
            triggerEffect = .filter
        case .autoNextFade, .autoNextSlowFade: return
        case .autoNextFilter: triggerEffect = .filter
        }

        guard audioEngine.effectiveRemaining <= triggerEffect.fadeOutDuration + 0.1 else { return }

        guard let next = nextSong(after: elementID, in: set),
              let nextTrack = next.audio else { return }

        startReplacement(track: nextTrack, set: set, element: next.element, effect: triggerEffect)
    }

    // MARK: - Scheduler MIDI Timeline

    /// Démarre la boucle de polling du scheduler MIDI (50 ms).
    /// Appelé at chaque `startPlayback`. La boucle se relance aussi si déjà
    /// active (annule la précédente), ce qui couvre les changements de song.
    private func startMidiScheduler() {
        midiSchedulerTask?.cancel()
        midiSchedulerTask = nil
        lastSchedulerPos = nil
        midiSchedulerGeneration &+= 1
        let gen = midiSchedulerGeneration
        midiSchedulerTask = Task { @MainActor [weak self] in
            var firstTick = true
            while !Task.isCancelled {
                // Génération divergente = cette task est orpheline (une autre
                // session MIDI a démarré). On sort sans envoyer de MIDI.
                guard let self, self.midiSchedulerGeneration == gen else { return }
                self.tickMidiScheduler(logFirstTick: firstTick)
                self.tickAutoNext()
                firstTick = false
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// Un tick du scheduler : vérifie la position courante et déclenche
    /// les MIDI events associés aux mémos franchis.
    ///
    /// Position : `livePosition` (CACurrentMediaTime en ligne) plutôt que
    /// `currentPosition` (cache UI at 30 Hz). Staleness 0 ms, fiable sous
    /// HALC overload.
    ///
    /// Pre-arm (première tick uniquement) : déclenche immédiatement tous
    /// les triggers dont `memoTime <= livePosition + 0.25s`. Élimine le
    /// retard structurel for les mémos placés en début de song (0–250 ms).
    private func tickMidiScheduler(logFirstTick: Bool = false) {
        guard audioEngine.state == .playing else { return }
        // Pendant un crossfade, le scheduler suit le song ENTRANT
        // (pendingCrossfadeTrack) sur sa propre position — sinon les mémos
        // du début du nouveau song partiraient 1 at 3 s trop tard, en
        // rafale at la fin du fade. Après finishCrossfade, currentlyLoadedTrack
        // devient ce même song et livePosition continue at la même
        // position absolue : la bascule est transparente, firedMidiTriggers
        // reste valide.
        let track: AudioFile
        let pos: TimeInterval
        if let pending = pendingCrossfadeTrack,
           let xfadePos = audioEngine.crossfadeIncomingLivePosition {
            track = pending
            pos = xfadePos
        } else if let loaded = currentlyLoadedTrack {
            track = loaded
            pos = audioEngine.livePosition
        } else {
            return
        }
        let memos = editableMemos(for: track)

        // Réalignement de `firedMidiTriggers` sur la position courante.
        //
        // Deux déclencheurs :
        //   A) Première tick d'une nouvelle instance de scheduler
        //      (`lastSchedulerPos == nil`) : on n'a aucun historique et
        //      `firedMidiTriggers` peut contenir des entrées périmées
        //      (ex. Pause → seek arrière pendant la pause → Resume — le
        //      Resume relance le scheduler sans toucher au set).
        //   B) Saut significatif détecté pendant la lecture
        //      (delta > seuil) : seek avant/arrière live, return to
        //      beginning, etc.
        //
        // Dans les deux cas, on reconstruit le set depuis zéro :
        //   • cues at time ≤ pos → marquées comme déjà tirées (pas de
        //     déclenchement rétroactif après un seek avant) ;
        //   • cues at time >  pos → réarmées (re-déclenchables au
        //     prochain franchissement, ex. après retour au début).
        let isFirstTickRealign = (lastSchedulerPos == nil)
        var didRealign = isFirstTickRealign
        var seekKind = isFirstTickRealign ? "first-tick" : "none"
        if let lastPos = lastSchedulerPos {
            let delta = pos - lastPos
            if delta < -Self.seekDetectionThreshold {
                didRealign = true
                seekKind   = "backward"
            } else if delta > Self.seekDetectionThreshold {
                didRealign = true
                seekKind   = "forward"
            }
        }
        if didRealign {
            print("[SCHED] tick pos=\(String(format: "%.3f", pos))s  lastPos=\(lastSchedulerPos.map { String(format: "%.3f", $0) } ?? "nil")  seek=\(seekKind)  fired-before=\(firedMidiTriggers.count)")
            realignFiredTriggers(for: track, at: pos, memos: memos)
            print("[SCHED] tick pos=\(String(format: "%.3f", pos))s  realign done  fired-after=\(firedMidiTriggers.count)")
        }
        lastSchedulerPos = pos

        // Offset MIDI global : −200 ms stocké → tir 200 ms en avance.
        // S'applique uniquement at la comparaison, jamais aux données.
        let midiLead = Double(-midiGlobalOffsetMillis) / 1000.0
        let firePos = pos + midiLead

        // Window de pre-arm : 0.25 s at partir de la position de tir,
        // uniquement sur la première tick de la session.
        let preArmHorizon: TimeInterval = logFirstTick ? firePos + 0.25 : firePos

        if logFirstTick {
            let midiMemos = memos.filter { $0.startMidiEventID != nil || $0.endMidiEventID != nil }
            let next = midiMemos.first(where: { $0.memoTime > preArmHorizon })
            print("""
            [MIDI] scheduler démarré — \(track.name ?? "?")
              • pos=\(String(format: "%.2f", pos))s  preArm≤\(String(format: "%.2f", preArmHorizon))s  firedTriggers=\(firedMidiTriggers.count)
              • MIDI memos: \(midiMemos.count)  next after pre-arm: \(next.map { "\($0.shortName) @ \(String(format: "%.2f", $0.memoTime))s" } ?? "none")
            """)
        }

        for memo in memos {
            // ── Start trigger ────────────────────────────────────────
            if let eventID = memo.startMidiEventID {
                let key = "\(memo.id)-start"
                // Sur la première tick, on utilise preArmHorizon (pos+0.25s)
                // for déclencher immédiatement les mémos proches du début.
                if !firedMidiTriggers.contains(key) && preArmHorizon >= memo.memoTime {
                    firedMidiTriggers.insert(key)
                    if let event = midiEventsByID[eventID] {
                        let prefix = logFirstTick && memo.memoTime > pos ? "[MIDI] PRE-ARM START" : "[MIDI] AUTO START MEMO"
                        print("\(prefix) · \(track.name ?? "?") · \(memo.shortName) · event \(eventID) · \(event.name ?? "?")")
                        dispatch(event: event)
                    }
                }
            }
            // ── End trigger ──────────────────────────────────────────
            if let eventID = memo.endMidiEventID {
                let key = "\(memo.id)-end"
                let endTime = memo.memoTime + memo.memoLength
                if !firedMidiTriggers.contains(key) && preArmHorizon >= endTime {
                    firedMidiTriggers.insert(key)
                    if let event = midiEventsByID[eventID] {
                        let prefix = logFirstTick && endTime > pos ? "[MIDI] PRE-ARM END" : "[MIDI] AUTO END MEMO"
                        print("\(prefix) · \(track.name ?? "?") · \(memo.shortName) · event \(eventID) · \(event.name ?? "?")")
                        dispatch(event: event)
                    }
                }
            }
        }

        // ── Boucle 2 : TimelineMidiCue ────────────────────────────────────────
        // Même firePos et même firedMidiTriggers que la boucle mémos.
        // Clé de déduplication : "\(cue.id)-midicue" (distinct des clés mémos).
        for cue in midiCues(for: track) {
            let key = "\(cue.id)-midicue"
            if !firedMidiTriggers.contains(key) && preArmHorizon >= cue.time {
                firedMidiTriggers.insert(key)
                if let event = midiEventsByID[cue.midiEventID] {
                    let prefix = logFirstTick && cue.time > pos ? "[MIDI] PRE-ARM MIDICUE" : "[MIDI] AUTO MIDICUE"
                    let displayLabel = cue.label.isEmpty ? event.name ?? "?" : cue.label
                    print("\(prefix) · \(track.name ?? "?") · \(displayLabel) @ \(String(format: "%.2f", cue.time))s · event \(cue.midiEventID)")
                    dispatch(event: event)
                }
            }
        }

        // ── Boucle 3 : TimelineOscCue ─────────────────────────────────────────
        // Même mécanique, clé de déduplication "\(cue.id)-osccue".
        for cue in oscCues(for: track) {
            let key = "\(cue.id)-osccue"
            let already = firedMidiTriggers.contains(key)
            let due     = preArmHorizon >= cue.time
            let resolvedName: String = {
                if !cue.label.isEmpty { return cue.label }
                if let eid = cue.oscEventID, let e = oscEventsByID[eid] { return e.name }
                return "(no event)"
            }()
            if !already && due {
                firedMidiTriggers.insert(key)
                let prefix = logFirstTick && cue.time > pos ? "[OSC] PRE-ARM OSCCUE" : "[OSC] FIRE OSCCUE"
                let routing: String = {
                    if let eid = cue.oscEventID, let e = oscEventsByID[eid] {
                        return "→ \(e.host):\(e.port) \(e.address)"
                    } else {
                        return "(no event linked — will be skipped at dispatch)"
                    }
                }()
                print("\(prefix) · \(track.name ?? "?") · \(resolvedName) @ \(String(format: "%.2f", cue.time))s  pos=\(String(format: "%.3f", pos))s  preArm=\(String(format: "%.3f", preArmHorizon))s  \(routing)")
                dispatch(oscCue: cue)
            } else if already && due && didRealign {
                print("[OSC] SKIP OSCCUE (already past) · \(resolvedName) @ \(String(format: "%.2f", cue.time))s  pos=\(String(format: "%.3f", pos))s")
            } else if !already && !due && didRealign {
                print("[OSC] ARM  OSCCUE (future)      · \(resolvedName) @ \(String(format: "%.2f", cue.time))s  pos=\(String(format: "%.3f", pos))s")
            }
        }
    }

    /// Recalcule `firedMidiTriggers` après un seek détecté ou au démarrage
    /// d'une nouvelle instance de scheduler. Pour chaque cue du morceau, on
    /// insère sa clé si `cue.time ≤ pos` (déjà franchie → ne doit pas se
    /// redéclencher tant qu'on n'est pas revenu en arrière), et on l'omet
    /// sinon (réarmée). Couvre mémos start/end, MIDI cues et OSC cues —
    /// un seul ensemble partagé, un seul passage.
    private func realignFiredTriggers(
        for track: AudioFile,
        at pos: TimeInterval,
        memos: [EditableMemo]
    ) {
        var aligned: Set<String> = []
        for memo in memos {
            if memo.startMidiEventID != nil, memo.memoTime <= pos {
                aligned.insert("\(memo.id)-start")
            }
            if memo.endMidiEventID != nil,
               memo.memoTime + memo.memoLength <= pos {
                aligned.insert("\(memo.id)-end")
            }
        }
        for cue in midiCues(for: track) where cue.time <= pos {
            aligned.insert("\(cue.id)-midicue")
        }
        for cue in oscCues(for: track) where cue.time <= pos {
            aligned.insert("\(cue.id)-osccue")
        }
        let removed = firedMidiTriggers.subtracting(aligned)
        let added   = aligned.subtracting(firedMidiTriggers)
        firedMidiTriggers = aligned
        if !removed.isEmpty {
            print("[SCHED] realign removed (= re-armed) \(removed.count) trigger(s): \(removed.sorted().joined(separator: ", "))")
        }
        if !added.isEmpty {
            print("[SCHED] realign added (= marked past) \(added.count) trigger(s): \(added.sorted().joined(separator: ", "))")
        }
    }

    // MARK: - Dispatch MIDI
    //
    // `dispatch(event:)` est le point d'entrée unique for déclencher
    // un MidiEvent. Il :
    //   1) écrit TOUJOURS une ligne par message dans `midiLog`,
    //   2) envoie via CoreMIDI tout message avec un status byte valide,
    //      quelle que soit sa nature (MaestroDMX, QLab, Ableton, etc.),
    //      to la destination configurée.
    //      Si aucune destination n'est configurée, le log l'indique clairement.

    /// Déclenche un événement MIDI : log systématique + envoi CoreMIDI universel.
    func dispatch(event: MidiEvent) {
        lastDispatchedEventName = event.name
        let messages = midiMessages(for: event)
        let now = Date()
        let header = "Event \"\(event.name ?? "?")\""
            + (event.category.map { " [\($0)]" } ?? "")

        print("[MIDI] DISPATCH event \(event.midiEventID) \"\(event.name ?? "?")\" — \(messages.count) message(s)")

        if messages.isEmpty {
            print("[MIDI] DISPATCH ⚠ no message in midiMessagesByEventID[\(event.midiEventID)]")
            midiLog.append(MidiLogEntry(
                timestamp: now,
                text: "\(header) — no MIDI message to send"
            ))
            return
        }

        // Résolution unique de la destination for tout l'event.
        let dest = maestroDestination
        var hasMaestroMessage = false

        for message in messages {
            // Description enrichie : brut MIDI + suffixe MaestroDMX si applicable.
            let base = message.humanDescription
            let humanFull = message.maestroDescription
                .map { "\(base) — MaestroDMX : \($0)" } ?? base

            // Suivi de la scène active MaestroDMX (inchangé).
            if message.maestroDescription != nil { hasMaestroMessage = true }

            // Ignorer les messages sans status byte (données corrompues).
            guard let statusByte = message.message else {
                print("[MIDI] DISPATCH ⚠ SKIPPED: status byte nil  ch=\(message.channel?.description ?? "?") d1=\(message.data1?.description ?? "?") d2=\(message.data2?.description ?? "?")")
                midiLog.append(MidiLogEntry(
                    timestamp: now,
                    text: "SKIPPED (no status byte): \(humanFull)"
                ))
                continue
            }

            let destName = dest.map { $0.displayName } ?? "AUCUNE"
            print("[MIDI] SEND  status=\(statusByte)  ch=\(message.channel.map { $0 + 1 } ?? 0)  d1=\(message.data1 ?? 0)  d2=\(message.data2?.description ?? "-")  → \(destName)")

            let prefix: String
            if let d = dest {
                do {
                    try midiEngine.send(message: message, to: d)
                    prefix = "ENVOI     "
                    print("[MIDI] SEND OK")
                } catch {
                    prefix = "SEND FAILED (\(error.localizedDescription))"
                    print("[MIDI] SEND FAILED — \(error.localizedDescription)")
                }
            } else {
                prefix = "SANS DESTINATION"
                print("[MIDI] SEND ⚠ SANS DESTINATION — message non transmis")
            }

            midiLog.append(MidiLogEntry(
                timestamp: now,
                text: "\(prefix) : \(humanFull)"
            ))
        }

        // Met at jour la scène active si l'event contenait des messages Maestro.
        if hasMaestroMessage {
            lastDispatchedMaestroEventID = event.midiEventID
        }
    }

    /// Vide le journal — bouton "Effacer le log" côté UI.
    func clearMidiLog() {
        midiLog.removeAll()
    }

    // MARK: - Dispatch OSC

    /// Déclenche un cue OSC : résout l'`OscEvent` lié, logue, envoie via UDP.
    /// Pendant du `dispatch(event:)` côté MIDI — totalement indépendant.
    func dispatch(oscCue cue: TimelineOscCue) {
        let now = Date()
        guard let eventID = cue.oscEventID, let event = oscEventsByID[eventID] else {
            let info = cue.label.isEmpty ? "(unnamed cue)" : cue.label
            print("[OSC] DISPATCH ⚠ no OscEvent linked to cue \(cue.id) — \(info)")
            midiLog.append(MidiLogEntry(
                timestamp: now,
                text: "OSC SKIPPED (no event linked) — \(info)"
            ))
            return
        }
        dispatch(oscEvent: event, sourceLabel: cue.label.isEmpty ? event.name : cue.label)
    }

    /// Envoie un OscEvent nommé. Utilisé par dispatch(oscCue:) et par la
    /// section Library (bouton « Test » par event).
    func dispatch(oscEvent event: OscEvent, sourceLabel: String? = nil) {
        let now = Date()
        let valueDesc = event.value?.displayValue ?? "(no value)"
        let header = "OSC \"\(event.name)\" → \(event.host):\(event.port) \(event.address) \(valueDesc)"
        do {
            try oscEngine.send(
                address: event.address,
                value:   event.value,
                host:    event.host,
                port:    event.port
            )
            print("[OSC] SEND OK — \(header)")
            midiLog.append(MidiLogEntry(
                timestamp: now,
                text: "ENVOI     : \(header)"
            ))
        } catch {
            print("[OSC] SEND FAILED — \(error.localizedDescription) — \(header)")
            midiLog.append(MidiLogEntry(
                timestamp: now,
                text: "SEND FAILED (\(error.localizedDescription)) : \(header)"
            ))
        }
        _ = sourceLabel  // future-proof: enrichir le log si besoin
    }

    /// Test brut depuis Settings → OscTestSection (saisie libre host/port/addr).
    /// Pas de passage par la Library — utile pour QLab/Companion/Protokol.
    func sendTestOSC(
        host: String,
        port: Int,
        address: String,
        value: OSCValue?
    ) {
        let now = Date()
        let header = "OSC TEST → \(host):\(port) \(address) \(value?.displayValue ?? "(no value)")"
        do {
            try oscEngine.send(address: address, value: value, host: host, port: port)
            print("[OSC] SEND OK — \(header)")
            midiLog.append(MidiLogEntry(timestamp: now, text: "ENVOI     : \(header)"))
        } catch {
            print("[OSC] SEND FAILED — \(error.localizedDescription) — \(header)")
            midiLog.append(MidiLogEntry(timestamp: now, text: "SEND FAILED (\(error.localizedDescription)) : \(header)"))
        }
    }

    // MARK: - Audit d'usage MIDI

    struct MidiEventUsage {
        let memoStartCount: Int
        let memoEndCount:   Int
        let timelineCueCount: Int
        let isRestCue: Bool

        var isUsed: Bool { memoStartCount + memoEndCount + timelineCueCount > 0 || isRestCue }

        var description: String {
            var parts: [String] = []
            let total = memoStartCount + memoEndCount
            if total > 0 { parts.append("\(total) memo\(total > 1 ? "s" : "")") }
            if timelineCueCount > 0 { parts.append("\(timelineCueCount) cue\(timelineCueCount > 1 ? "s" : "") timeline") }
            if isRestCue { parts.append("cue de repos") }
            return parts.isEmpty ? "Unused" : parts.joined(separator: ", ")
        }
    }

    func midiEventUsage(for eventID: Int64) -> MidiEventUsage {
        var memoStart = 0
        var memoEnd   = 0
        for memos in editableMemosByAudioFileID.values {
            for memo in memos {
                if memo.startMidiEventID == eventID { memoStart += 1 }
                if memo.endMidiEventID   == eventID { memoEnd   += 1 }
            }
        }
        let cues = midiCuesByAudioFileID.values.reduce(0) { acc, list in
            acc + list.filter { $0.midiEventID == eventID }.count
        }
        return MidiEventUsage(
            memoStartCount:   memoStart,
            memoEndCount:     memoEnd,
            timelineCueCount: cues,
            isRestCue:        restCueMidiEventID == eventID
        )
    }

    // MARK: - Éditeur MIDI natif Velvet

    private func nextVelvetMidiEventID() -> Int64 {
        let candidate = min(-1, (midiEventsByID.keys.filter { $0 < 0 }.min() ?? 0) - 1)
        if DemoIDRange.events.contains(candidate) { return DemoIDRange.events.lowerBound - 1 }
        return candidate
    }

    private func nextVelvetMidiMessageID() -> Int64 {
        let allIDs = midiMessagesByEventID.values.joined().map(\.midiMessageID)
        return min(-1, (allIDs.filter { $0 < 0 }.min() ?? 0) - 1)
    }

    func createVelvetMidiEvent(name: String) {
        let id = nextVelvetMidiEventID()
        midiEventsByID[id] = MidiEvent(midiEventID: id, name: name.isEmpty ? "New Event" : name, category: nil)
        persistNativeVelvetMidi()
    }

    func renameVelvetMidiEvent(_ event: MidiEvent, to name: String) {
        guard event.midiEventID < 0, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        midiEventsByID[event.midiEventID] = MidiEvent(midiEventID: event.midiEventID, name: name, category: event.category)
        persistNativeVelvetMidi()
    }

    func deleteVelvetMidiEvent(_ event: MidiEvent) {
        guard event.midiEventID < 0 else { return }
        midiEventsByID.removeValue(forKey: event.midiEventID)
        midiMessagesByEventID.removeValue(forKey: event.midiEventID)
        persistNativeVelvetMidi()
    }

    /// channel est 1-based en entrée (UI), stocké 0-based (convention MIDI ShowBuddy).
    func addVelvetMidiMessage(to event: MidiEvent, messageType: Int64, channel: Int64, data1: Int64, data2: Int64?) {
        guard event.midiEventID < 0 else { return }
        let id = nextVelvetMidiMessageID()
        midiMessagesByEventID[event.midiEventID, default: []].append(
            MidiMessage(
                midiMessageID: id,
                midiEventID: event.midiEventID,
                time: nil,
                outDevice: nil,
                channel: channel - 1,
                message: messageType,
                data1: data1,
                data2: data2
            )
        )
        persistNativeVelvetMidi()
    }

    func deleteVelvetMidiMessage(_ message: MidiMessage) {
        guard let eid = message.midiEventID else { return }
        midiMessagesByEventID[eid]?.removeAll { $0.midiMessageID == message.midiMessageID }
        persistNativeVelvetMidi()
    }

    private func persistNativeVelvetMidi() {
        let allEvents   = Array(midiEventsByID.values).sorted { $0.midiEventID < $1.midiEventID }
        let allMessages = Array(midiMessagesByEventID.values.joined()).sorted { $0.midiMessageID < $1.midiMessageID }
        store.update {
            $0.velvetMidiEvents   = allEvents
            $0.velvetMidiMessages = allMessages
        }
    }

    // MARK: - Suppression du contenu démo

    /// Supprime toutes les entités référencées dans le manifest démo :
    /// shows, tracks, mémos, cue points, cues MIDI timeline, trims, volumes,
    /// couleurs, events/messages MIDI, fichiers DemoMedia.
    /// Ne touche pas aux données utilisateur.
    func removeDemoContent() {
        guard let manifest = demoManifest else { return }

        let trackSet = Set(manifest.trackIDs)
        let eventSet = Set(manifest.midiEventIDs)
        let showSet  = Set(manifest.showIDs)

        // ── Shows + ordre d'affichage ────────────────────────────────────────
        velvetShows.removeAll     { showSet.contains($0.id) }
        velvetShowOrder.removeAll { showSet.contains($0) }

        // ── Tracks ──────────────────────────────────────────────────────────
        velvetTracks.removeAll { trackSet.contains($0.id) }

        // ── Données liées aux tracks (didSet → persist automatique) ─────────
        for id in trackSet {
            editableMemosByAudioFileID.removeValue(forKey: id)
            cuePointsByAudioFileID.removeValue(forKey: id)
            midiCuesByAudioFileID.removeValue(forKey: id)
            trimsByAudioFileID.removeValue(forKey: id)
            volumeByAudioFileID.removeValue(forKey: id)
            trackColorsByAudioFileID.removeValue(forKey: id)
        }

        // Données stockées directement dans store.state (pas de didSet AppState)
        store.update {
            for id in trackSet {
                let key = String(id)
                $0.tempoOverridesByAudioFileID.removeValue(forKey: key)
                $0.audioFileMetaCacheByID.removeValue(forKey: key)
            }
        }

        // ── Events MIDI + messages ───────────────────────────────────────────
        for id in eventSet {
            midiEventsByID.removeValue(forKey: id)
            midiMessagesByEventID.removeValue(forKey: id)
            archivedMidiEventIDs.remove(id)
        }
        persistNativeVelvetMidi()

        // ── Cue de repos : sécurité si le demo event était sélectionné ──────
        if let restID = restCueMidiEventID, eventSet.contains(restID) {
            restCueMidiEventID = nil
        }

        // ── Fichiers DemoMedia (async, non bloquant) ─────────────────────────
        let demoDir = store.demoMediaDirectoryURL
        Task.detached(priority: .background) {
            try? FileManager.default.removeItem(at: demoDir)
        }

        // ── UserDefaults + manifest ──────────────────────────────────────────
        DemoContentStore.shared.clearManifest()
        demoManifest = nil

        print("[DEMO] removeDemoContent(): \(showSet.count) show(s), \(trackSet.count) track(s), \(eventSet.count) MIDI event(s) deleted.")
    }

    // MARK: - Installation du contenu démo

    /// Injecte le projet démo depuis le bundle dans l'état courant.
    /// Idempotente : si le manifest existe déjà, ne fait rien.
    /// Ne touche jamais aux données utilisateur.
    func installDemoContent() throws {
        guard demoManifest == nil else { return }
        guard let jsonURL = DemoContentStore.shared.bundleDemoStateURL else {
            throw DemoInstallError.jsonNotFound
        }

        // ── Décodage du JSON démo ────────────────────────────────────────────
        let jsonData = try Data(contentsOf: jsonURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let demoState = try decoder.decode(VelvetShowState.self, from: jsonData)

        // ── Vérification de collision d'IDs ──────────────────────────────────
        let existingTrackIDs = Set(velvetTracks.map(\.id))
        let existingShowIDs  = Set(velvetShows.map(\.id))
        let existingEventIDs = Set(midiEventsByID.keys)

        let demoTrackIDs = demoState.velvetTracks.map(\.id)
        let demoShowIDs  = demoState.velvetShows.map(\.id)
        let demoEventIDs = demoState.velvetMidiEvents.map(\.midiEventID)

        guard demoTrackIDs.allSatisfy({ !existingTrackIDs.contains($0) }),
              demoShowIDs.allSatisfy({ !existingShowIDs.contains($0) }),
              demoEventIDs.allSatisfy({ !existingEventIDs.contains($0) })
        else { throw DemoInstallError.idCollision }

        // ── Copie des fichiers audio to App Support/DemoMedia/ ─────────────
        let fm = FileManager.default
        let demoDir = store.demoMediaDirectoryURL
        try fm.createDirectory(at: demoDir, withIntermediateDirectories: true)

        var patchedTracks:  [VelvetTrack] = []
        var mediaFileNames: [String]       = []

        for track in demoState.velvetTracks {
            let fileName  = track.fileURL.lastPathComponent
            let nameNoExt = (fileName as NSString).deletingPathExtension
            let ext       = (fileName as NSString).pathExtension

            // Recherche dans l'ordre : DemoContent/DemoMedia/, DemoMedia/, racine Resources
            let resourceURL = Bundle.main.resourceURL
            let candidates: [URL?] = [
                resourceURL.map { $0.appendingPathComponent("DemoContent/DemoMedia/\(fileName)") },
                resourceURL.map { $0.appendingPathComponent("DemoMedia/\(fileName)") },
                resourceURL.map { $0.appendingPathComponent(fileName) },
                Bundle.main.url(forResource: nameNoExt, withExtension: ext,  subdirectory: "DemoContent/DemoMedia"),
                Bundle.main.url(forResource: nameNoExt, withExtension: ext,  subdirectory: "DemoMedia"),
                Bundle.main.url(forResource: nameNoExt, withExtension: ext),
            ]

            let srcURL = candidates.compactMap { $0 }.first { fm.fileExists(atPath: $0.path) }

            guard let srcURL else {
                let searched = candidates.compactMap { $0?.path }.joined(separator: "\n  ")
                print("[DEMO] Missing bundled media: \(fileName)\n[DEMO] Searched:\n  \(searched)")
                throw DemoInstallError.audioFileMissing(fileName)
            }
            print("[DEMO] Found bundled media: \(srcURL.path)")

            let destURL = demoDir.appendingPathComponent(fileName)
            if !fm.fileExists(atPath: destURL.path) {
                try fm.copyItem(at: srcURL, to: destURL)
            }
            mediaFileNames.append(fileName)
            patchedTracks.append(VelvetTrack(
                id:         track.id,
                title:      track.title,
                genre:      track.genre,
                note:       track.note,
                colorHex:   track.colorHex,
                tempo:      track.tempo,
                fileURL:    destURL,
                duration:   track.duration,
                importedAt: track.importedAt
            ))
        }

        // ── Fusion dans AppState (didSet → persist automatique) ──────────────
        velvetTracks    += patchedTracks
        velvetShows     += demoState.velvetShows
        velvetShowOrder  = demoShowIDs + velvetShowOrder

        // Memos (clé String → Int64)
        for (id, memos) in demoState.editableMemosByAudioFileID.keyedByInt64() {
            editableMemosByAudioFileID[id] = memos
        }

        // Cues MIDI timeline (clé String → Int64)
        for (id, cues) in demoState.midiCuesByAudioFileID.keyedByInt64() {
            midiCuesByAudioFileID[id] = cues
        }

        // Events + messages MIDI (private(set) → mutation directe)
        for event in demoState.velvetMidiEvents {
            midiEventsByID[event.midiEventID] = event
        }
        for msg in demoState.velvetMidiMessages {
            guard let eid = msg.midiEventID else { continue }
            midiMessagesByEventID[eid, default: []].append(msg)
        }
        persistNativeVelvetMidi()

        // ── Manifest + UserDefaults ──────────────────────────────────────────
        let manifest = DemoContentManifest(
            version:        1,
            showIDs:        demoShowIDs,
            trackIDs:       demoTrackIDs,
            midiEventIDs:   demoEventIDs,
            mediaFileNames: mediaFileNames
        )
        DemoContentStore.shared.manifest = manifest
        demoManifest = manifest

        print("[DEMO] installDemoContent(): \(demoShowIDs.count) show(s), \(demoTrackIDs.count) track(s), \(demoEventIDs.count) MIDI event(s) installed.")
    }

    // MARK: - Endgerprint MIDI

    /// Signature canonique d'une liste de messages.
    /// Utilisée for la déduplication at l'import — indépendante du nom et de l'ID.
    /// Format par message : "<statusHighNibble>-<channel0based>-<data1>-<data2orNil>"
    /// Trié for que l'ordre des messages n'entre pas en compte.
    func midiEndgerprint(for messages: [MidiMessage]) -> String {
        messages.map { m -> String in
            let hi  = (m.message ?? 0) & 0xF0
            let ch  = m.channel ?? 0
            let d1  = m.data1   ?? 0
            // Program Change (0xC0) et Channel Pressure (0xD0) : 1 seul data byte.
            let d2: String = (hi == 0xC0 || hi == 0xD0) ? "nil" : "\(m.data2 ?? 0)"
            return "\(hi)-\(ch)-\(d1)-\(d2)"
        }
        .sorted()
        .joined(separator: "|")
    }

    func midiEndgerprint(for event: MidiEvent) -> String {
        midiEndgerprint(for: midiMessages(for: event))
    }

    // MARK: - Import MaestroDMX

    /// Résultat de l'analyse avant application.
    struct MaestroDMXImportReport {

        enum EntryStatus {
            case alreadyPresent     // même nom + même fingerprint → réutiliser
            case new                // inconnu → créer
            case nameConflict       // même nom, fingerprint différent → conserver les deux
            case midiEquivalent     // même fingerprint, nom différent → signaler, ne pas fusionner
        }

        struct Entry: Identifiable {
            let id = UUID()
            let cueName:   String
            let cueNumber: Int         // 1-98
            let note:      Int         // cueNumber + 28
            let fingerprint: String
            let status:    EntryStatus
            let matchedEvent: MidiEvent?
        }

        let entries: [Entry]

        var alreadyPresent: [Entry] { entries.filter { if case .alreadyPresent = $0.status { return true }; return false } }
        var newEntries:     [Entry] { entries.filter { if case .new            = $0.status { return true }; return false } }
        var nameConflicts:  [Entry] { entries.filter { if case .nameConflict   = $0.status { return true }; return false } }
        var midiEquivalents:[Entry] { entries.filter { if case .midiEquivalent = $0.status { return true }; return false } }
    }

    /// Analyse une liste (nom, numéro de cue MaestroDMX 1-98) et retourne un rapport
    /// sans rien modifier.
    func analyzeMaestroDMXImport(_ pairs: [(name: String, cueNumber: Int)]) -> MaestroDMXImportReport {
        // Index fingerprint → event existant (calculé une seule fois).
        var fpIndex: [String: MidiEvent] = [:]
        for event in midiEventsByID.values {
            let fp = midiEndgerprint(for: event)
            if !fp.isEmpty { fpIndex[fp] = event }
        }

        // Index nom normalisé → events existants.
        var nameIndex: [String: [MidiEvent]] = [:]
        for event in midiEventsByID.values {
            let key = (event.name ?? "").trimmingCharacters(in: .whitespaces).uppercased()
            nameIndex[key, default: []].append(event)
        }

        // Index Note On ch16 note → event existant contenant ce message parmi d'autres.
        // Couvre le cas "event multi-messages" : Note On MaestroDMX + PC ch1 supplémentaire.
        var noteOnIndex: [Int64: MidiEvent] = [:]
        for event in midiEventsByID.values {
            for msg in midiMessages(for: event) {
                let hi = (msg.message ?? 0) & 0xF0
                if hi == 0x90, msg.channel == 15, msg.data2 == 0, let note = msg.data1 {
                    if noteOnIndex[note] == nil { noteOnIndex[note] = event }
                }
            }
        }

        var entries: [MaestroDMXImportReport.Entry] = []

        for pair in pairs {
            let name       = pair.name.trimmingCharacters(in: .whitespaces)
            let cueNumber  = pair.cueNumber
            let note       = cueNumber + 28     // spec MaestroDMX v1.5
            // Endgerprint du message entrant : Note On ch16 (0-based=15), note, velocity 0.
            let fp = "144-15-\(note)-0"

            let nameKey      = name.uppercased()
            let byName       = nameIndex[nameKey] ?? []
            let byFp         = fpIndex[fp]
            let byNoteOn     = noteOnIndex[Int64(note)]

            let status: MaestroDMXImportReport.EntryStatus
            let matched: MidiEvent?

            if let existing = byFp, (existing.name ?? "").uppercased() == nameKey {
                // Cas 1 — même nom + même fingerprint exact
                status  = .alreadyPresent
                matched = existing
            } else if let existing = byFp {
                // Cas 2 — même fingerprint exact, nom différent
                status  = .midiEquivalent
                matched = existing
            } else if let existing = byNoteOn {
                // Cas 3 — fingerprint partiel : un event existant contient déjà ce Note On ch16
                // (il peut avoir des messages supplémentaires, ex. PC ch1). Déjà couvert.
                status  = .midiEquivalent
                matched = existing
            } else if let existing = byName.first {
                // Cas 4 — même nom, fingerprint différent
                status  = .nameConflict
                matched = existing
            } else {
                // Cas nouveau
                status  = .new
                matched = nil
            }

            entries.append(MaestroDMXImportReport.Entry(
                cueName:    name,
                cueNumber:  cueNumber,
                note:       note,
                fingerprint: fp,
                status:     status,
                matchedEvent: matched
            ))
        }

        return MaestroDMXImportReport(entries: entries)
    }

    /// Applique le rapport : crée uniquement les events `.new`.
    /// Ne touche pas les existants, les mémos, les cues timeline ni le cue de repos.
    func applyMaestroDMXImport(_ report: MaestroDMXImportReport) {
        for entry in report.newEntries {
            guard case .new = entry.status else { continue }
            let eventID = nextVelvetMidiEventID()
            midiEventsByID[eventID] = MidiEvent(
                midiEventID: eventID,
                name:        entry.cueName,
                category:    "MaestroDMX"
            )
            let msgID = nextVelvetMidiMessageID()
            midiMessagesByEventID[eventID] = [
                MidiMessage(
                    midiMessageID: msgID,
                    midiEventID:   eventID,
                    time:          nil,
                    outDevice:     nil,
                    channel:       15,      // canal 16, 0-based
                    message:       144,     // Note On
                    data1:         Int64(entry.note),
                    data2:         0        // velocity 0
                )
            ]
        }
        persistNativeVelvetMidi()
    }

    // MARK: - Import MIDI Standard (.mid / .smf)

    /// Un message MIDI unique extrait d'un fichier .mid (dédoublonné par (hi, ch, d1, d2)).
    struct MidiFileCandidate {
        let statusHighNibble: Int   // 0x90 Note On, 0xB0 CC, 0xC0 PC
        let channel:          Int   // 0-based
        let data1:            Int
        let data2:            Int?  // nil for PC/CP (1 seul data byte)
        let occurrences:      Int   // nb fois dans le fichier (info uniquement)
    }

    struct MidiFileImportReport {
        enum EntryStatus {
            case alreadyPresent   // fingerprint exact + même nom
            case midiEquivalent   // fingerprint partiel ou exact, nom différent
            case new              // inconnu → at créer
        }

        struct Entry: Identifiable {
            let id            = UUID()
            let suggestedName:  String
            let fingerprint:    String
            let candidate:      MidiFileCandidate
            let status:         EntryStatus
            let matchedEvent:   MidiEvent?
        }

        let entries:      [Entry]
        let sourceFileName: String

        var newEntries:     [Entry] { entries.filter { if case .new            = $0.status { return true }; return false } }
        var alreadyPresent: [Entry] { entries.filter { if case .alreadyPresent = $0.status { return true }; return false } }
        var equivalents:    [Entry] { entries.filter { if case .midiEquivalent = $0.status { return true }; return false } }
    }

    func analyzeMidiFileImport(_ candidates: [MidiFileCandidate], sourceFileName: String) -> MidiFileImportReport {
        var fpIndex: [String: MidiEvent] = [:]
        for event in midiEventsByID.values {
            let fp = midiEndgerprint(for: event)
            if !fp.isEmpty { fpIndex[fp] = event }
        }

        var noteOnIndex: [Int64: MidiEvent] = [:]
        for event in midiEventsByID.values {
            for msg in midiMessages(for: event) {
                let hi = (msg.message ?? 0) & 0xF0
                if hi == 0x90, let note = msg.data1, noteOnIndex[note] == nil {
                    noteOnIndex[note] = event
                }
            }
        }

        var entries: [MidiFileImportReport.Entry] = []
        for c in candidates {
            let fp   = midiFileCandidateEndgerprint(c)
            let name = midiFileCandidateName(c)
            let byFp     = fpIndex[fp]
            let byNoteOn = (c.statusHighNibble == 0x90) ? noteOnIndex[Int64(c.data1)] : nil

            let status: MidiFileImportReport.EntryStatus
            let matched: MidiEvent?

            if let e = byFp, (e.name ?? "").uppercased() == name.uppercased() {
                status = .alreadyPresent; matched = e
            } else if let e = byFp {
                status = .midiEquivalent; matched = e
            } else if let e = byNoteOn {
                status = .midiEquivalent; matched = e
            } else {
                status = .new; matched = nil
            }

            entries.append(MidiFileImportReport.Entry(
                suggestedName: name,
                fingerprint:   fp,
                candidate:     c,
                status:        status,
                matchedEvent:  matched
            ))
        }

        return MidiFileImportReport(entries: entries, sourceFileName: sourceFileName)
    }

    func applyMidiFileImport(_ report: MidiFileImportReport) {
        for entry in report.newEntries {
            guard case .new = entry.status else { continue }
            let c       = entry.candidate
            let eventID = nextVelvetMidiEventID()
            midiEventsByID[eventID] = MidiEvent(
                midiEventID: eventID,
                name:        entry.suggestedName,
                category:    "Import MIDI"
            )
            let msgID    = nextVelvetMidiMessageID()
            let fullStatus = Int64(c.statusHighNibble | c.channel) // ex. 0x90|0 = 144
            midiMessagesByEventID[eventID] = [
                MidiMessage(
                    midiMessageID: msgID,
                    midiEventID:   eventID,
                    time:          nil,
                    outDevice:     nil,
                    channel:       Int64(c.channel),
                    message:       fullStatus,
                    data1:         Int64(c.data1),
                    data2:         c.data2.map { Int64($0) }
                )
            ]
        }
        persistNativeVelvetMidi()
    }

    private func midiFileCandidateEndgerprint(_ c: MidiFileCandidate) -> String {
        let hi  = c.statusHighNibble
        let ch  = c.channel
        let d1  = c.data1
        let d2: String = (hi == 0xC0 || hi == 0xD0) ? "nil" : "\(c.data2 ?? 0)"
        return "\(hi)-\(ch)-\(d1)-\(d2)"
    }

    private func midiFileCandidateName(_ c: MidiFileCandidate) -> String {
        let ch = c.channel + 1
        switch c.statusHighNibble {
        case 0x90:
            return "Note On \(midiNoteNameFromNumber(c.data1)) ch\(ch)"
        case 0xB0:
            let ccName = standardCCName(c.data1)
            return "CC \(c.data1)\(ccName.isEmpty ? "" : " \(ccName)") ch\(ch)"
        case 0xC0:
            return "PC \(c.data1 + 1) ch\(ch)"
        default:
            return "MIDI \(c.statusHighNibble | c.channel) \(c.data1)"
        }
    }

    private func midiNoteNameFromNumber(_ number: Int) -> String {
        let names  = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        let octave = number / 12 - 2   // Yamaha : Middle C = C3
        let pitch  = names[number % 12]
        return "\(pitch)\(octave)"
    }

    private func standardCCName(_ cc: Int) -> String {
        switch cc {
        case 1:  return "Modulation"
        case 7:  return "Volume"
        case 10: return "Pan"
        case 11: return "Expression"
        case 64: return "Sustain"
        case 91: return "Reverb"
        case 93: return "Chorus"
        default: return ""
        }
    }

    // MARK: - Shows Velvet autonomes

    /// Conservé for les cas où seul l'ID est disponible (hors contexte AppState).
    /// Préférer `isVelvetShow(_:)` qui vérifie la présence réelle dans velvetShows.
    static func isVelvetShowID(_ setID: ShowSet.ID) -> Bool { setID < 0 }

    /// Vrai si ce set est un VelvetShow — vérifie la présence dans velvetShows,
    /// indépendamment du signe de l'ID (les concerts importeds ont des IDs positifs).
    func isVelvetShow(_ set: ShowSet) -> Bool {
        velvetShows.contains { $0.id == set.setID }
    }

    func velvetShow(for set: ShowSet) -> VelvetShow? {
        velvetShows.first { $0.id == set.setID }
    }

    private static func showSet(from velvetShow: VelvetShow) -> ShowSet {
        ShowSet(
            setID: velvetShow.id,
            name: velvetShow.name,
            note: velvetShow.note,
            folder: velvetShow.folder ?? "VELVET SHOWS",
            setType: "Velvet"
        )
    }

    func color(for set: ShowSet) -> Color {
        guard let show = velvetShow(for: set) else { return .secondary }
        return Color(hex: show.colorHex)
    }

    func createVelvetShow(name: String, note: String, color: Color) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let showName = trimmedName.isEmpty ? "New Show" : trimmedName
        let show = VelvetShow(
            id: nextVelvetShowID(),
            name: showName,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: color.hexComponents
        )
        velvetShows.append(show)
        selectedSetID = show.id
    }

    func duplicateAsVelvetShow(_ source: ShowSet) {
        var nextTrackID = nextVelvetTrackID()
        let sourceSongs = songs(in: source)
        let copiedTracks = sourceSongs.compactMap { song -> VelvetShowTrack? in
            guard let audio = song.audio else { return nil }
            let mode: QueuePlaybackMode = song.element.autoStart == 1 ? .automatic : .manual
            // Récupère endBehavior depuis le VelvetShowTrack source si disponible.
            let behavior: TrackEndBehavior
            if let velvetShow = velvetShow(for: source),
               let vst = velvetShow.tracks.first(where: { $0.id == song.element.setElementID }) {
                behavior = vst.endBehavior
            } else {
                behavior = endBehavior(for: song, in: source)
            }
            defer { nextTrackID -= 1 }
            return VelvetShowTrack(
                id: nextTrackID,
                audioFileID: audio.audioFileID,
                playbackMode: mode,
                endBehavior: behavior
            )
        }
        let baseName = source.name ?? "Unnamed Show"
        // Color : copie celle du show source si disponible, sinon couleur par défaut.
        let sourceColorHex: UInt32
        if let velvetShow = velvetShow(for: source) {
            sourceColorHex = velvetShow.colorHex
        } else {
            sourceColorHex = 0x00C8FF
        }
        let newShowID = nextVelvetShowID()
        let show = VelvetShow(
            id: newShowID,
            name: "\(baseName) (copie)",
            note: source.note ?? "",
            colorHex: sourceColorHex,
            tracks: copiedTracks
        )
        velvetShows.append(show)
        // Copie les couleurs locales au show (songColorsByShowID).
        if let srcColors = songColorsByShowID[source.setID] {
            // Les clés sont des audioFileIDs — valables dans le nouveau show.
            songColorsByShowID[newShowID] = srcColors
        }
        selectedSetID = show.id
    }

    func updateVelvetShow(_ set: ShowSet, name: String, note: String, color: Color) {
        guard let index = velvetShows.firstIndex(where: { $0.id == set.setID }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        velvetShows[index].name = trimmedName.isEmpty ? "Show Velvet" : trimmedName
        velvetShows[index].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        velvetShows[index].colorHex = color.hexComponents
    }

    func deleteVelvetShow(_ set: ShowSet) {
        guard isVelvetShow(set) else { return }
        velvetShows.removeAll { $0.id == set.setID }
        playedSetElementIDsBySetID[set.setID] = nil
        liveAdditionsBySetID[set.setID] = nil
        concertQueueBySetID[set.setID] = nil
        customOrderBySetID[set.setID] = nil
        selectedShowSetElementIDBySetID[set.setID] = nil
        activeConcertIDBySetID[set.setID] = nil
        songColorsByShowID[set.setID] = nil
        endBehaviorBySetElementID = endBehaviorBySetElementID.filter { key, _ in
            !velvetShows.flatMap({ $0.tracks }).map({ $0.id }).contains(key)
        }
        if selectedSetID == set.setID {
            selectedSetID = sets.first?.id
        }
        store.saveNow()
    }

    private func nextVelvetShowID() -> Int64 {
        let candidate = min(-1, (velvetShows.map(\.id).min() ?? 0) - 1)
        if DemoIDRange.shows.contains(candidate) { return DemoIDRange.shows.lowerBound - 1 }
        return candidate
    }

    private func nextVelvetTrackID() -> Int64 {
        let candidate = min(-1, (velvetShows.flatMap { $0.tracks.map(\.id) }.min() ?? 0) - 1)
        if DemoIDRange.showTracks.contains(candidate) { return DemoIDRange.showTracks.lowerBound - 1 }
        return candidate
    }

    // MARK: - Mode édition du show
    //
    // Ces helpers permettent at l'UI de réorganiser, supprimer ou ajouter
    // librement dans un show — sans jamais toucher at ShowBuddy.db.
    // L'ordre custom est stocké dans le VelvetShowStore et appliqué par
    // `songs(in:)` au moment du rendu. Le mode édition est verrouillé
    // par défaut (`isShowEditMode = false`) for ne pas qu'un drag
    // accidentel ne perturbe un concert.

    /// Renvoie l'ordre natural (ShowBuddy + live additions) sans les
    /// overrides. Utilisé for initialiser un `customOrderBySetID` la
    /// première fois qu'on touche au show.
    private func naturalOrder(for set: ShowSet) -> [SetElement.ID] {
        if let show = velvetShow(for: set) {
            return show.tracks.map(\.id)
        }
        guard let db = database else { return [] }
        do {
            let elements = try db.loadSetElements(forSetID: set.setID)
            var ids = elements.map { $0.setElementID }
            for addition in liveAdditionsBySetID[set.setID] ?? [] {
                if let anchor = addition.anchorSetElementID,
                   let idx = ids.lastIndex(of: anchor) {
                    ids.insert(addition.id, at: ids.index(after: idx))
                } else {
                    ids.append(addition.id)
                }
            }
            return ids
        } catch {
            return []
        }
    }

    /// Garantit qu'un `customOrderBySetID[setID]` existe avant toute
    /// mutation. Le premier appel initialise l'override avec l'ordre
    /// natural courant — les éditions suivantes opèrent sur la liste.
    private func ensureCustomOrder(for set: ShowSet) {
        guard customOrderBySetID[set.setID] == nil else { return }
        customOrderBySetID[set.setID] = naturalOrder(for: set)
    }

    /// Déplace une ou plusieurs lignes dans le show. Appelé directement
    /// par `List.onMove` côté UI : SwiftUI fournit déjà les IndexSet et
    /// la destination, on les applique sur la liste d'IDs persistée.
    func moveSong(in set: ShowSet, from source: IndexSet, to destination: Int) {
        if let index = velvetShows.firstIndex(where: { $0.id == set.setID }) {
            velvetShows[index].tracks.move(fromOffsets: source, toOffset: destination)
            return
        }
        ensureCustomOrder(for: set)
        customOrderBySetID[set.setID]?.move(fromOffsets: source, toOffset: destination)
    }

    func moveSong(in set: ShowSet, songID: SetElement.ID, before targetID: SetElement.ID) {
        moveSong(in: set, songID: songID, relativeTo: targetID, placement: .before)
    }

    func moveSong(in set: ShowSet, songID: SetElement.ID, after targetID: SetElement.ID) {
        moveSong(in: set, songID: songID, relativeTo: targetID, placement: .after)
    }

    private enum SongMovePlacement {
        case before
        case after
    }

    private func moveSong(
        in set: ShowSet,
        songID: SetElement.ID,
        relativeTo targetID: SetElement.ID,
        placement: SongMovePlacement
    ) {
        guard songID != targetID else { return }
        if let index = velvetShows.firstIndex(where: { $0.id == set.setID }) {
            var tracks = velvetShows[index].tracks
            guard let sourceIndex = tracks.firstIndex(where: { $0.id == songID }),
                  tracks.contains(where: { $0.id == targetID }) else { return }
            let moved = tracks.remove(at: sourceIndex)
            guard let targetIndex = tracks.firstIndex(where: { $0.id == targetID }) else { return }
            let destinationIndex = placement == .before ? targetIndex : tracks.index(after: targetIndex)
            tracks.insert(moved, at: destinationIndex)
            velvetShows[index].tracks = tracks
            return
        }
        ensureCustomOrder(for: set)
        guard var order = customOrderBySetID[set.setID],
              let sourceIndex = order.firstIndex(of: songID),
              order.contains(targetID) else { return }
        let moved = order.remove(at: sourceIndex)
        guard let targetIndex = order.firstIndex(of: targetID) else { return }
        let destinationIndex = placement == .before ? targetIndex : order.index(after: targetIndex)
        order.insert(moved, at: destinationIndex)
        customOrderBySetID[set.setID] = order
    }

    /// Retire un song du show côté Velvet. ShowBuddy n'est pas touchée :
    /// si l'utilisateur réimporte ou reset, le song sera de nouveau là.
    /// Nettoie aussi la queue et l'historique joué for ce set.
    func removeFromShow(songID: SetElement.ID, in set: ShowSet) {
        if let index = velvetShows.firstIndex(where: { $0.id == set.setID }) {
            velvetShows[index].tracks.removeAll { $0.id == songID }
        } else {
            ensureCustomOrder(for: set)
            customOrderBySetID[set.setID]?.removeAll { $0 == songID }
            liveAdditionsBySetID[set.setID]?.removeAll { $0.id == songID }
        }
        // Retire de la queue si présent — évite un AUTO SHOW sur un song supprimé.
        concertQueueBySetID[set.setID]?.removeAll { $0.setElementID == songID }
        // Retire de l'historique joué — cohérence de l'état de lecture.
        playedSetElementIDsBySetID[set.setID]?.remove(songID)
    }

    /// Annule toutes les éditions Velvet sur un set — retour at l'ordre
    /// natural ShowBuddy + live additions courantes.
    func resetCustomOrder(for set: ShowSet) {
        customOrderBySetID[set.setID] = nil
    }

    /// Réordonne la file d'attente du concert. Pendant un long set on
    /// veut souvent déplacer un song "vers le haut" sans le retirer
    /// puis le ré-ajouter.
    func moveQueueItem(in set: ShowSet, from source: IndexSet, to destination: Int) {
        guard var queue = concertQueueBySetID[set.setID] else { return }
        queue.move(fromOffsets: source, toOffset: destination)
        concertQueueBySetID[set.setID] = queue
    }

    // MARK: - Songs d'un set (Show Library)

    /// Retourne les songs d'un set sous forme de `Song` (élément +
    /// show + audio résolus en une seule passe).
    func songs(in set: ShowSet) -> [Song] {
        if let show = velvetShow(for: set) {
            return show.tracks.enumerated().compactMap { index, item in
                guard let audio = audioFilesByID[item.audioFileID] else { return nil }
                let element = SetElement(
                    setElementID: item.id,
                    setID: show.id,
                    lightShowID: -1,
                    playOrder: Int64(index + 1),
                    note: item.playbackMode.label,
                    autoStart: item.playbackMode == .automatic ? 1 : 0,
                    loop: nil,
                    colour: nil
                )
                return Song(element: element, show: nil, audio: audio)
            }
        }
        guard let db = database else { return [] }
        do {
            let elements = try db.loadSetElements(forSetID: set.setID)
            var resolvedSongs = elements.map { element in
                let show = lightShowsByID[element.lightShowID]
                let audio = show?.audioFileID.flatMap { audioFilesByID[$0] }
                return Song(element: element, show: show, audio: audio)
            }
            for addition in liveAdditionsBySetID[set.setID] ?? [] {
                guard let audio = audioFilesByID[addition.audioFileID] else { continue }
                let liveElement = SetElement(
                    setElementID: addition.id,
                    setID: set.setID,
                    lightShowID: -1,
                    playOrder: nil,
                    note: addition.anchorSetElementID.map { "Added live after \($0)" } ?? "Added live",
                    autoStart: nil,
                    loop: nil,
                    colour: nil
                )
                let liveSong = Song(element: liveElement, show: nil, audio: audio, isLiveAdded: true)
                if let anchor = addition.anchorSetElementID,
                   let index = resolvedSongs.lastIndex(where: { $0.element.setElementID == anchor || $0.element.note == "Added live after \(anchor)" }) {
                    resolvedSongs.insert(liveSong, at: resolvedSongs.index(after: index))
                } else {
                    resolvedSongs.append(liveSong)
                }
            }

            // Application des éditions Velvet : si un customOrder est
            // présent on l'applique strictement (un ID absent = supprimé).
            // Tout song qui n'apparaît pas dans le custom — typiquement
            // un ajout live postérieur at la dernière édition — est
            // appended en fin for ne pas être perdu.
            if let customOrder = customOrderBySetID[set.setID] {
                let songsByID = Dictionary(
                    uniqueKeysWithValues: resolvedSongs.map { ($0.element.setElementID, $0) }
                )
                let ordered = customOrder.compactMap { songsByID[$0] }
                let listed = Set(customOrder)
                let unlisted = resolvedSongs.filter { !listed.contains($0.element.setElementID) }
                resolvedSongs = ordered + unlisted
            }

            return resolvedSongs
        } catch {
            self.lastError = error.localizedDescription
            return []
        }
    }

    // MARK: - Suppression multi-niveaux & Velvet Trash

    /// Retourne la liste des VelvetShows qui contiennent ce song.
    func showsContaining(_ track: VelvetTrack) -> [VelvetShow] {
        velvetShows.filter { show in
            show.tracks.contains { $0.audioFileID == track.id }
        }
    }

    /// NIVEAU 1 — Retirer d'un show Velvet (sans toucher at la bibliothèque).
    func removeTrack(_ track: VelvetTrack, from show: VelvetShow) {
        guard let showIdx = velvetShows.firstIndex(where: { $0.id == show.id }) else { return }
        velvetShows[showIdx].tracks.removeAll { $0.audioFileID == track.id }
    }

    /// Overload pratique depuis Show Library : accepte un ShowSet (Velvet).
    func removeTrack(_ track: VelvetTrack, from set: ShowSet) {
        guard let show = velvetShow(for: set) else { return }
        removeTrack(track, from: show)
    }

    /// NIVEAU 2 — Delete de la bibliothèque Velvet et de tous les shows Velvet.
    /// Déplace dans la Velvet Trash (snapshot complet préservé, restauration possible).
    func trashVelvetTrack(_ track: VelvetTrack) {
        let tid = track.id
        // Snapshot toutes les données associées
        let memos = editableMemosByAudioFileID[tid] ?? []
        let cues  = cuePointsByAudioFileID[tid] ?? []
        let trim  = trimsByAudioFileID[tid]
        let vol   = volumeByAudioFileID[tid]
        let color = trackColorsByAudioFileID[tid]

        let trashed = TrashedVelvetTrack(
            track: track,
            memos: memos,
            cuePoints: cues,
            trim: trim,
            volume: vol,
            colorHex: color
        )
        trashedTracks.insert(trashed, at: 0)

        // Retirer de la bibliothèque
        velvetTracks.removeAll { $0.id == tid }

        // Retirer de tous les shows Velvet
        for idx in velvetShows.indices {
            velvetShows[idx].tracks.removeAll { $0.audioFileID == tid }
        }

        // Nettoyer les données associées
        editableMemosByAudioFileID.removeValue(forKey: tid)
        cuePointsByAudioFileID.removeValue(forKey: tid)
        trimsByAudioFileID.removeValue(forKey: tid)
        volumeByAudioFileID.removeValue(forKey: tid)
        trackColorsByAudioFileID.removeValue(forKey: tid)
    }

    /// Restore un song depuis la Velvet Trash to la bibliothèque.
    func restoreFromTrash(_ trashed: TrashedVelvetTrack) {
        let tid = trashed.track.id
        // Remettre en bibliothèque si absent
        if !velvetTracks.contains(where: { $0.id == tid }) {
            velvetTracks.append(trashed.track)
        }
        // Restore les données associées (sans écraser l'existant si déjà là)
        if editableMemosByAudioFileID[tid] == nil {
            editableMemosByAudioFileID[tid] = trashed.memos
        }
        if cuePointsByAudioFileID[tid] == nil {
            cuePointsByAudioFileID[tid] = trashed.cuePoints
        }
        if let trim = trashed.trim, trimsByAudioFileID[tid] == nil {
            trimsByAudioFileID[tid] = trim
        }
        if let vol = trashed.volume, volumeByAudioFileID[tid] == nil {
            volumeByAudioFileID[tid] = vol
        }
        if let color = trashed.colorHex, trackColorsByAudioFileID[tid] == nil {
            trackColorsByAudioFileID[tid] = color
        }
        trashedTracks.removeAll { $0.id == trashed.id }
    }

    /// NIVEAU 3 — Suppression définitive depuis la Corbeille.
    /// Ne touche pas au fichier audio (MediaFiles reste intact).
    func permanentlyDeleteTrashedTrack(_ trashed: TrashedVelvetTrack) {
        trashedTracks.removeAll { $0.id == trashed.id }
    }

    /// Vider toute la Velvet Trash (suppression définitive de tous les éléments).
    func emptyVelvetTrash() {
        trashedTracks.removeAll()
    }
}
