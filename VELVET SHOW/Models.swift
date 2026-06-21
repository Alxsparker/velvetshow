//
//  Models.swift
//  VELVET SHOW
//
//  Modèles Swift qui reflètent fidèlement le schéma de ShowBuddy.db.
//
//  Choix de conception :
//  - Une struct par table. Les noms restent proches de l'original SQLite
//    for limiter la friction quand on relit une requête.
//  - La plupart des champs sont Optional : un backup réel contient
//    fréquemment des NULL et on ne veut surtout pas crasher l'import.
//  - Identifiable + Hashable : pratique for les List/ForEach/Table SwiftUI.
//

import Foundation

// MARK: - AudioFiles

struct AudioFile: Identifiable, Hashable {
    let audioFileID: Int64
    let name: String?
    let path: String?
    let note: String?
    let lengthSecs: Double?
    let mainAudioFileID: Int64?

    var id: Int64 { audioFileID }
}

// MARK: - AudioFileMetaCache

/// Cache Velvet des métadonnées essentielles d'un AudioFile ShowBuddy.
/// Stocké dans VelvetShowState.json — permet at la Track Library de rester
/// fonctionnelle même si ShowBuddy.db est temporairement absente.
/// Mis at jour automatiquement at chaque ouverture de ShowBuddy.db.
struct AudioFileMetaCache: Codable, Hashable {
    var name: String
    var path: String
    var lengthSecs: Double?
}

// MARK: - LightShows

struct LightShow: Identifiable, Hashable {
    let lightShowID: Int64
    let name: String?
    let audioFileID: Int64?
    let dmxisShowName: String?
    let note: String?
    let tempo: Double?
    let trimStart: Double?
    let trimEnd: Double?
    let audioVolume: Double?

    var id: Int64 { lightShowID }
}

// MARK: - Sets

struct ShowSet: Identifiable, Hashable {
    let setID: Int64
    let name: String?
    let note: String?
    let folder: String?
    // La colonne SQL s'appelle "Type" (mot-clé Swift), on la renomme ici.
    let setType: String?

    var id: Int64 { setID }
}

// MARK: - SetElements

struct SetElement: Identifiable, Hashable {
    let setElementID: Int64
    let setID: Int64
    let lightShowID: Int64
    let playOrder: Int64?
    let note: String?
    let autoStart: Int64?
    let loop: Int64?
    let colour: String?

    var id: Int64 { setElementID }
}

// MARK: - MidiEvents

struct MidiEvent: Identifiable, Hashable, Codable {
    let midiEventID: Int64
    let name: String?
    let category: String?

    var id: Int64 { midiEventID }
}

// MARK: - MidiMessages

struct MidiMessage: Identifiable, Hashable, Codable {
    let midiMessageID: Int64
    let midiEventID: Int64?
    let time: Double?
    let outDevice: String?
    let channel: Int64?
    let message: Int64?
    let data1: Int64?
    let data2: Int64?

    var id: Int64 { midiMessageID }
}

// MARK: - ShowMemos

struct ShowMemo: Identifiable, Hashable {
    let showMemoID: Int64
    let lightShowID: Int64?
    let shortName: String?
    let memo: String?
    let memoTime: Double?
    let memoLength: Double?
    let countIn: Double?
    let startMidiEventID: Int64?
    let endMidiEventID: Int64?

    var id: Int64 { showMemoID }
}

// MARK: - Edition locale des mémos

enum MemoAttachmentType: String, CaseIterable, Identifiable, Hashable, Codable {
    case image
    case pdf
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .image: return "Image"
        case .pdf:   return "PDF"
        case .other: return "Autre"
        }
    }
}

struct MemoAttachment: Identifiable, Hashable, Codable {
    let id: UUID
    let memoID: UUID
    let fileName: String
    let fileURL: URL
    let type: MemoAttachmentType

    init(
        id: UUID = UUID(),
        memoID: UUID,
        fileName: String,
        fileURL: URL,
        type: MemoAttachmentType
    ) {
        self.id = id
        self.memoID = memoID
        self.fileName = fileName
        self.fileURL = fileURL
        self.type = type
    }
}

struct EditableMemo: Identifiable, Hashable, Codable {
    let id: UUID
    let sourceShowMemoID: Int64?
    var lightShowID: Int64?
    var shortName: String
    var memo: String
    var memoTime: Double
    var memoLength: Double
    var countIn: Double
    var startMidiEventID: Int64?
    var endMidiEventID: Int64?

