//
//  VelvetShowStore.swift
//  VELVET SHOW
//
//  Couche de persistance locale propre at VELVET SHOW.
//
//  Principes :
//  - ShowBuddy.db reste read-only, JAMAIS modifiée par cette couche ;
//  - tout ce que l'utilisateur produit dans Velvet Show (mémos édités,
//    pièces jointes, progression des shows, queue, ajouts live, couleurs
//    de styles, préférences utiles) est sérialisé dans un seul fichier
//    JSON en Application Support, at côté du dossier Attachments ;
//  - les pièces jointes sont copiées dans Attachments/<uuid>.<ext> dès
//    leur ajout — l'état JSON ne référence plus jamais l'URL d'origine ;
//  - les sauvegardes sont debouncées (0,4 s) for éviter d'écrire à
//    chaque frappe, et l'UI peut lire le statut via `status`.
//

import Foundation
import Observation

// MARK: - État sérialisé

/// Container racine du fichier `VelvetShowState.json`.
///
/// Les clés Int64 (AudioFileID, SetID, SetElementID...) sont sérialisées en
/// String parce que JSON n'accepte que des clés string. La conversion se
/// fait dans `AppState` via les helpers `string(_:)` / `int64(_:)` en bas
/// de ce fichier.
struct VelvetShowState: Codable {

    init() { }

