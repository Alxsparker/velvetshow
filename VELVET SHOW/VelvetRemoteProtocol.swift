//
//  VelvetRemoteProtocol.swift
//  VELVET SHOW
//
//  Messages JSON échangés entre le Mac (serveur) et les clients distants.
//  Chaque message est une ligne JSON terminée par \n.
//

import Foundation

// MARK: - Outbound (Mac → client)

struct RemoteSetlistSong: Codable, Identifiable {
    var id: String        // setElementID encodé en String
    var title: String
}

struct RemoteTimelineMemo: Codable, Identifiable {
    var id: String
    var title: String
    var startTime: Double
    var duration: Double
    var hasMidi: Bool
}

/// Morceau de la bibliothèque complète.
/// Transmis une seule fois à la connexion, puis à chaque changement réel de la bibliothèque.
struct RemoteTrackInfo: Codable, Identifiable {
    var id: Int64      // audioFileID
    var title: String
}

struct RemoteLibraryUpdate: Codable {
    var type: String = "libraryUpdate"
    var tracks: [RemoteTrackInfo]
}

struct RemoteStateUpdate: Codable {
    var type: String = "stateUpdate"
    var songTitle: String?
    var nextSongTitle: String?
    var memoText: String?
    var playbackState: RemotePlaybackState
    var positionSeconds: Double
    var durationSeconds: Double
    var timelineMemos: [RemoteTimelineMemo] = []
    var afterNextSongTitle: String? = nil
    var upcomingSetlist: [RemoteSetlistSong] = []
    var queue: [RemoteSetlistSong] = []     // queue courante, dans l'ordre
    var queuedAudioFileIDs: [Int64] = []   // audioFileIDs en queue — détection doublons côté Remote
}

// Décodage robuste dans une extension : les champs non-optionnels à valeur par défaut sont traités
// avec decodeIfPresent pour tolérer les binaires Mac plus anciens qui ne les envoient pas.
// Placer l'init dans une extension préserve l'init memberwize synthétisé utilisé par AppState.
extension RemoteStateUpdate {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type               = try c.decodeIfPresent(String.self,               forKey: .type)               ?? "stateUpdate"
        songTitle          = try c.decodeIfPresent(String.self,               forKey: .songTitle)
        nextSongTitle      = try c.decodeIfPresent(String.self,               forKey: .nextSongTitle)
        memoText           = try c.decodeIfPresent(String.self,               forKey: .memoText)
        playbackState      = try c.decode(         RemotePlaybackState.self,  forKey: .playbackState)
        positionSeconds    = try c.decode(         Double.self,               forKey: .positionSeconds)
        durationSeconds    = try c.decode(         Double.self,               forKey: .durationSeconds)
        timelineMemos      = try c.decodeIfPresent([RemoteTimelineMemo].self, forKey: .timelineMemos)      ?? []
        afterNextSongTitle = try c.decodeIfPresent(String.self,               forKey: .afterNextSongTitle)
        upcomingSetlist    = try c.decodeIfPresent([RemoteSetlistSong].self,  forKey: .upcomingSetlist)    ?? []
        queue              = try c.decodeIfPresent([RemoteSetlistSong].self,  forKey: .queue)              ?? []
        queuedAudioFileIDs = try c.decodeIfPresent([Int64].self,              forKey: .queuedAudioFileIDs) ?? []
    }
}

struct RemotePing: Codable {
    var type: String = "ping"
    var timestamp: Double = Date().timeIntervalSince1970
}

// MARK: - Inbound (client → Mac)  — réservé Étape 4

struct RemoteCommand: Codable {
    var type: String       // "playPause" | "next" | "stop" | "panic"
}
