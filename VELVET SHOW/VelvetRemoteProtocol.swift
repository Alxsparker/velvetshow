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
}

struct RemotePing: Codable {
    var type: String = "ping"
    var timestamp: Double = Date().timeIntervalSince1970
}

// MARK: - Inbound (client → Mac)  — réservé Étape 4

struct RemoteCommand: Codable {
    var type: String       // "playPause" | "next" | "stop" | "panic"
}