    private enum CodingKeys: String, CodingKey {
        case version
        case editableMemosByAudioFileID
        case memoAttachmentsByMemoID
        case velvetTracks
        case velvetShows
        case playedSetElementIDsBySetID
        case liveAdditionsBySetID
        case concertQueueBySetID
        case concertHistory
        case activeConcertIDBySetID
        case customOrderBySetID
        case genreColors
        case selectedConcertGenreRaw
        case isSafePlayEnabled
        case isQuickLibraryVisible
        case trimsByAudioFileID
        case volumeByAudioFileID
        case trackColorsByAudioFileID
        case hasMigratedFromShowBuddy
        case hasImportedShowBuddyTrims
        case velvetMidiEvents
        case velvetMidiMessages
        case cuePointsByAudioFileID
        case trashedTracks
        case songColorsByShowID
        case velvetShowOrder
        case endBehaviorBySetElementID
        case normTargetLUFS
        case isNormalizationEnabled
        case tempoOverridesByAudioFileID
        case audioFileMetaCacheByID
        case customGenreColors
        case midiCuesByAudioFileID
        case archivedMidiEventIDs
        case oscCuesByAudioFileID
        case velvetOscEvents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        editableMemosByAudioFileID = try container.decodeIfPresent([String: [EditableMemo]].self, forKey: .editableMemosByAudioFileID) ?? [:]
        memoAttachmentsByMemoID = try container.decodeIfPresent([String: [MemoAttachment]].self, forKey: .memoAttachmentsByMemoID) ?? [:]
        velvetTracks = try container.decodeIfPresent([VelvetTrack].self, forKey: .velvetTracks) ?? []
        velvetShows = try container.decodeIfPresent([VelvetShow].self, forKey: .velvetShows) ?? []
        playedSetElementIDsBySetID = try container.decodeIfPresent([String: [Int64]].self, forKey: .playedSetElementIDsBySetID) ?? [:]
        liveAdditionsBySetID = try container.decodeIfPresent([String: [LiveShowAddition]].self, forKey: .liveAdditionsBySetID) ?? [:]
        concertQueueBySetID = try container.decodeIfPresent([String: [ConcertQueueItem]].self, forKey: .concertQueueBySetID) ?? [:]
        concertHistory = try container.decodeIfPresent([ConcertHistoryEntry].self, forKey: .concertHistory) ?? []
        activeConcertIDBySetID = try container.decodeIfPresent([String: UUID].self, forKey: .activeConcertIDBySetID) ?? [:]
        customOrderBySetID = try container.decodeIfPresent([String: [Int64]].self, forKey: .customOrderBySetID) ?? [:]
        genreColors = try container.decodeIfPresent([String: UInt32].self, forKey: .genreColors) ?? [:]
        selectedConcertGenreRaw = try container.decodeIfPresent(String.self, forKey: .selectedConcertGenreRaw) ?? ConcertGenre.all.rawValue
        isSafePlayEnabled = try container.decodeIfPresent(Bool.self, forKey: .isSafePlayEnabled) ?? true
        isQuickLibraryVisible = try container.decodeIfPresent(Bool.self, forKey: .isQuickLibraryVisible) ?? true
        trimsByAudioFileID = try container.decodeIfPresent([String: VelvetTrackTrim].self, forKey: .trimsByAudioFileID) ?? [:]
        volumeByAudioFileID = try container.decodeIfPresent([String: VelvetTrackVolume].self, forKey: .volumeByAudioFileID) ?? [:]
        trackColorsByAudioFileID = try container.decodeIfPresent([String: UInt32].self, forKey: .trackColorsByAudioFileID) ?? [:]
        hasMigratedFromShowBuddy = try container.decodeIfPresent(Bool.self, forKey: .hasMigratedFromShowBuddy) ?? false
        hasImportedShowBuddyTrims = try container.decodeIfPresent(Bool.self, forKey: .hasImportedShowBuddyTrims) ?? false
        velvetMidiEvents  = try container.decodeIfPresent([MidiEvent].self,   forKey: .velvetMidiEvents)  ?? []
        velvetMidiMessages = try container.decodeIfPresent([MidiMessage].self, forKey: .velvetMidiMessages) ?? []
        cuePointsByAudioFileID = try container.decodeIfPresent([String: [CuePoint]].self, forKey: .cuePointsByAudioFileID) ?? [:]
        trashedTracks = try container.decodeIfPresent([TrashedVelvetTrack].self, forKey: .trashedTracks) ?? []
        songColorsByShowID = try container.decodeIfPresent([String: [String: UInt32]].self, forKey: .songColorsByShowID) ?? [:]
        velvetShowOrder    = try container.decodeIfPresent([Int64].self, forKey: .velvetShowOrder) ?? []
        endBehaviorBySetElementID = try container.decodeIfPresent([String: TrackEndBehavior].self, forKey: .endBehaviorBySetElementID) ?? [:]
        normTargetLUFS = try container.decodeIfPresent(Double.self, forKey: .normTargetLUFS) ?? -16.0
        isNormalizationEnabled = try container.decodeIfPresent(Bool.self, forKey: .isNormalizationEnabled) ?? false
        tempoOverridesByAudioFileID = try container.decodeIfPresent([String: Double].self, forKey: .tempoOverridesByAudioFileID) ?? [:]
        audioFileMetaCacheByID = try container.decodeIfPresent([String: AudioFileMetaCache].self, forKey: .audioFileMetaCacheByID) ?? [:]
        customGenreColors = try container.decodeIfPresent([String: UInt32].self, forKey: .customGenreColors) ?? [:]
        midiCuesByAudioFileID = try container.decodeIfPresent([String: [TimelineMidiCue]].self, forKey: .midiCuesByAudioFileID) ?? [:]
        archivedMidiEventIDs  = try container.decodeIfPresent([Int64].self, forKey: .archivedMidiEventIDs) ?? []
        oscCuesByAudioFileID  = try container.decodeIfPresent([String: [TimelineOscCue]].self, forKey: .oscCuesByAudioFileID) ?? [:]
        velvetOscEvents       = try container.decodeIfPresent([OscEvent].self, forKey: .velvetOscEvents) ?? []
    }

    /// Numéro de version du schéma. Incrémenté at chaque migration structurelle.
    /// Ne jamais le réduire — toujours croissant.
    var version: Int = 1

