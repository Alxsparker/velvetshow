//
//  DemoContent.swift
//  VELVET SHOW
//
//  Infrastructure du projet démo — manifest, plages d'IDs réservées,
//  accès UserDefaults. Aucune injection automatique ici.
//

import Foundation

// MARK: - Errors d'installation démo

enum DemoInstallError: LocalizedError {
    case jsonNotFound
    case idCollision
    case audioFileMissing(String)

    var errorDescription: String? {
        switch self {
        case .jsonNotFound:         return "DemoVelvetShowState.json introuvable dans le bundle."
        case .idCollision:          return "Demo IDs already exist in your data; installation was cancelled."
        case .audioFileMissing(let f): return "Demo audio file not found in the bundle: \(f)"
        }
    }
}

// MARK: - Plages d'IDs réservées for le contenu démo
//
//  Ces plages ne doivent JAMAIS être utilisées for des entités créées par
//  l'utilisateur. Les IDs native Velvet (hors démo) partent de -1 et
//  décroissent librement tant qu'ils restent hors de ces plages.
//
//  -1_000_001 ... -1_000_999  →  VelvetTrack démo (audioFileID)
//  -2_000_001 ... -2_000_999  →  MidiEvent démo
//  -3_000_001 ... -3_000_999  →  VelvetShow démo
//  -4_000_001 ... -4_000_999  →  VelvetShowTrack slot démo
//
//  Les fonctions next*ID() dans AppState sautent ces plages automatiquement.

enum DemoIDRange {
    /// IDs de VelvetTrack (audioFileID) réservés for la démo.
    static let tracks:     ClosedRange<Int64> = -1_000_999 ... -1_000_001
    /// IDs de MidiEvent réservés for la démo.
    static let events:     ClosedRange<Int64> = -2_000_999 ... -2_000_001
    /// IDs de VelvetShow réservés for la démo.
    static let shows:      ClosedRange<Int64> = -3_000_999 ... -3_000_001
    /// IDs de slot VelvetShowTrack réservés for la démo.
    static let showTracks: ClosedRange<Int64> = -4_000_999 ... -4_000_001
}

// MARK: - Manifest

/// Inventaire de toutes les entités injectées par le projet démo.
/// Stocké en JSON dans UserDefaults. Absent = aucune démo installée.
struct DemoContentManifest: Codable, Equatable {
    /// Numéro de version du contenu démo (incrémenté at chaque mise at jour du bundle).
    var version:        Int
    /// IDs de VelvetShow créés for la démo.
    var showIDs:        [Int64]
    /// IDs de VelvetTrack (audioFileID) créés for la démo.
    var trackIDs:       [Int64]
    /// IDs de MidiEvent créés for la démo.
    var midiEventIDs:   [Int64]
    /// Noms de fichiers audio copiés dans App Support/DemoMedia/.
    var mediaFileNames: [String]
}

// MARK: - Store

/// Accès partagé au manifest démo dans UserDefaults.
/// Non-Observable : AppState expose `demoManifest` comme propriété reactive.
final class DemoContentStore {
    static let shared = DemoContentStore()
    private init() {}

    private let manifestKey = "demoManifest"
    private let versionKey  = "demoContentVersion"

    // MARK: Lecture / écriture manifest

    var manifest: DemoContentManifest? {
        get {
            guard let data = UserDefaults.standard.data(forKey: manifestKey) else { return nil }
            return try? JSONDecoder().decode(DemoContentManifest.self, from: data)
        }
        set {
            guard let m = newValue,
                  let data = try? JSONEncoder().encode(m) else {
                clearManifest()
                return
            }
            UserDefaults.standard.set(data, forKey: manifestKey)
            UserDefaults.standard.set(m.version, forKey: versionKey)
        }
    }

    var installedVersion: Int {
        UserDefaults.standard.integer(forKey: versionKey)
    }

    func clearManifest() {
        UserDefaults.standard.removeObject(forKey: manifestKey)
        UserDefaults.standard.removeObject(forKey: versionKey)
    }

    // MARK: Disponibilité bundle

    /// Vrai si `DemoVelvetShowState.json` est présent dans le bundle
    /// (sous DemoContent/ ou at la racine selon la synchro Xcode).
    var bundleDemoAvailable: Bool {
        bundleDemoStateURL != nil
    }

    /// URL du JSON de démo dans le bundle, ou nil si absent.
    var bundleDemoStateURL: URL? {
        Bundle.main.url(forResource: "DemoVelvetShowState", withExtension: "json", subdirectory: "DemoContent")
        ?? Bundle.main.url(forResource: "DemoVelvetShowState", withExtension: "json")
    }

    /// Vrai si une démo est actuellement installée dans l'état utilisateur.
    var isDemoInstalled: Bool { manifest != nil }
}