    init(
        id: UUID = UUID(),
        sourceShowMemoID: Int64? = nil,
        lightShowID: Int64? = nil,
        shortName: String = "",
        memo: String = "",
        memoTime: Double = 0,
        memoLength: Double = 5,
        countIn: Double = 0,
        startMidiEventID: Int64? = nil,
        endMidiEventID: Int64? = nil
    ) {
        self.id = id
        self.sourceShowMemoID = sourceShowMemoID
        self.lightShowID = lightShowID
        self.shortName = shortName
        self.memo = memo
        self.memoTime = memoTime
        self.memoLength = memoLength
        self.countIn = countIn
        self.startMidiEventID = startMidiEventID
        self.endMidiEventID = endMidiEventID
    }

    init(showMemo: ShowMemo) {
        self.init(
            sourceShowMemoID: showMemo.showMemoID,
            lightShowID: showMemo.lightShowID,
            shortName: showMemo.shortName ?? "",
            memo: showMemo.memo ?? "",
            memoTime: showMemo.memoTime ?? 0,
            memoLength: max(1, showMemo.memoLength ?? 5),
            countIn: showMemo.countIn ?? 0,
            startMidiEventID: showMemo.startMidiEventID,
            endMidiEventID: showMemo.endMidiEventID
        )
    }

    var displayTitle: String {
        if !shortName.isEmpty { return shortName }
        if !memo.isEmpty { return String(memo.prefix(32)) }
        return "New memo"
    }

    var hasMidi: Bool {
        startMidiEventID != nil || endMidiEventID != nil
    }
}

// MARK: - Trim Velvet (non destructif)

/// Bornes de lecture définies par l'utilisateur dans VELVET SHOW.
///
// MARK: - Cue Points

/// Marqueur de navigation placé manuellement dans l'éditeur de timeline.
/// Distinct des `EditableMemo` (paroles/Prompter) : les Cue Points servent
/// exclusivement au saut et au raccourcissement en live.
struct CuePoint: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var time: Double          // secondes depuis le début du fichier (absolu, comme currentPosition)
    var colorName: String?    // nil = couleur par défaut (orange). Valeurs : "orange","blue","green","red","purple"
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String = "Cue Point",
        time: Double = 0,
        colorName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.time = time
        self.colorName = colorName
        self.createdAt = createdAt
    }
}

/// Cue MIDI placé directement sur la timeline, sans mémo texte associé.
/// Déclenche un MidiEvent at une position temporelle précise.
/// Coexiste avec EditableMemo.startMidiEventID — les deux systèmes sont indépendants.
struct TimelineMidiCue: Identifiable, Codable, Hashable {
    let id: UUID
    var time: Double       // secondes depuis le début du fichier audio (même convention que CuePoint.time)
    var midiEventID: Int64
    var label: String      // affiché sur le marqueur ; peut être vide
    var colorName: String? // nil = violet par défaut (distinct du orange des CuePoints)

    init(
        id: UUID = UUID(),
        time: Double,
        midiEventID: Int64,
        label: String = "",
        colorName: String? = nil
    ) {
        self.id          = id
        self.time        = time
        self.midiEventID = midiEventID
        self.label       = label
        self.colorName   = colorName
    }
}

/// Valeur typée optionnelle attachée à un cue OSC.
/// Couvre les 4 types courants OSC 1.0/1.1 — suffisant pour la V1.
enum OSCValue: Codable, Hashable {
    case int(Int)
    case float(Double)
    case string(String)
    case bool(Bool)

    /// Étiquette courte affichée dans l'UI (picker, marqueur).
    var typeLabel: String {
        switch self {
        case .int:    return "Int"
        case .float:  return "Float"
        case .string: return "String"
        case .bool:   return "Bool"
        }
    }

    /// Représentation lisible pour le log et le marqueur.
    var displayValue: String {
        switch self {
        case .int(let v):    return String(v)
        case .float(let v):  return String(format: "%g", v)
        case .string(let v): return "\"\(v)\""
        case .bool(let v):   return v ? "true" : "false"
        }
    }
}

/// Événement OSC nommé — équivalent OSC de `MidiEvent`.
/// Stocké dans la « Velvet OSC Library » (VelvetShowState.velvetOscEvents).
/// Une `TimelineOscCue` ne porte que la référence (`oscEventID`) ;
/// l'event lui-même définit host/port/address/value ET le nom lisible que
/// l'utilisateur manipule partout dans l'UI.
struct OscEvent: Identifiable, Codable, Hashable {
    let oscEventID: UUID
    var name: String
    var category: String?
    var host: String
    var port: Int
    var address: String
    var value: OSCValue?

    var id: UUID { oscEventID }

    init(
        oscEventID: UUID = UUID(),
        name: String,
        category: String? = nil,
        host: String = "127.0.0.1",
        port: Int = 8000,
        address: String = "/cue/scene/1",
        value: OSCValue? = nil
    ) {
        self.oscEventID = oscEventID
        self.name = name
        self.category = category
        self.host = host
        self.port = port
        self.address = address
        self.value = value
    }
}

