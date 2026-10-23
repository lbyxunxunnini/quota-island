import Foundation
import Security

struct CredentialVault {
    let read: (ProviderConfig) throws -> KeychainStore.Credentials
    let write: (KeychainStore.Credentials, UUID) throws -> Void
    let remove: (UUID) throws -> Void
    static var keychain: CredentialVault {
        CredentialVault(read: KeychainStore.credentials(for:), write: KeychainStore.save(_:for:),
                        remove: KeychainStore.remove(_:))
    }
}

enum KeychainStore {
    private static let instanceService = "com.aiquotaisland.instances"

    struct Credentials: Codable, Equatable, Sendable {
        var apiKey: String = ""
        var cookie: String = ""
        var isEmpty: Bool { apiKey.isEmpty && cookie.isEmpty }
    }

    static func credentials(for config: ProviderConfig) throws -> Credentials {
        if let raw = try read(service: instanceService, account: config.id.uuidString),
           let data = raw.data(using: .utf8) {
            guard let result = try? JSONDecoder().decode(Credentials.self, from: data) else {
                throw QuotaFailure.unavailable("本 App 凭据格式无法识别")
            }
            return result
        }
        if config.isLegacy {
            if config.provider == .spark { return Credentials(cookie: try readSparkCookie() ?? "") }
            if config.provider == .opencodeGo { return Credentials(apiKey: try readOpenCodeGoKey() ?? "") }
        }
        return Credentials()
    }

    static func save(_ credentials: Credentials, for id: UUID) throws {
        let data = try JSONEncoder().encode(credentials)
        try save(String(decoding: data, as: UTF8.self), service: instanceService, account: id.uuidString)
    }

    static func remove(_ id: UUID) throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: instanceService,
            kSecAttrAccount as String: id.uuidString
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw QuotaFailure.unavailable("无法移除本 App 凭据（Keychain: \(status)）")
        }
    }

    private static let sparkService = "com.aiquotaisland.spark"
    private static let sparkAccount = "free-quota-cookie"
    private static let goService = "com.aiquotaisland.opencode-go"
    private static let goAccount = "workspace-key"

    static func readSparkCookie() throws -> String? {
        try read(service: sparkService, account: sparkAccount)
    }

    static func saveSparkCookie(_ value: String) throws {
        try save(value, service: sparkService, account: sparkAccount)
    }

    static func readOpenCodeGoKey() throws -> String? {
        try read(service: goService, account: goAccount)
    }

    static func saveOpenCodeGoKey(_ value: String) throws {
        try save(value, service: goService, account: goAccount)
    }

    private static func read(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw QuotaFailure.unavailable("无法读取本 App 凭据（Keychain: \(status)）")
        }
        return value
    }

    private static func save(_ value: String, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else {
            throw QuotaFailure.unavailable("无法保存本 App 凭据（Keychain: \(status)）")
        }
        var create = query
        create[kSecValueData as String] = data
        let addStatus = SecItemAdd(create as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw QuotaFailure.unavailable("无法保存本 App 凭据（Keychain: \(addStatus)）")
        }
    }
}
