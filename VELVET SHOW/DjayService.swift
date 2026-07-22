//
//  DjayService.swift
//  VELVET SHOW
//
//  Handoff DJ / entracte : lance une app audio externe et tente d'envoyer Play.
//  Cibles intégrées : djay Pro, Spotify, Apple Music, Traktor. Une cible custom
//  peut être configurée par bundle ID ou nom d'app.
//

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

#if os(macOS)

@MainActor
enum DJHandoffService {

    struct Configuration {
        var target: AppState.DJHandoffTarget
        var customBundleID: String
        var customAppName: String
        var coldLaunchDelayMillis: Int
        var usesKeyboardFallback: Bool
    }

    private struct TargetDefinition {
        let displayName: String
        let bundleIDs: [String]
        let fallbackNameContains: [String]
        let appleScriptCommand: String?
    }

    enum HandoffError: LocalizedError {
        case notInstalled
        case customTargetMissing
        case launchFailed(String)
        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "The selected DJ handoff app is not installed."
            case .customTargetMissing:
                return "Configure a custom app bundle ID or app name in Settings."
            case .launchFailed(let msg):
                return "DJ handoff launch failed: \(msg)"
            }
        }
    }

    private static func definition(for target: AppState.DJHandoffTarget) -> TargetDefinition {
        switch target {
        case .djay:
            return TargetDefinition(
                displayName: "djay Pro",
                bundleIDs: [
                    "com.algoriddim.djaypro-mac",
                    "com.algoriddim.djay-pro-mac",
                    "com.algoriddim.djay-pro-ai-mac",
                    "com.algoriddim.djay-pro",
                    "com.algoriddim.djay",
                ],
                fallbackNameContains: ["djay"],
                appleScriptCommand: "play"
            )
        case .spotify:
            return TargetDefinition(
                displayName: "Spotify",
                bundleIDs: ["com.spotify.client"],
                fallbackNameContains: ["spotify"],
                appleScriptCommand: "play"
            )
        case .appleMusic:
            return TargetDefinition(
                displayName: "Apple Music",
                bundleIDs: ["com.apple.Music"],
                fallbackNameContains: ["music"],
                appleScriptCommand: "play"
            )
        case .traktor:
            return TargetDefinition(
                displayName: "Traktor",
                bundleIDs: [
                    "com.native-instruments.Traktor Pro 4",
                    "com.native-instruments.Traktor Pro 3",
                    "com.native-instruments.Traktor Pro",
                    "com.native-instruments.Traktor",
                ],
                fallbackNameContains: ["traktor"],
                appleScriptCommand: nil
            )
        case .custom:
            return TargetDefinition(
                displayName: "Custom App",
                bundleIDs: [],
                fallbackNameContains: [],
                appleScriptCommand: nil
            )
        }
    }

    static func installedAppURL(for config: Configuration) throws -> URL? {
        if config.target == .custom {
            let bundleID = config.customBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = config.customAppName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty || !name.isEmpty else { throw HandoffError.customTargetMissing }
            if !bundleID.isEmpty,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return url
            }
            if !name.isEmpty, let url = findApp(namedOrContaining: name) {
                return url
            }
            return nil
        }

        let definition = definition(for: config.target)
        for bundleID in definition.bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                print("[DJ] Found \(definition.displayName) via bundle ID \(bundleID) → \(url.path)")
                return url
            }
        }
        for needle in definition.fallbackNameContains {
            if let url = findApp(namedOrContaining: needle) {
                print("[DJ] Found \(definition.displayName) via filesystem scan → \(url.path)")
                return url
            }
        }
        return nil
    }

    private static func findApp(namedOrContaining rawNeedle: String) -> URL? {
        let needle = rawNeedle.lowercased()
        let searchRoots: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first,
        ].compactMap { $0 }
        let fm = FileManager.default
        for root in searchRoots {
            guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for entry in entries {
                let name = entry.lastPathComponent.lowercased()
                if name.hasSuffix(".app") && name.contains(needle) {
                    return entry
                }
            }
        }
        return nil
    }

    static func openAndPlay(config: Configuration) async throws {
        guard let appURL = try installedAppURL(for: config) else {
            throw HandoffError.notInstalled
        }

        let openConfig = NSWorkspace.OpenConfiguration()
        openConfig.activates = true
        openConfig.addsToRecentItems = false

        let runningApp: NSRunningApplication
        do {
            runningApp = try await NSWorkspace.shared.openApplication(at: appURL, configuration: openConfig)
        } catch {
            throw HandoffError.launchFailed(error.localizedDescription)
        }

        let bundleID = Bundle(url: appURL)?.bundleIdentifier
        print("[DJ] launched bundle id=\(bundleID ?? "unknown")")

        // Forcer l'app au premier plan (activates=true ne suffit pas toujours
        // quand l'app était déjà ouverte mais cachée).
        runningApp.activate(options: [.activateAllWindows])

        let warm = runningApp.isFinishedLaunching
        let coldMs = max(0, min(2_000, config.coldLaunchDelayMillis))
        let sleepNs: UInt64 = warm ? 60_000_000 : UInt64(coldMs) * 1_000_000
        print("[DJ] warm=\(warm) → sleep \(sleepNs / 1_000_000) ms before Play")
        try? await Task.sleep(nanoseconds: sleepNs)

        if let bundleID {
            let definition = definition(for: config.target)
            if let command = definition.appleScriptCommand,
               tryAppleScriptCommand(bundleID: bundleID, command: command) {
                return
            }
        }

        guard config.usesKeyboardFallback else { return }

        if tryAppleScriptKeyCodeSpace() {
            return
        }

        postCGEventSpace()
    }

    /// Vérifie si Velvet Show a la permission Accessibilité.
    /// Note : pour les apps sandboxées, l'utilisateur doit ajouter Velvet
    /// manuellement (le `+` dans la liste Accessibilité ne fonctionne pas
    /// sans entitlement, mais drag-and-drop du .app marche).
    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    /// Envoie une frappe Espace via CGEvent au niveau HID. djay (frontmost)
    /// la reçoit comme une vraie touche. Sans Accessibilité, échec silencieux.
    private static func postCGEventSpace() {
        let trusted = AXIsProcessTrusted()
        print("[DJ] CGEvent attempt — accessibility trusted=\(trusted)")
        let source = CGEventSource(stateID: .combinedSessionState)
        let spaceKey: CGKeyCode = 49
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: spaceKey, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: spaceKey, keyDown: false)
        else {
            print("[DJ] CGEvent creation failed")
            return
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        print("[DJ] CGEvent Space posted to HID tap")
    }

    @discardableResult
    private static func tryAppleScriptCommand(bundleID: String, command: String) -> Bool {
        let source = "tell application id \"\(bundleID)\" to \(command)"
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        if let error {
            print("[DJ] AppleScript \(command) failed for id \(bundleID): \(error)")
            return false
        }
        print("[DJ] AppleScript \(command) sent to id \(bundleID)")
        return true
    }

    /// Envoie une frappe Espace via System Events à l'app actuellement au
    /// premier plan (djay, puisqu'on vient de l'activer). Nécessite l'autorisation
    /// "Velvet Show contrôle System Events" — popup macOS au 1er usage.
    @discardableResult
    private static func tryAppleScriptKeyCodeSpace() -> Bool {
        let source = "tell application \"System Events\" to key code 49"
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        if let error {
            print("[DJ] AppleScript key code Space failed: \(error)")
            return false
        }
        print("[DJ] AppleScript key code Space sent")
        return true
    }
}

@MainActor
enum DjayService {
    static func openAndPlay() async throws {
        try await DJHandoffService.openAndPlay(config: .init(
            target: .djay,
            customBundleID: "",
            customAppName: "",
            coldLaunchDelayMillis: 600,
            usesKeyboardFallback: true
        ))
    }
}

#endif
