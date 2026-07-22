//
//  BetaTrial.swift
//  VELVET SHOW
//
//  Local 30-day trial — first launch date stored in Keychain (survives reinstall).
//  Migrates automatically from UserDefaults on first run after update.
//

import SwiftUI
import AppKit
import Security

// MARK: - BetaManager

@Observable
@MainActor
final class BetaManager {

    private static let trialDays       = 30
    private static let udKey           = "betaFirstLaunchDate"
    private static let keychainService = "app.velvetshow.trial"
    private static let keychainAccount = "first_launch_date"

    let firstLaunchDate: Date

    init() {
        firstLaunchDate = BetaManager.resolveFirstLaunchDate()

        #if DEBUG
        let expires = Calendar.current.date(
            byAdding: .day, value: BetaManager.trialDays, to: firstLaunchDate
        ) ?? firstLaunchDate
        let remaining = max(0, Calendar.current.dateComponents([.day], from: Date(), to: expires).day ?? 0)
        print("[BETA] first launch   = \(firstLaunchDate)")
        print("[BETA] expires        = \(expires)")
        print("[BETA] days remaining = \(remaining)")
        #endif
    }

    var isExpired: Bool {
        #if DEBUG
        return false
        #else
        guard let expiry = Calendar.current.date(
            byAdding: .day, value: BetaManager.trialDays, to: firstLaunchDate
        ) else { return true }
        return Date() >= expiry
        #endif
    }

    /// Date d'expiration calculée à partir de la première date d'ouverture.
    /// Stable tant que `firstLaunchDate` ne change pas (le Keychain est
    /// l'autorité, voir `resolveFirstLaunchDate`).
    var expiresAt: Date {
        Calendar.current.date(
            byAdding: .day, value: BetaManager.trialDays, to: firstLaunchDate
        ) ?? firstLaunchDate
    }

    /// Jours restants avant expiration (0 si déjà expiré). Borné à 0…trialDays.
    /// Utilisé par le badge toolbar et la section License des Settings.
    var daysRemaining: Int {
        let raw = Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0
        return min(BetaManager.trialDays, max(0, raw))
    }

    // MARK: - Private

    private static func resolveFirstLaunchDate() -> Date {
        // 1. Keychain — authoritative source
        if let date = keychainReadDate() { return date }

        // 2. Migrate from UserDefaults (users who installed before this version)
        if let legacy = UserDefaults.standard.object(forKey: udKey) as? Date {
            keychainWriteDate(legacy)
            return legacy
        }

        // 3. First ever launch
        let now = Date()
        keychainWriteDate(now)
        return now
    }

    private static func keychainWriteDate(_ date: Date) {
        let data = withUnsafeBytes(of: date.timeIntervalSinceReferenceDate) { Data($0) }
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String:   data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func keychainReadDate() -> Date? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              data.count == MemoryLayout<TimeInterval>.size else { return nil }
        let interval = data.withUnsafeBytes { $0.load(as: TimeInterval.self) }
        return Date(timeIntervalSinceReferenceDate: interval)
    }
}

// MARK: - BetaExpiredView

struct BetaExpiredView: View {
    var body: some View {
        // Plein écran post-expiration : copy historique conservée.
        LicenseView(mode: .expired, onDismiss: nil)
    }
}

// MARK: - TrialStatusBadge (toolbar)

/// Pastille toolbar discrète affichant le statut du trial. N'apparaît que si
/// la licence n'est pas activée ET le trial est encore actif. Cliquer ouvre
/// `LicenseView` en sheet (mode `.trial`) — l'utilisateur peut acheter ou
/// activer une clé sans quitter l'app.
///
/// Couleurs : neutre > 7 jours, orange entre 7 et 3 jours, rouge ≤ 3 jours.
/// Aucune ostentation — ce n'est pas une bannière publicitaire.
struct TrialStatusBadge: View {
    let betaManager: BetaManager
    let licenseManager: LicenseManager

    @State private var isShowingUnlockSheet = false

    /// Affiche le badge uniquement quand on est en trial actif et non licencié.
    private var isVisible: Bool {
        !licenseManager.isActivated && !betaManager.isExpired
    }

    private var days: Int { betaManager.daysRemaining }

    private var accent: Color {
        if days <= 3 { return .red }
        if days <= 7 { return .orange }
        return .secondary
    }

    private var label: String {
        let unit = days == 1 ? "day" : "days"
        return "Trial · \(days) \(unit) · Unlock"
    }

    var body: some View {
        if isVisible {
            Button {
                isShowingUnlockSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 9, weight: .semibold))
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .strokeBorder(accent.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Velvet Show Trial — \(days) day\(days == 1 ? "" : "s") remaining. Click to unlock now.")
            .sheet(isPresented: $isShowingUnlockSheet) {
                LicenseSheet(
                    licenseManager: licenseManager,
                    betaManager: betaManager,
                    onDismiss: { isShowingUnlockSheet = false }
                )
            }
        }
    }
}

// MARK: - LicenseSheet (wrapper)

/// Sheet hôte pour `LicenseView(mode: .trial)`. Fournit l'environnement
/// `LicenseManager` requis par `LicenseView`. Disparaît dès que la license
/// est activée — l'onChange referme automatiquement la sheet.
struct LicenseSheet: View {
    let licenseManager: LicenseManager
    let betaManager: BetaManager
    let onDismiss: () -> Void

    var body: some View {
        LicenseView(
            mode: .trial(daysRemaining: betaManager.daysRemaining),
            onDismiss: onDismiss
        )
        .environment(licenseManager)
        .onChange(of: licenseManager.isActivated) { _, isActivated in
            if isActivated { onDismiss() }
        }
    }
}