    // ──────────────────────────────────────────────────────────────
    // MARK: - Version courante du schéma
    // ──────────────────────────────────────────────────────────────
    //
    // Règle d'évolution :
    //   1. Incrémenter `currentSchemaVersion`.
    //   2. Add un bloc `if s.version < N` dans `migrate(_:)`.
    //   3. Ne jamais modifier les blocs de migration existants.
    //
    static let currentSchemaVersion: Int = 3

    // Édition timeline (Track Library).
    var editableMemosByAudioFileID: [String: [EditableMemo]] = [:]
    var memoAttachmentsByMemoID: [String: [MemoAttachment]] = [:]

    // Songs et Shows Velvet autonomes, stockés localement sans modifier ShowBuddy.db.
    var velvetTracks: [VelvetTrack] = []
    var velvetShows: [VelvetShow] = []

    // Concert (Show Library).
    var playedSetElementIDsBySetID: [String: [Int64]] = [:]
    var liveAdditionsBySetID: [String: [LiveShowAddition]] = [:]
    var concertQueueBySetID: [String: [ConcertQueueItem]] = [:]
    var concertHistory: [ConcertHistoryEntry] = []
    var activeConcertIDBySetID: [String: UUID] = [:]

    /// Ordre personnalisé Velvet Show for un set ShowBuddy. La liste
    /// définit l'ordre ET le contenu visible : un setElementID absent
    /// est considéré comme supprimé du show côté Velvet Show. Tout
    /// nouveau song (ajouté live après l'édition) est appended at la
    /// fin par `AppState.songs(in:)` for ne pas le perdre.
    var customOrderBySetID: [String: [Int64]] = [:]

    // Colors de styles (clé = ConcertGenre.rawValue, valeur = hex 0xRRGGBB).
    var genreColors: [String: UInt32] = [:]

    // Preferences utilisateur "data-style" (les préférences système type
    // bookmark sandbox, theme, ID MIDI restent en UserDefaults).
    var selectedConcertGenreRaw: String = ConcertGenre.all.rawValue

    /// Mode sécurisé : un double-clic est requis for lancer un song, et
    /// si un autre song est déjà en lecture une confirmation explicite
    /// "Replace avec fade-out" est demandée. Activé par défaut.
    var isSafePlayEnabled: Bool = true

    /// Affichage de la Track Library rapide en colonne gauche du Show.
    /// Pendant un concert on veut souvent voir le show sur tout l'écran,
    /// la colonne se masque avec ⌘B.
    var isQuickLibraryVisible: Bool = true

    /// Bornes de lecture (trimStart / trimEnd) définies par l'utilisateur
    /// dans VELVET SHOW. Indexées par `audioFileID` (en String for JSON).
    /// Si absent for un song, le fallback se fait sur le trim
    /// ShowBuddy (`LightShow.trimStart` / `trimEnd`).
    var trimsByAudioFileID: [String: VelvetTrackTrim] = [:]

    /// Volume non destructif par song, indexé par `audioFileID`.
    /// Valeur absente = 0 dB.
    var volumeByAudioFileID: [String: VelvetTrackVolume] = [:]

    /// Cible de normalisation loudness globale (LUFS-I).
    /// Valeur par défaut : -16.0 LUFS (adapté backtracks live).
    var normTargetLUFS: Double = -16.0

    /// Normalisation active : applique le gain calculé par l'analyse LUFS
    /// au playbackGain de l'AudioEngine. Disabled par défaut.
    var isNormalizationEnabled: Bool = false

    /// BPM édité/détecté par l'utilisateur, indexé par audioFileID.
    /// Prioritaire sur VelvetTrack.tempo et LightShow.tempo.
    var tempoOverridesByAudioFileID: [String: Double] = [:]

    /// Color individuelle d'un song, indexée par `audioFileID`.
    /// Prioritaire sur la couleur de genre. Absent = couleur de genre.
    var trackColorsByAudioFileID: [String: UInt32] = [:]