/// Cue OSC placée directement sur la timeline.
/// Frère de `TimelineMidiCue` : même mécanique de déclenchement par
/// `tickMidiScheduler`. Référence un `OscEvent` nommé par `oscEventID`.
///
/// Décodage rétro-compatible : si l'ancien JSON portait des champs inline
/// (host/port/address/value), ils sont relus dans `legacyInline` et la cue
/// est migrée à la prochaine ouverture par `AppState.migrateLegacyOscCues()`.
/// Le ré-encodage ne sérialise jamais les champs legacy.
struct TimelineOscCue: Identifiable, Codable, Hashable {
    let id: UUID
    var time: Double           // secondes depuis le début du fichier audio
    var oscEventID: UUID?      // réf vers OscEvent ; nil = cue legacy à migrer
    var label: String          // affiché sur le marqueur ; vide → event.name
    var colorName: String?     // nil = teal par défaut

    /// Champs inline lus depuis l'ancien format. Présent uniquement jusqu'à
    /// la passe de migration AppState. Jamais ré-encodé.
    var legacyInline: LegacyInline?

    struct LegacyInline: Hashable {
        var host: String
        var port: Int
        var address: String
        var value: OSCValue?
    }

    init(
        id: UUID = UUID(),
        time: Double,
        oscEventID: UUID? = nil,
        label: String = "",
        colorName: String? = nil
    ) {
        self.id          = id
        self.time        = time
        self.oscEventID  = oscEventID
        self.label       = label
        self.colorName   = colorName
        self.legacyInline = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, time, oscEventID, label, colorName
        // Legacy keys (in-line storage) — read-only.
        case host, port, address, value
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self,    forKey: .id)
        time      = try c.decode(Double.self,  forKey: .time)
        label     = try c.decodeIfPresent(String.self,    forKey: .label)     ?? ""
        colorName = try c.decodeIfPresent(String.self,    forKey: .colorName)
        if let eid = try c.decodeIfPresent(UUID.self, forKey: .oscEventID) {
            oscEventID   = eid
            legacyInline = nil
        } else if let host = try c.decodeIfPresent(String.self, forKey: .host) {
            // Ancien format : champs inline → on les conserve pour migration.
            let port    = try c.decodeIfPresent(Int.self,      forKey: .port)    ?? 8000
            let address = try c.decodeIfPresent(String.self,   forKey: .address) ?? "/cue"
            let value   = try c.decodeIfPresent(OSCValue.self, forKey: .value)
            oscEventID  = nil
            legacyInline = LegacyInline(host: host, port: port, address: address, value: value)
        } else {
            oscEventID   = nil
            legacyInline = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,   forKey: .id)
        try c.encode(time, forKey: .time)
        try c.encodeIfPresent(oscEventID, forKey: .oscEventID)
        try c.encode(label, forKey: .label)
        try c.encodeIfPresent(colorName, forKey: .colorName)
        // Les champs legacy ne sont jamais ré-écrits.
    }
}

/// Color d'un Cue Point — un petit ensemble fixe for rester simple.
enum CuePointColor: String, CaseIterable {
    case orange, blue, green, red, purple

    var displayName: String {
        switch self {
        case .orange: return "Orange"
        case .blue:   return "Bleu"
        case .green:  return "Vert"
        case .red:    return "Rouge"
        case .purple: return "Violet"
        }
    }

    static let `default` = CuePointColor.orange
}

/// Stocké at part des données ShowBuddy : aucune écriture sur ShowBuddy.db
/// ni sur le fichier audio. Si présent for un `audioFileID`, ces bornes
/// remplacent celles éventuellement définies dans `LightShow` côté
/// ShowBuddy (fallback). `trimEnd == 0` = pas de trim de fin (on lit
/// jusqu'à la fin du fichier).
struct VelvetTrackTrim: Codable, Hashable {
    var audioFileID: Int64
    var trimStart: TimeInterval
    var trimEnd: TimeInterval
    var updatedAt: Date

    init(
        audioFileID: Int64,
        trimStart: TimeInterval = 0,
        trimEnd: TimeInterval = 0,
        updatedAt: Date = Date()
    ) {
        self.audioFileID = audioFileID
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.updatedAt = updatedAt
    }
}

/// Réglage de volume non destructif défini dans VELVET SHOW.
/// Le fichier audio original n'est jamais modifié : on stocke uniquement
/// un offset en dB, appliqué par `AudioEngine` au chargement et en temps réel.
struct VelvetTrackVolume: Codable, Hashable {
    static let minimumDB: Double = -12
    static let maximumDB: Double = 12

    var audioFileID: Int64
    var volumeOffsetDB: Double
    var updatedAt: Date

