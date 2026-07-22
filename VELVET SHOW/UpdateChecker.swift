//
//  UpdateChecker.swift
//  VELVET SHOW
//
//  Lightweight GitHub Releases update checker. Polls
//  `https://api.github.com/repos/Alxsparker/velvetshow/releases/latest` on
//  app launch, compares the tag against the bundled CFBundleShortVersionString,
//  and exposes a small toolbar badge.
//
//  Design rules:
//    • Never block app launch. Network failures are silent.
//    • Cache the result for 6 hours to avoid hammering GitHub's rate limit.
//    • Coalesce concurrent checks.
//    • Keep this fully separate from BetaManager / LicenseManager — the only
//      coupling is that both expose a small `@Observable` and a toolbar badge.
//    • No auto-install. Download is a browser handoff to the release URL.
//

import SwiftUI
import AppKit

// MARK: - UpdateChecker

@Observable
@MainActor
final class UpdateChecker {

    // MARK: - Configuration

    static let owner = "Alxsparker"
    static let repo  = "velvetshow"

    /// Minimum interval between two HTTP requests to GitHub. Keeps anonymous
    /// requests well below the 60/hour rate limit even on long sessions.
    private static let cacheInterval: TimeInterval = 6 * 60 * 60   // 6 hours

    // UserDefaults keys
    private static let kAvailableVersion = "updateAvailableVersion"
    private static let kReleaseURL       = "updateReleaseURL"
    private static let kLastCheckedAt    = "updateLastCheckedAt"
    private static let kDismissedVersion = "updateDismissedVersion"

    // MARK: - Observable state

    /// Latest release tag found on GitHub (sans leading « v »). nil = jamais
    /// vu (premier lancement sans réseau).
    private(set) var availableVersion: String? = nil

    /// URL to open when the user clicks Download — typically the release page
    /// on GitHub. Falls back to the html_url even if no asset is attached.
    private(set) var releaseURL: URL? = nil

    /// Timestamp of the last successful network check. Drives the 6-hour cache.
    private(set) var lastCheckedAt: Date? = nil

    /// Version explicitly dismissed by the user via the "Later" button. Stored
    /// in UserDefaults — re-appears automatically when a newer tag is released.
    @ObservationIgnored private var dismissedVersion: String?

    @ObservationIgnored private var inFlightTask: Task<Void, Never>? = nil

    // MARK: - Init

    init() {
        let d = UserDefaults.standard
        availableVersion = d.string(forKey: Self.kAvailableVersion)
        if let s = d.string(forKey: Self.kReleaseURL) { releaseURL = URL(string: s) }
        lastCheckedAt    = d.object(forKey: Self.kLastCheckedAt) as? Date
        dismissedVersion = d.string(forKey: Self.kDismissedVersion)
    }

    // MARK: - Public API