    /// Vrai après la migration structurelle depuis ShowBuddy.
    /// Quand vrai, l'app ne requiert plus ShowBuddy.db au démarrage.
    var hasMigratedFromShowBuddy: Bool = false

    /// Vrai après l'import incrémental des TrimStart/TrimEnd ShowBuddy
    /// to `trimsByAudioFileID`. Jamais remis at false — migration one-shot.
    var hasImportedShowBuddyTrims: Bool = false

    /// Events MIDI migrés depuis ShowBuddy (copie Velvet, ShowBuddy.db non modifié).
    var velvetMidiEvents: [MidiEvent] = []

    /// Messages MIDI migrés depuis ShowBuddy (copie Velvet, ShowBuddy.db non modifié).
    var velvetMidiMessages: [MidiMessage] = []

    /// Cue Points placés manuellement dans l'éditeur, indexés par audioFileID.
    /// Jamais écrits dans ShowBuddy.db.
    var cuePointsByAudioFileID: [String: [CuePoint]] = [:]

    /// Velvet Trash — songs supprimés de la bibliothèque mais pas
    /// encore supprimés définitivement. Le fichier audio reste sur disque
    /// tant que `permanentlyDeleteTrashedTrack` n'est pas appelé.
    var trashedTracks: [TrashedVelvetTrack] = []

    /// Colors par show — setID (String) → audioFileID (String) → hex.
    /// Prioritaire sur `trackColorsByAudioFileID` dans la Show Library.
    var songColorsByShowID: [String: [String: UInt32]] = [:]

    /// Ordre d'affichage manuel des Shows Velvet — tableau d'IDs (Int64 négatifs).
    /// Absent du JSON existant → tableau vide → ordre de création conservé.
    var velvetShowOrder: [Int64] = []

    /// Comportement de fin par setElementID (ShowBuddy shows).
    /// Pour les Velvet shows, le comportement est stocké dans VelvetShowTrack.endBehavior.
    var endBehaviorBySetElementID: [String: TrackEndBehavior] = [:]

    /// Cache des métadonnées AudioFile ShowBuddy (nom, chemin, durée).
    /// Peuplé at chaque ouverture de ShowBuddy.db. Permet de reconstituer
    /// la Track Library au démarrage sans avoir ShowBuddy.db sous la main.
    var audioFileMetaCacheByID: [String: AudioFileMetaCache] = [:]

    /// Genres personnalisés créés par l'utilisateur.
    /// Clé = nom du genre (lowercase), valeur = couleur hex 0xRRGGBB.
    var customGenreColors: [String: UInt32] = [:]

    /// Cues MIDI placés directement sur la timeline, indexés par audioFileID.
    /// Distincts des EditableMemo : pas de texte, pas de durée, un seul trigger au `time`.
    var midiCuesByAudioFileID: [String: [TimelineMidiCue]] = [:]
    var archivedMidiEventIDs: [Int64] = []

    /// Cues OSC placés directement sur la timeline, indexés par audioFileID.
    /// Pendant OSC du V1 — coexiste avec midiCuesByAudioFileID.
    var oscCuesByAudioFileID: [String: [TimelineOscCue]] = [:]

    /// Bibliothèque d'OscEvents nommés — équivalent OSC de velvetMidiEvents.
    /// Chaque entrée porte name + category + host/port/address/value.
    var velvetOscEvents: [OscEvent] = []
}

// MARK: - Statut de sauvegarde

/// État affichable dans la toolbar. Évalué par l'UI via `store.status`.
enum VelvetShowSaveStatus: Equatable {
    case idle
    case dirty
    case saving
    case saved(Date)
    case error(String)