    /// Loudness intégré mesuré (LUFS-I, EBU R128). Nil si non analysé.
    var measuredLUFS: Double?
    /// True Peak mesuré via sur-échantillonnage ×4 (dBTP). Nil si non analysé.
    var measuredTruePeakDB: Double?
    /// Peak PCM brut (max absolu avant sur-échantillonnage, dBFS). Diagnostic.
    var measuredPcmPeakDB: Double?
    /// Gain de normalisation recommandé (dB) for atteindre `normTarget`.
    /// S'additionne at `volumeOffsetDB` (correction manuelle) au moment de la lecture.
    var normGainDB: Double?
    /// Cible LUFS utilisée lors du calcul de `normGainDB` (ex: -16.0).
    var normTarget: Double?
    /// Date de la dernière analyse loudness.
    var normAnalysedAt: Date?

    init(
        audioFileID: Int64,
        volumeOffsetDB: Double = 0,
        updatedAt: Date = Date(),
        measuredLUFS: Double? = nil,
        measuredTruePeakDB: Double? = nil,
        measuredPcmPeakDB: Double? = nil,
        normGainDB: Double? = nil,
        normTarget: Double? = nil,
        normAnalysedAt: Date? = nil
    ) {
        self.audioFileID        = audioFileID
        self.volumeOffsetDB     = Self.clamped(volumeOffsetDB)
        self.updatedAt          = updatedAt
        self.measuredLUFS       = measuredLUFS
        self.measuredTruePeakDB = measuredTruePeakDB
        self.measuredPcmPeakDB  = measuredPcmPeakDB
        self.normGainDB         = normGainDB
        self.normTarget         = normTarget
        self.normAnalysedAt     = normAnalysedAt
    }

    static func clamped(_ value: Double) -> Double {
        min(maximumDB, max(minimumDB, value))
    }
}

// MARK: - Concert V2 local

enum TrackEndBehavior: String, Codable {
    case autoStop
    case autoNextFilter
    case autoNextFade
    case autoNextSlowFade
    case smart
}

enum QueuePlaybackMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case automatic
    case manual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "Auto"
        case .manual:    return "Manuel"
        }
    }
}

struct VelvetTrack: Identifiable, Codable, Hashable {
    let id: Int64
    var title: String
    var genre: String
    var note: String
    var colorHex: UInt32?
    var tempo: Double?
    var fileURL: URL
    var duration: Double?
    let importedAt: Date

    init(
        id: Int64,
        title: String,
        genre: String = "Velvet",
        note: String = "",
        colorHex: UInt32? = nil,
        tempo: Double? = nil,
        fileURL: URL,
        duration: Double? = nil,
        importedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.genre = genre
        self.note = note
        self.colorHex = colorHex
        self.tempo = tempo
        self.fileURL = fileURL
        self.duration = duration
        self.importedAt = importedAt
    }
}

/// Snapshot complet d'un VelvetTrack déplacé dans la Velvet Trash.
///
/// Le fichier audio n'est PAS supprimé immédiatement : il reste sur disque
/// tant que la suppression définitive n'a pas été confirmée depuis la
/// Corbeille. Cela permet la restauration complète (données + audio).
///
/// Règle : jamais supprimer automatiquement. L'utilisateur décide.
struct TrashedVelvetTrack: Identifiable, Codable, Hashable {
    let id:        UUID
    let trashedAt: Date

    // Velvet Song d'origine
    let track: VelvetTrack

    // Snapshot de toutes les données Velvet associées
    let memos:     [EditableMemo]
    let cuePoints: [CuePoint]
    let trim:      VelvetTrackTrim?
    let volume:    VelvetTrackVolume?
    let colorHex:  UInt32?

    init(
        track:     VelvetTrack,
        memos:     [EditableMemo]    = [],
        cuePoints: [CuePoint]        = [],
        trim:      VelvetTrackTrim?  = nil,
        volume:    VelvetTrackVolume? = nil,
        colorHex:  UInt32?           = nil
    ) {
        self.id        = UUID()
        self.trashedAt = Date()
        self.track     = track
        self.memos     = memos
        self.cuePoints = cuePoints
        self.trim      = trim
        self.volume    = volume
        self.colorHex  = colorHex
    }
}

struct VelvetShowTrack: Identifiable, Hashable {
    let id: Int64
    let audioFileID: Int64
    var playbackMode: QueuePlaybackMode
    var endBehavior: TrackEndBehavior
    let createdAt: Date

    init(
        id: Int64,
        audioFileID: Int64,
        playbackMode: QueuePlaybackMode = .manual,
        endBehavior: TrackEndBehavior = .autoStop,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.audioFileID = audioFileID
        self.playbackMode = playbackMode
        self.endBehavior = endBehavior
        self.createdAt = createdAt
    }
}

