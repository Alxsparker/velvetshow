//
//  LicenseManager.swift
//  VELVET SHOW
//
//  LemonSqueezy license validation.
//  Stores the activated license key + instance ID in the macOS Keychain.
//

import SwiftUI
import Security

// MARK: - LicenseManager

@Observable
@MainActor
final class LicenseManager {

    // MARK: - State

    enum LicenseState: Equatable {
        case activated(key: String)
        case notActivated
        case validating
        case error(String)
    }

    var state: LicenseState = .notActivated
    var inputKey: String = ""

    // MARK: - Constants

    // Replace with your actual LemonSqueezy product ID after setup
    private static let lsProductID = "1146874"
    private static let keychainService = "app.velvetshow.license"
    private static let keychainKeyAccount = "license_key"
    private static let keychainInstanceAccount = "instance_id"

    // MARK: - Init

    init() {
        if let key = keychainRead(account: Self.keychainKeyAccount) {
            state = .activated(key: key)
        }
    }

    // MARK: - Public

    var isActivated: Bool {
        if case .activated = state { return true }
        return false
    }

    func activate() async {
        let key = inputKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        state = .validating

        do {
            let instanceID = try await validateWithLemonSqueezy(key: key)
            keychainWrite(value: key, account: Self.keychainKeyAccount)
            keychainWrite(value: instanceID, account: Self.keychainInstanceAccount)
            state = .activated(key: key)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func deactivate() {
        keychainDelete(account: Self.keychainKeyAccount)
        keychainDelete(account: Self.keychainInstanceAccount)
        state = .notActivated
        inputKey = ""
    }

    // MARK: - LemonSqueezy API

    private func validateWithLemonSqueezy(key: String) async throws -> String {
        guard let url = URL(string: "https://api.lemonsqueezy.com/v1/licenses/validate") else {
            throw LicenseError.invalidURL
        }

        // Unique machine identifier (anonymized)
        let machineID = getMachineID()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "license_key": key,
            "instance_name": machineID
        ])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LicenseError.networkError
        }

        let json = try JSONDecoder().decode(LemonSqueezyResponse.self, from: data)

        guard http.statusCode == 200, json.valid else {
            throw LicenseError.invalidKey(json.error ?? "Invalid license key.")
        }

        return json.instance?.id ?? machineID
    }

    // MARK: - Machine ID

    private func getMachineID() -> String {
        // Use hardware UUID as anonymous machine identifier
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        let uuid = IORegistryEntryCreateCFProperty(service,
            "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
        return uuid ?? UUID().uuidString
    }

    // MARK: - Keychain

    private func keychainWrite(value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String:   data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func keychainRead(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      Self.keychainService,
            kSecAttrAccount as String:      account,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainDelete(account: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - LemonSqueezy Response

private struct LemonSqueezyResponse: Decodable {
    let valid: Bool
    let error: String?
    let instance: LicenseInstance?

    struct LicenseInstance: Decodable {
        let id: String
    }
}

// MARK: - Errors

enum LicenseError: LocalizedError {
    case invalidURL
    case networkError
    case invalidKey(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:       return "Invalid API URL."
        case .networkError:     return "Network error. Check your connection."
        case .invalidKey(let m): return m
        }
    }
}