    var label: String {
        switch self {
        case .idle:    return "Ready"
        case .dirty:   return "Unsaved Change"
        case .saving:  return "Sauvegarde..."
        case .saved:   return "Saved"
        case .error:   return "Save Error"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:    return "circle"
        case .dirty:   return "circle.dotted"
        case .saving:  return "arrow.triangle.2.circlepath"
        case .saved:   return "checkmark.seal.fill"
        case .error:   return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Store

/// Source de vérité for la persistance Velvet Show. Une instance vit dans
/// `AppState`, exposée at l'UI via `@Observable`. Toute mutation passe par
/// `update { $0... }` — c'est ce qui déclenche le debounce d'écriture.
@MainActor
@Observable
final class VelvetShowStore {

    /// État en mémoire. Modifié uniquement via `update(_:)` for garantir
    /// que le statut bascule en `.dirty` puis `.saving` puis `.saved`.
    private(set) var state: VelvetShowState

    /// Statut affichable dans la toolbar.
    private(set) var status: VelvetShowSaveStatus = .idle

    /// URL du JSON racine. Exposé for debug / inspection.
    let fileURL: URL

    /// Dossier des pièces jointes copiées. Garanti existant at l'init.
    let attachmentsDirectoryURL: URL

    /// Dossier des fichiers audio importeds dans Velvet Show.
    let mediaDirectoryURL: URL

    /// Dossier des sauvegardes audio créées avant remplacement.
    /// Chemin : ApplicationSupport/VELVET SHOW/AudioBackups/
    /// Garanti existant at l'init.
    let audioBackupsDirectoryURL: URL

    /// Dossier des fichiers audio du projet démo.
    /// Chemin : ApplicationSupport/VELVET SHOW/DemoMedia/
    /// Créé at l'init (peut être vide ou absent si la démo n'a jamais été installée).
    let demoMediaDirectoryURL: URL

    /// Vrai si aucun VelvetShowState.json ni fichier .bak n'existaient au démarrage.
    /// Indique un premier lancement de l'application.
    private(set) var isFirstLaunch: Bool = false

    /// Tâche en cours de debouncing. Annulée at chaque nouvelle mutation
    /// for ne pas multiplier les écritures.
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// Delay de regroupement des sauvegardes successives.
    private static let debounceNanos: UInt64 = 400_000_000  // 0.4 s

    init() {
        let fm = FileManager.default
        let support: URL
        if let resolved = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            support = resolved
        } else {
            // Très improbable sur macOS, mais on garde un fallback safe
            // plutôt que de crasher au démarrage.
            support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fm.temporaryDirectory
        }

        let appDir = support.appendingPathComponent("VELVET SHOW", isDirectory: true)
        try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        let attachmentsDir = appDir.appendingPathComponent("Attachments", isDirectory: true)
        try? fm.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
        let mediaDir = appDir.appendingPathComponent("Media", isDirectory: true)
        try? fm.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        let backupsDir = appDir.appendingPathComponent("AudioBackups", isDirectory: true)
        try? fm.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        let demoMediaDir = appDir.appendingPathComponent("DemoMedia", isDirectory: true)
        // Ne pas créer DemoMedia automatiquement — il est créé uniquement lors de l'injection démo.

        let stateURL = appDir.appendingPathComponent("VelvetShowState.json")
        let bakURL   = stateURL.appendingPathExtension("bak")
        self.isFirstLaunch = !fm.fileExists(atPath: stateURL.path)
                          && !fm.fileExists(atPath: bakURL.path)

        self.fileURL = stateURL
        self.attachmentsDirectoryURL = attachmentsDir
        self.mediaDirectoryURL = mediaDir
        self.audioBackupsDirectoryURL = backupsDir
        self.demoMediaDirectoryURL = demoMediaDir

        var wasMigrated = false
        if let loaded = Self.loadFromDisk(at: self.fileURL) {
            wasMigrated = loaded.version < VelvetShowState.currentSchemaVersion
            self.state = loaded
            self.status = .saved(Date())
        } else if let loaded = Self.loadFromDisk(at: bakURL) {
            wasMigrated = loaded.version < VelvetShowState.currentSchemaVersion
            self.state = loaded
            self.status = .error("Main JSON is unreadable; data restored from the .bak backup")
        } else {
            self.state = VelvetShowState()
            self.status = .idle
        }
        self.bakURL = bakURL
        // Si le fichier sur disque était dans un schéma antérieur, on
        // sauvegarde immédiatement avec la nouvelle version for ne pas
        // rejouer la migration at chaque démarrage.
        if wasMigrated {
            Task { await performSaveAsync() }
        }
    }

    /// URL du fichier de sauvegarde de secours.
    let bakURL: URL

    // MARK: Mutation

    /// Point d'entrée unique for modifier l'état. Le bloc fournit un
    /// `inout` sur la structure, la sauvegarde est planifiée juste après.
    func update(_ mutate: (inout VelvetShowState) -> Void) {
        mutate(&state)
        scheduleSave()
    }

    // MARK: Pièces jointes

    /// Copie un fichier audio source dans `Media/` et retourne l'URL stable.
    func importMediaFile(from sourceURL: URL) throws -> URL {
        let ext = sourceURL.pathExtension
        let cleanBase = sourceURL.deletingPathExtension().lastPathComponent
        let fallbackBase = cleanBase.isEmpty ? UUID().uuidString : cleanBase
        let filename = ext.isEmpty
            ? "\(fallbackBase)-\(UUID().uuidString)"
            : "\(fallbackBase)-\(UUID().uuidString).\(ext)"
        let target = mediaDirectoryURL.appendingPathComponent(filename)

        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        try FileManager.default.copyItem(at: sourceURL, to: target)
        return target
    }

    func discardMediaFile(at url: URL) {
        guard url.path.hasPrefix(mediaDirectoryURL.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Copie un fichier source dans `Attachments/<uuid>.<ext>` et retourne
    /// l'URL stable de la copie. L'appelant fournit ensuite cette URL au
    /// `MemoAttachment` qu'il persiste — l'URL d'origine n'est jamais
    /// stockée.
    func importAttachment(from sourceURL: URL) throws -> URL {
        let ext = sourceURL.pathExtension
        let basename = UUID().uuidString
        let filename = ext.isEmpty ? basename : "\(basename).\(ext)"
        let target = attachmentsDirectoryURL.appendingPathComponent(filename)

        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        try FileManager.default.copyItem(at: sourceURL, to: target)
        return target
    }

    /// Supprime physiquement le fichier d'une pièce jointe précédemment
    /// copiée dans `Attachments/`. Utilisé par AppState quand l'utilisateur
    /// retire un attachment côté UI. Aucune erreur n'est propagée : la
    /// pièce jointe peut déjà avoir été supprimée manuellement par
    /// l'utilisateur depuis le Endder.
    func discardAttachmentFile(at url: URL) {
        guard url.path.hasPrefix(attachmentsDirectoryURL.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Sauvegarde

    /// Force une sauvegarde immédiate (utilisé par exemple at la fermeture
    /// de l'app). L'encodage reste asynchrone et off-MainActor.
    func saveNow() {
        saveTask?.cancel()
        Task { await performSaveAsync() }
    }

    /// Sauvegarde synchrone — uniquement for la terminaison de l'app.
    /// `saveNow()` repose sur une Task détachée qui ne survivrait pas at la
    /// fin du process : ici l'encodage et l'écriture bloquent le main
    /// thread (quelques ms) for garantir que rien n'est perdu au ⌘Q.
    func saveNowBlocking() {
        saveTask?.cancel()
        saveTask = nil
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.replaceItem(
                    at: bakURL,
                    withItemAt: fileURL,
                    backupItemName: nil,
                    options: [],
                    resultingItemURL: nil
                )
            }
            try data.write(to: fileURL, options: .atomic)
            status = .saved(Date())
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    private func scheduleSave() {
        status = .dirty
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: VelvetShowStore.debounceNanos)
            guard let self, !Task.isCancelled else { return }
            await self.performSaveAsync()
        }
    }

    private func performSaveAsync() async {
        // Capture de l'état sur MainActor avant de partir en background.
        let snapshot = self.state
        let fileURL  = self.fileURL
        let bakURL   = self.bakURL

        status = .saving

        // Encodage + écriture disque hors du MainActor.
        let result: Result<Void, Error> = await Task.detached(priority: .utility) {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(snapshot)
                // Copier en .bak AVANT d'écraser for récupérer si le
                // process est tué pendant l'écriture.
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try? FileManager.default.replaceItem(
                        at: bakURL,
                        withItemAt: fileURL,
                        backupItemName: nil,
                        options: [],
                        resultingItemURL: nil
                    )
                }
                try data.write(to: fileURL, options: .atomic)
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value

        // Mise at jour du statut sur MainActor.
        switch result {
        case .success:      status = .saved(Date())
        case .failure(let e): status = .error(e.localizedDescription)
        }
    }

    private static func loadFromDisk(at url: URL) -> VelvetShowState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var loaded = try? decoder.decode(VelvetShowState.self, from: data) else { return nil }
        loaded = VelvetShowState.migrate(loaded)
        return loaded
    }
}

// MARK: - Migrations de schéma

extension VelvetShowState {
    /// Applique toutes les migrations nécessaires for amener le fichier
    /// chargé depuis le disque jusqu'au schéma courant (`currentSchemaVersion`).
    ///
    /// Chaque bloc `if s.version < N` est idempotent : il n'est jamais
    /// appliqué deux fois sur le même fichier car `s.version` est mis at jour
    /// at la fin du bloc. L'ordre des blocs est garanti croissant.
    ///
    /// **Règle d'or :** ne jamais supprimer ni modifier un bloc existant.
    /// Add uniquement at la fin.
    static func migrate(_ state: VelvetShowState) -> VelvetShowState {
        var s = state

        // v0 → v1 : fichiers antérieurs at juin 2026 (champ `version` absent).
        // Aucune transformation structurelle : on appose simplement le numéro.
        if s.version < 1 {
            s.version = 1
        }

        // v1 → v2 : ajout de audioFileMetaCacheByID (Phase 1 indépendance ShowBuddy).
        // Aucune transformation : le champ est vide par défaut et sera peuplé
        // automatiquement at la prochaine ouverture de ShowBuddy.db.
        if s.version < 2 {
            s.version = 2
        }

        // v2 → v3 : ajout de customGenreColors (genres personnalisés).
        // Aucune transformation : le dictionnaire est vide par défaut.
        if s.version < 3 {
            s.version = 3
        }

        // ── Prochaines migrations ────────────────────────────────
        // if s.version < 4 {
        //     s.version = 4
        // }
        // ─────────────────────────────────────────────────────────

        return s
    }

    /// Vrai si le fichier chargé était dans une version antérieure et a
    /// été migré. Utilisé par `VelvetShowStore` for déclencher une
    /// sauvegarde immédiate après le chargement initial.
    var needsMigration: Bool {
        version < Self.currentSchemaVersion
    }
}

// MARK: - Helpers de conversion Int64 ↔ String for les clés JSON

extension Dictionary where Key == String {
    /// Retourne la map convertie en `[Int64: Value]`, en ignorant les clés
    /// non parsables comme Int64 (ne devrait pas arriver, mais on reste
    /// défensif).
    func keyedByInt64() -> [Int64: Value] {
        var result: [Int64: Value] = [:]
        for (rawKey, value) in self {
            if let id = Int64(rawKey) {
                result[id] = value
            }
        }
        return result
    }
}

extension Dictionary where Key == Int64 {
    /// Sérialise une map keyed-by-Int64 to un dict at clés String, prêt
    /// at être encodé en JSON.
    func stringKeyed() -> [String: Value] {
        var result: [String: Value] = [:]
        for (key, value) in self {
            result[String(key)] = value
        }
        return result
    }
}