extension VelvetShowTrack: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, audioFileID, playbackMode, endBehavior, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(Int64.self, forKey: .id)
        audioFileID  = try c.decode(Int64.self, forKey: .audioFileID)
        playbackMode = try c.decodeIfPresent(QueuePlaybackMode.self,   forKey: .playbackMode) ?? .manual
        endBehavior  = try c.decodeIfPresent(TrackEndBehavior.self,    forKey: .endBehavior)  ?? .autoStop
        createdAt    = try c.decodeIfPresent(Date.self,                forKey: .createdAt)    ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,           forKey: .id)
        try c.encode(audioFileID,  forKey: .audioFileID)
        try c.encode(playbackMode, forKey: .playbackMode)
        try c.encode(endBehavior,  forKey: .endBehavior)
        try c.encode(createdAt,    forKey: .createdAt)
    }
}

struct VelvetShow: Identifiable, Hashable {
    let id: Int64
    var name: String
    var note: String
    var colorHex: UInt32
    var tracks: [VelvetShowTrack]
    /// Dossier d'origine (ShowBuddy) ou nil for les shows créés dans Velvet.
    var folder: String?
    let createdAt: Date

    init(
        id: Int64,
        name: String,
        note: String = "",
        colorHex: UInt32 = 0x00C8FF,
        tracks: [VelvetShowTrack] = [],
        folder: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.colorHex = colorHex
        self.tracks = tracks
        self.folder = folder
        self.createdAt = createdAt
    }
}

extension VelvetShow: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, note, colorHex, tracks, folder, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(Int64.self,            forKey: .id)
        name      = try c.decode(String.self,           forKey: .name)
        note      = try c.decodeIfPresent(String.self,  forKey: .note) ?? ""
        colorHex  = try c.decode(UInt32.self,           forKey: .colorHex)
        tracks    = try c.decodeIfPresent([VelvetShowTrack].self, forKey: .tracks) ?? []
        folder    = try c.decodeIfPresent(String.self,  forKey: .folder)
        createdAt = try c.decodeIfPresent(Date.self,    forKey: .createdAt) ?? Date()
    }
}

struct ConcertQueueItem: Identifiable, Codable, Hashable {
    let id: UUID
    let setID: Int64
    let setElementID: Int64?
    let audioFileID: Int64
    var playbackMode: QueuePlaybackMode
    let createdAt: Date

    init(
        id: UUID = UUID(),
        setID: Int64,
        setElementID: Int64? = nil,
        audioFileID: Int64,
        playbackMode: QueuePlaybackMode = .manual,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.setID = setID
        self.setElementID = setElementID
        self.audioFileID = audioFileID
        self.playbackMode = playbackMode
        self.createdAt = createdAt
    }
}

struct ConcertPlayedTrack: Identifiable, Codable, Hashable {
    let id: UUID
    let audioFileID: Int64
    let title: String
    let genre: String
    let playedAt: Date
    let playPosition: Int

    init(
        id: UUID = UUID(),
        audioFileID: Int64,
        title: String,
        genre: String,
        playedAt: Date = Date(),
        playPosition: Int
    ) {
        self.id = id
        self.audioFileID = audioFileID
        self.title = title
        self.genre = genre
        self.playedAt = playedAt
        self.playPosition = playPosition
    }

    private enum CodingKeys: String, CodingKey {
        case id, audioFileID, title, genre, playedAt, playPosition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        audioFileID = try container.decode(Int64.self, forKey: .audioFileID)
        title = try container.decode(String.self, forKey: .title)
        genre = try container.decode(String.self, forKey: .genre)
        playedAt = try container.decode(Date.self, forKey: .playedAt)
        playPosition = try container.decodeIfPresent(Int.self, forKey: .playPosition) ?? 0
    }
}

struct ConcertHistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let setID: Int64
    let setName: String
    let startedAt: Date
    var playedTracks: [ConcertPlayedTrack]

    init(
        id: UUID = UUID(),
        setID: Int64,
        setName: String,
        startedAt: Date = Date(),
        playedTracks: [ConcertPlayedTrack] = []
    ) {
        self.id = id
        self.setID = setID
        self.setName = setName
        self.startedAt = startedAt
        self.playedTracks = playedTracks
    }
}

struct TrackPlayStat: Identifiable, Hashable {
    let audioFileID: Int64
    let title: String
    let count: Int
    let lastPlayedAt: Date?

    var id: Int64 { audioFileID }
}

enum TrackRiskLevel: Hashable {
    case unknown
    case recent
    case sixMonths(months: Int)
    case oneYear(months: Int)

    var label: String {
        switch self {
        case .unknown:
            return "Never played"
        case .recent:
            return "Played recently"
        case .sixMonths:
            return "Not played in 6 months"
        case .oneYear:
            return "Not played in 1 year"
        }
    }

    var symbol: String {
        switch self {
        case .unknown:
            return "Never played"
        case .recent:
            return "✓"
        case .sixMonths:
            return "⚠️"
        case .oneYear:
            return "⚠️⚠️"
        }
    }