    /// Current app version, read from the bundle. "0.0" if unavailable
    /// (shouldn't happen — included as a defensive default).
    var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0"
    }

    /// True if a newer release was found and the user hasn't dismissed it.
    /// Drives the toolbar badge visibility.
    var hasUpdate: Bool {
        guard let v = availableVersion else { return false }
        guard !Self.parseSemver(v).isEmpty else { return false }
        if let dismissed = dismissedVersion, dismissed == v { return false }
        return Self.compareSemver(v, currentVersion) == .orderedDescending
    }

    /// Run a network check if the cache is stale (> 6h) or if `force` is true.
    /// Coalesces concurrent calls. Silent on failure — never throws.
    func checkIfNeeded(force: Bool = false) async {
        if !force, let last = lastCheckedAt,
           Date().timeIntervalSince(last) < Self.cacheInterval {
            return
        }
        if let existing = inFlightTask {
            return await existing.value
        }
        let task = Task<Void, Never> { await self.performCheck() }
        inFlightTask = task
        await task.value
        inFlightTask = nil
    }

    /// Snooze the current available version until a strictly newer one ships.
    func dismissCurrent() {
        guard let v = availableVersion else { return }
        dismissedVersion = v
        UserDefaults.standard.set(v, forKey: Self.kDismissedVersion)
    }

    /// Open the release page in the default browser. No-op if no URL cached.
    func openRelease() {
        guard let u = releaseURL else { return }
        NSWorkspace.shared.open(u)
    }

    // MARK: - Network

    private func performCheck() async {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest") else {
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("VelvetShow/\(currentVersion) macOS", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            // /releases/latest never returns drafts or pre-releases per the
            // GitHub API contract, but defensively skip just in case.
            if release.draft || release.prerelease { return }

            let version = Self.stripLeadingV(release.tag_name.trimmingCharacters(in: .whitespacesAndNewlines))
            let now = Date()

            availableVersion = version
            releaseURL       = URL(string: release.html_url)
            lastCheckedAt    = now

            let d = UserDefaults.standard
            d.set(version,       forKey: Self.kAvailableVersion)
            d.set(release.html_url, forKey: Self.kReleaseURL)
            d.set(now,           forKey: Self.kLastCheckedAt)

            #if DEBUG
            print("[UPDATE] latest=\(version) current=\(currentVersion) hasUpdate=\(hasUpdate)")
            #endif
        } catch {
            #if DEBUG
            print("[UPDATE] check failed (silent): \(error.localizedDescription)")
            #endif
        }
    }

    private struct GitHubRelease: Decodable {
        let tag_name:  String
        let html_url:  String
        let draft:     Bool
        let prerelease:Bool
    }

    // MARK: - Version comparison (semver-ish)

    private static func stripLeadingV(_ s: String) -> String {
        if s.hasPrefix("v") || s.hasPrefix("V") { return String(s.dropFirst()) }
        return s
    }

    /// Parses "1.2.3" → [1, 2, 3]. Strips leading « v » and trailing build/
    /// pre-release suffix. Returns [] if no numeric component is found.
    static func parseSemver(_ s: String) -> [Int] {
        var cleaned = stripLeadingV(s.trimmingCharacters(in: .whitespacesAndNewlines))
        if let dash = cleaned.firstIndex(of: "-") { cleaned = String(cleaned[..<dash]) }
        if let plus = cleaned.firstIndex(of: "+") { cleaned = String(cleaned[..<plus]) }
        return cleaned.split(separator: ".").compactMap { Int($0) }
    }

    /// Compare two semver-ish strings component by component. Missing
    /// components are treated as 0 ("0.12" vs "0.12.0" → orderedSame).
    static func compareSemver(_ a: String, _ b: String) -> ComparisonResult {
        let pa = parseSemver(a)
        let pb = parseSemver(b)
        let len = max(pa.count, pb.count)
        for i in 0..<len {
            let ai = i < pa.count ? pa[i] : 0
            let bi = i < pb.count ? pb[i] : 0
            if ai < bi { return .orderedAscending }
            if ai > bi { return .orderedDescending }
        }
        return .orderedSame
    }
}

// MARK: - Toolbar badge

/// Compact pill shown in the main toolbar when a newer release is available
/// AND the user hasn't dismissed it. Style mirrors `TrialStatusBadge` — small,
/// subtle, never intrusive during a live show.
struct UpdateAvailableBadge: View {
    let updateChecker: UpdateChecker

    @State private var showSheet = false

    var body: some View {
        if updateChecker.hasUpdate, let version = updateChecker.availableVersion {
            Button {
                showSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Update · \(version)")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().strokeBorder(Color.blue.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Velvet Show \(version) is available")
            .sheet(isPresented: $showSheet) {
                UpdateAvailableSheet(
                    updateChecker: updateChecker,
                    onDismiss: { showSheet = false }
                )
            }
        }
    }
}

// MARK: - Update sheet

struct UpdateAvailableSheet: View {
    let updateChecker: UpdateChecker
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Velvet Show \(updateChecker.availableVersion ?? "?") is available")
                        .font(.headline)
                    Text("You're currently on \(updateChecker.currentVersion).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Download the new release from GitHub. You can keep using \(updateChecker.currentVersion) until you've installed it — no forced update, no auto-install.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Later") {
                    updateChecker.dismissCurrent()
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    updateChecker.openRelease()
                    onDismiss()
                } label: {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 400)
    }
}
