//
//  PrompterShared.swift
//  VELVET SHOW  /  Velvet Remote
//
//  Types cross-platform partagés entre la target Mac et la target iOS.
//  Aucune dépendance AppKit / UIKit / AVFoundation.
//

import SwiftUI

// MARK: - RemotePlaybackState

/// État de lecture sérialisable — remplace AudioEngine.PlaybackState
/// dans PrompterPreviewView pour permettre le partage avec iOS.
enum RemotePlaybackState: String, Codable, Equatable {
    case playing, paused, stopping, stopped
}

#if os(macOS)
import Foundation // AudioEngine est macOS-only
extension RemotePlaybackState {
    init(_ state: AudioEngine.PlaybackState) {
        switch state {
        case .playing:  self = .playing
        case .paused:   self = .paused
        case .stopping: self = .stopping
        case .stopped:  self = .stopped
        }
    }
}
#endif

// MARK: - PrompterPalette

/// Palette visuelle du prompteur — déplacée ici depuis ThemeManager.swift
/// pour être accessible sur iOS sans importer AppKit.
struct PrompterPalette: Hashable {
    let background: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
}

// MARK: - WaveformTimelineMemo

/// Métadonnées d'un mémo sur la timeline — déplacées ici depuis
/// WaveformTimelineView.swift pour être utilisables dans PrompterPreviewView
/// sur iOS (où WaveformTimelineView n'existe pas).
struct WaveformTimelineMemo: Identifiable, Hashable {
    let id: String
    let title: String
    let startTime: TimeInterval
    let duration: TimeInterval
    let hasMidi: Bool

    init(
        id: String,
        title: String,
        startTime: TimeInterval,
        duration: TimeInterval,
        hasMidi: Bool = false
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.duration = duration
        self.hasMidi = hasMidi
    }
}

// MARK: - Color(hex:)

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

// MARK: - ChordLineDetector

/// Détection de lignes d'accords dans un texte de mémo.
/// Déplacé ici depuis PrompterView.swift pour être partagé avec iOS.
struct ChordLineDetector {
    static func containsChordLines(in text: String) -> Bool {
        text.components(separatedBy: .newlines).contains { isChordLine($0) }
    }

    static func isChordLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let tokens = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return false }

        var chordTokens = 0
        var meaningfulTokens = 0
        for token in tokens {
            if isSeparator(token) { continue }
            meaningfulTokens += 1
            if isChordToken(token) { chordTokens += 1 }
        }

        guard meaningfulTokens > 0 else { return false }
        return Double(chordTokens) / Double(meaningfulTokens) >= 0.7
    }

    private static func isSeparator(_ token: String) -> Bool {
        let separators = ["|", "/", "\\", "-", "–", "—", "x2", "x3", "x4"]
        return separators.contains(token.lowercased())
    }

    private static func isChordToken(_ token: String) -> Bool {
        var cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "[]{}(),.;:|"))
        if cleaned.hasSuffix(".") { cleaned.removeLast() }
        if cleaned.uppercased() == "N.C" || cleaned.uppercased() == "NC" { return true }
        let pattern = #"^[A-Ga-g](#|b)?[0-9mMajindugsDIMNAUGSUSad#+b°øΔ()]*(/[A-Ga-g](#|b)?)?$"#
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }
}