    var detail: String {
        switch self {
        case .sixMonths(let months), .oneYear(let months):
            return "\(label) (\(months) months)"
        default:
            return label
        }
    }
}

// MARK: - Mode bibliothèque (architecture haut niveau)

/// Les deux modes principaux de VELVET SHOW, inspirés de ShowBuddy.
///
/// - `trackLibrary` : organisation par MORCEAU. Mode d'édition / préparation.
///                    On voit la fiche d'un song (paroles, mémos, MIDI, trim...).
/// - `showLibrary`  : organisation par SET. Mode performance / setlist.
///                    On voit la liste ordonnée des songs d'un show.
enum LibraryMode: String, CaseIterable, Identifiable, Hashable {
    case trackLibrary
    case showLibrary

    var id: String { rawValue }

    var label: String {
        switch self {
        case .trackLibrary: return "Songs"
        case .showLibrary:  return "Shows"
        }
    }

    var systemImage: String {
        switch self {
        case .trackLibrary: return "music.note.house"
        case .showLibrary:  return "rectangle.stack.badge.play"
        }
    }
}

// MARK: - Catégorie de la Track Library

/// Regroupement des `AudioFile` par dossier, déduit de leur `Path`.
/// Sert at organiser la première colonne de la Track Library
/// (à la manière des dossiers Source dans Music.app).
struct TrackCategory: Identifiable, Hashable {
    /// Nom affiché en sidebar (le dernier composant du dossier parent).
    let name: String
    /// Les songs de cette catégorie, déjà triés par nom.
    let tracks: [AudioFile]

    /// L'identifiant est le nom lui-même : deux paths qui retombent sur le
    /// même dossier sont fusionnés en une seule catégorie.
    var id: String { name }
}

// MARK: - Agrégat for le tableau de bord

/// Compteurs affichés dans le bandeau "vue d'ensemble" de la fenêtre.
struct LibraryStats: Equatable {
    var audioFiles: Int = 0
    var lightShows: Int = 0
    var sets: Int = 0
    var setElements: Int = 0
    var midiEvents: Int = 0
    var midiMessages: Int = 0
    var showMemos: Int = 0
}

// MARK: - Filtres concert

enum ConcertGenre: String, CaseIterable, Identifiable, Hashable, Codable {
    case all
    case rock
    case disco
    case electro
    case funk
    case lounge
    case jazz
    case sax
    case ambiance
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:      return "Tous"
        case .rock:     return "Rock"
        case .disco:    return "Disco"
        case .electro:  return "Electro"
        case .funk:     return "Funk"
        case .lounge:   return "Lounge"
        case .jazz:     return "Jazz"
        case .sax:      return "Sax"
        case .ambiance: return "Ambiance"
        case .other:    return "Autres"
        }
    }

    /// Color d'affichage par défaut.
    /// Source unique : `VSColor.Tile` dans DesignSystem.swift.
    /// Surchargée par l'utilisateur via `VelvetShowState.genreColors`.
    var defaultColorHex: UInt32 { VSColor.Tile.color(for: self).hexComponents }
}

// MARK: - Interprétation lisible d'un MidiMessage
//
// Phase MIDI 0 : on n'envoie rien, mais on doit pouvoir lire les messages
// stockés dans la base ShowBuddy comme un humain les lirait sur un patch
// MIDI. Le champ `Message` de la table est le high nibble du status byte :
//
//   - 192 (0xC0) → Program Change
//   - 144 (0x90) → Note On
//   - 128 (0x80) → Note Off
//   - 176 (0xB0) → Control Change
//   - 224 (0xE0) → Pitch Bend
//   - 208 (0xD0) → Channel Pressure
//
// Pour chaque type, `data1` et `data2` ont un sens différent (note/vélocité,
// CC#/valeur, etc.). On expose ici deux propriétés utilitaires :
//   - `kindLabel` : le nom du type seul, for les tags d'UI ;
//   - `humanDescription` : la phrase complète, telle qu'on la veut dans
//     le log de simulation.

extension MidiMessage {

    /// Nom court du type de message MIDI ("Program Change", etc.).
    var kindLabel: String {
        switch message ?? -1 {
        case 192: return "Program Change"
        case 144: return "Note On"
        case 128: return "Note Off"
        case 176: return "Control Change"
        case 224: return "Pitch Bend"
        case 208: return "Channel Pressure"
        default:  return "Message \(message.map(String.init) ?? "?")"
        }
    }

