import Foundation
import Security

enum KeychainStore {
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
