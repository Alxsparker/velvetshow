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
        LicenseView()
    }
}