    /// Channel MIDI tel qu'affiché dans ShowBuddy (1-indexé).
    ///
    /// La base ShowBuddy stocke les canaux sur la convention "wire"
    /// (0-15) — la convention MIDI brute. L'UI ShowBuddy et la spec
    /// MaestroDMX raisonnent en 1-16. Pour rester fidèle at ce que tu
    /// vois dans ShowBuddy, on ajoute +1 partout côté affichage.
    /// La valeur brute reste accessible via `channel` for les colonnes
    /// "raw" du panneau de debug et, plus tard, for l'envoi CoreMIDI.
    var displayChannel: Int? {
        channel.map { Int($0) + 1 }
    }

    /// Phrase complète prête for l'affichage / le log, format identique
    /// aux exemples du cahier des charges Phase MIDI 0 :
    ///   "Program Change canal 1 valeur 4 to CQ18T - MIDI"
    ///   "Note On channel 16 note 50 velocity 0 to USB MIDI Interface"
    ///
    /// Le canal est affiché en convention 1–16 (`displayChannel`), pas
    /// la valeur brute 0–15 stockée en base.
    var humanDescription: String {
        let ch     = displayChannel.map(String.init) ?? "?"
        let d1     = data1.map(String.init)          ?? "?"
        let d2     = data2.map(String.init)          ?? "?"
        let device = outDevice ?? "(device ?)"

        switch message ?? -1 {
        case 192: // Program Change : un seul data byte significatif
            return "Program Change channel \(ch) value \(d1) to \(device)"
        case 144: // Note On : data1 = note, data2 = vélocité
            return "Note On channel \(ch) note \(d1) velocity \(d2) to \(device)"
        case 128: // Note Off : data1 = note, data2 = velocity de release
            return "Note Off channel \(ch) note \(d1) velocity \(d2) to \(device)"
        case 176: // Control Change : data1 = CC#, data2 = valeur
            return "Control Change channel \(ch) CC \(d1) value \(d2) to \(device)"
        case 224: // Pitch Bend : (LSB, MSB)
            return "Pitch Bend channel \(ch) LSB \(d1) MSB \(d2) to \(device)"
        case 208: // Channel Pressure (aftertouch) : un seul data byte
            return "Channel Pressure channel \(ch) value \(d1) to \(device)"
        default:
            return "\(kindLabel) channel \(ch) data1 \(d1) data2 \(d2) to \(device)"
        }
    }
}

// MARK: - Décodage sémantique MaestroDMX
//
// Tout le pilotage MaestroDMX passe par le canal 16 (MIDI Input
// Specification, MaestroDMX User Manual v1.5). Quand un MidiMessage
// vise ce canal, on peut traduire le couple (note/CC, value) en
// intention humaine — Play, Stop, Select Cue N, Global Brightness X%,
// etc. — au lieu du brut "Note On note 50".
//
// Cette extension n'envoie rien, ne dépend ni de CoreMIDI ni d'un device :
// c'est pur look-up sur la table de la spec. Renvoie nil si le message
// ne cible pas MaestroDMX ou si la note/CC est inconnue → l'UI continue
// alors d'afficher uniquement `humanDescription`.

extension MidiMessage {

    /// Description MaestroDMX si le message correspond at la spec MIDI
    /// (canal 16 + note/CC connus). nil sinon (ex. cible CQ18T mixer).
    var maestroDescription: String? {
        guard displayChannel == 16 else { return nil }
        switch message ?? -1 {
        case 144: return maestroNoteDescription
        case 176: return maestroControlChangeDescription
        default:  return nil
        }
    }

    /// Mappings Note On → action MaestroDMX. Spec v1.5 :
    ///   11..28   = transport + trigger buttons
    ///   29..127  = sélection directe Cue 1..98 (Cue = note - 28)
    /// Une velocity 0 sur Note On = release (convention MIDI standard,
    /// utilisée par les MIDI Chunks de ShowBuddy for faire "press / release").
    private var maestroNoteDescription: String? {
        guard let note = data1 else { return nil }
        let isRelease = (data2 ?? 0) == 0
        let suffix    = isRelease ? " (release)" : ""

        let action: String?
        switch note {
        case 11:        action = "Play/Pause"
        case 12:        action = "Strobe Toggle"
        case 13:        action = "Blackout Toggle"
        case 14:        action = "Blinder Toggle"
        case 15:        action = "Fog Toggle"
        case 16:        action = "Effect Toggle"
        case 17:        action = "Load Previous Show"
        case 18:        action = "Load Next Show"
        case 19:        action = "Blackout Momentary"
        case 20:        action = "Blinder Momentary"
        case 21:        action = "Strobe Momentary"
        case 22:        action = "Fog Momentary"
        case 23:        action = "Effect Momentary"
        case 24:        action = "Previous Cue"
        case 25:        action = "Next Cue"
        case 26:        action = "Play"
        case 27:        action = "Pause"
        case 28:        action = "Stop"
        case 29...127:  action = "Select Cue \(note - 28)"
        default:        action = nil
        }
        return action.map { $0 + suffix }
    }

    /// Mappings Control Change → action MaestroDMX. Spec v1.5 :
    ///   CC 0       = Show Select (data2 = index)
    ///   CC 14..21  = global brightness + strobe/blinder/fog
    ///   CC 30..37  = Fixture Group 1 (Bright, Excite, Bgnd, MoverRange,
    ///                MoverSpeed, Pattern, Color Palette, FX Palette)
    ///   CC 40..47  = Group 2 (mêmes 8 paramètres)
    ///   CC 50..57  = Group 3
    ///   CC 60..67  = Group 4
    ///
    /// Pour les CC continus on affiche un % indicatif (value / 127 × 100).
    /// Pour les CC d'index (Pattern / Palette / FX / Show Select) on
    /// affiche la valeur brute, qui est 1-indexée côté MaestroDMX.
    private var maestroControlChangeDescription: String? {
        guard let cc = data1 else { return nil }
        let value   = data2 ?? 0
        let percent = Int((Double(value) / 127.0 * 100.0).rounded())

        switch cc {
        case 0:  return "Show Select #\(value)"
        case 14: return "Global Brightness ≈ \(percent)%"
        case 15: return "Strobe Rate ≈ \(percent)%"
        case 16: return "Strobe Brightness ≈ \(percent)%"
        case 17: return "Blinder Brightness ≈ \(percent)%"
        case 18: return "Fog Volume ≈ \(percent)%"
        case 19: return "Fog Duration ≈ \(percent)%"
        case 20: return "Fog Interval ≈ \(percent)%"
        case 21: return "Fog Speed ≈ \(percent)%"
        case 30...37: return groupCC(group: 1, base: 30, cc: cc, value: value, percent: percent)
        case 40...47: return groupCC(group: 2, base: 40, cc: cc, value: value, percent: percent)
        case 50...57: return groupCC(group: 3, base: 50, cc: cc, value: value, percent: percent)
        case 60...67: return groupCC(group: 4, base: 60, cc: cc, value: value, percent: percent)
        default:      return nil
        }
    }

    /// Helper : for un Fixture Group N, l'offset du CC dans la base
    /// donne directement le paramètre (8 paramètres ordonnés).
    private func groupCC(
        group: Int, base: Int64, cc: Int64, value: Int64, percent: Int
    ) -> String {
        let labels = [
            "Brightness", "Excitement", "Background",
            "Mover Range", "Mover Speed",
            "Pattern", "Color Palette", "FX Palette",
        ]
        let idx = Int(cc - base)
        guard labels.indices.contains(idx) else {
            return "Group \(group) CC \(cc) = \(value)"
        }
        let label = labels[idx]
        // Pattern / Color Palette / FX Palette = sélecteurs 1-indexés
        // (la spec dit "Pattern, Color Palette, and FX Palette are
        //  indexed by a value of 1").
        if idx >= 5 {
            return "Group \(group) \(label) #\(value)"
        }
        return "Group \(group) \(label) ≈ \(percent)%"
    }
}

// MARK: - MIDI Log Simulator
//
// Une entrée du journal de simulation. On capture l'instant for pouvoir
// l'afficher en tête de ligne et savoir dans quel ordre l'utilisateur a
// déclenché ses "envois fictifs".

struct MidiLogEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let text: String
}

// MARK: - Vue agrégée d'un song dans un set

/// Représente une ligne dans la table des songs d'un set, en réunissant
/// les trois entités liées : l'élément du set, le show (LightShow) et le
/// fichier audio associé.
struct Song: Identifiable, Hashable {
    let element: SetElement
    let show: LightShow?
    let audio: AudioFile?
    var isLiveAdded: Bool = false

    var id: Int64 { element.setElementID }

    /// Title principal du song.
    ///
    /// Dans ShowBuddy, `LightShows.Name` vaut très souvent "Default lightshow"
    /// — c'est le nom du show lumière DMXIS, PAS le titre du song.
    /// VELVET SHOW se concentrant sur audio + MIDI, on prend toujours
    /// `AudioFiles.Name` comme source de vérité.
    var title: String {
        audio?.name ?? "Untitled"
    }

    /// Nom du LightShow ShowBuddy associé. Conservé uniquement comme
    /// information technique secondaire (à afficher dans un panneau de
    /// détail plus tard) — on ne le montre PAS dans la liste principale.
    var lightShowName: String? {
        show?.name
    }

    /// Duration formatée mm:ss at partir de lengthSecs (un Double dans la DB).
    var duration: String {
        guard let seconds = audio?.lengthSecs, seconds > 0 else { return "—" }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Ajout live local dans un show

struct LiveShowAddition: Identifiable, Codable, Hashable {
    let id: Int64
    let setID: Int64
    let audioFileID: Int64
    let anchorSetElementID: Int64?
    let createdAt: Date
}
