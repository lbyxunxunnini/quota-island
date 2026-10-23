import Foundation
import Security
import CryptoKit

/// Reads the ChatGPT account used by the local Codex login. Credentials never leave memory
/// except as HTTPS authorization headers sent to ChatGPT.
struct CodexAdapter: QuotaAdapter {
    let provider: ProviderID = .codex

    private let session: URLSession
    private let usageURL: URL
    private let resetCreditsURL: URL
    private let loadCredentials: @Sendable () throws -> Credentials

    init() {
        self.session = .shared
        self.usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
        self.resetCreditsURL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!
        self.loadCredentials = { try Self.readCredentials() }
    }

    func fetch() async throws -> QuotaSnapshot {
        let credentials = try loadCredentials()
        let usageData = try await request(usageURL, credentials: credentials)
        let fetchedAt = Date()
        let base = try Self.parseUsage(usageData, fetchedAt: fetchedAt)
        if base.resetCredits?.availableCount == 0 { return base }

        // The usage response owns the available count. Details only add the nearest expiry;
        // a failing detail request must not hide an otherwise valid usage snapshot.
        guard let detailsData = try? await request(resetCreditsURL, credentials: credentials, timeout: 8) else {
            return base
        }
        return try Self.parseUsage(usageData, fetchedAt: fetchedAt, resetDetails: detailsData)
    }

    private func request(
        _ url: URL,
        credentials: Credentials,
        timeout: TimeInterval = 15
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
        if let accountID = credentials.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw QuotaFailure.temporary("Codex 查询没有收到有效响应")
            }
            switch response.statusCode {
            case 200...299:
                return data
            case 401, 403:
                throw QuotaFailure.authentication("Codex 登录已失效，请重新登录 Codex")
            case 408, 429, 500...599:
                throw QuotaFailure.temporary("Codex 服务暂时不可用（HTTP \(response.statusCode)）")
            default:
                throw QuotaFailure.unavailable("Codex 额度查询失败（HTTP \(response.statusCode)）")
            }
        } catch let failure as QuotaFailure {
            throw failure
        } catch {
            // Do not include a URLSession error description: it can contain a request URL.
            throw QuotaFailure.temporary("Codex 网络连接失败")
        }
    }

    static func parseUsage(
        _ data: Data,
        fetchedAt: Date,
        resetDetails: Data? = nil
    ) throws -> QuotaSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rateLimit = root["rate_limit"] as? [String: Any] else {
            throw QuotaFailure.unavailable("Codex 返回的额度格式无法识别")
        }

        let sources: [(String, String)] = [
            ("primary_window", "主要额度"),
            ("secondary_window", "次要额度")
        ]
        let windows = sources.compactMap { key, fallback -> QuotaWindow? in
            guard let raw = rateLimit[key] as? [String: Any],
                  let used = number(raw["used_percent"]), used.isFinite,
                  (0...100).contains(used) else { return nil }
            let seconds = number(raw["limit_window_seconds"]).flatMap { Int(exactly: $0) }
            let resetDate = number(raw["reset_at"]).flatMap { seconds -> Date? in
                guard seconds > 0, seconds.isFinite, used != 0 else { return nil }
                return Date(timeIntervalSince1970: seconds)
            }
            return QuotaWindow(
                id: key,
                title: windowTitle(seconds: seconds, fallback: fallback),
                durationSeconds: seconds,
                remainingFraction: 1 - used / 100,
                resetsAt: resetDate
            )
        }
        guard !windows.isEmpty else {
            throw QuotaFailure.unavailable("Codex 未返回可用的额度窗口")
        }

        let summary = root["rate_limit_reset_credits"] as? [String: Any]
        let summaryCount = availableCount(summary?["available_count"])
        let detail = resetDetails.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let detailCount = availableCount(detail?["available_count"])
        let availableEntries = (detail?["credits"] as? [[String: Any]] ?? []).filter { entry in
            guard entry["status"] as? String == "available" else { return false }
            guard let raw = entry["expires_at"] as? String,
                  let expiry = QuotaDateParser.parse(raw) else { return true }
            return expiry > fetchedAt
        }
        let availableExpiries = availableEntries.compactMap { entry -> Date? in
            guard let raw = entry["expires_at"] as? String else { return nil }
            return QuotaDateParser.parse(raw)
        }
        let fallbackCount = availableEntries.count
        let count = summaryCount ?? detailCount ?? (detail == nil ? nil : fallbackCount)
        let resetCredits = count.map { count in
            ResetCredits(availableCount: count, expiresAt: availableExpiries.min())
        }

        return QuotaSnapshot(
            provider: .codex,
            windows: windows,
            totalQuota: nil,
            resetCredits: resetCredits,
            fetchedAt: fetchedAt
        )
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        return value.doubleValue
    }

    private static func availableCount(_ value: Any?) -> Int? {
        guard let value = number(value), value >= 0 else { return nil }
        return Int(exactly: value)
    }

    private static func windowTitle(seconds: Int?, fallback: String) -> String {
        guard let seconds, seconds > 0 else { return fallback }
        switch seconds {
        case 18_000: return "5 小时"
        case 604_800: return "本周"
        case 2_592_000: return "本月"
        default:
            if seconds % 86_400 == 0 { return "\(seconds / 86_400) 天" }
            if seconds % 3_600 == 0 { return "\(seconds / 3_600) 小时" }
            return "\(seconds / 60) 分钟"
        }
    }

    private struct Credentials: Sendable {
        let accessToken: String
        let accountID: String?
    }

    private static func readCredentials() throws -> Credentials {
        let home = codexHome()
        let canonicalPath = home.resolvingSymlinksInPath().standardizedFileURL.path
        let hash = SHA256.hash(data: Data(canonicalPath.utf8))
        let prefix = hash.prefix(8).map { String(format: "%02x", $0) }.joined()
        let account = "cli|\(prefix)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Codex Auth",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess {
            guard let data = item as? Data else {
                throw QuotaFailure.unavailable("无法读取 Codex Keychain 登录")
            }
            return try parseCredentials(data)
        }
        guard status == errSecItemNotFound else {
            // An inaccessible Keychain entry may be a different login than auth.json.
            throw QuotaFailure.unavailable("无法访问 Codex Keychain 登录，请检查系统权限")
        }
        let file = home.appendingPathComponent("auth.json")
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw QuotaFailure.authentication("未找到 Codex 登录，请先登录 Codex")
        }
        do {
            return try parseCredentials(Data(contentsOf: file))
        } catch let failure as QuotaFailure {
            throw failure
        } catch {
            throw QuotaFailure.unavailable("无法读取 Codex 登录文件")
        }
    }

    private static func codexHome() -> URL {
        if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    private static func parseCredentials(_ data: Data) throws -> Credentials {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["auth_mode"] as? String == "chatgpt",
              let tokens = root["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              !accessToken.isEmpty else {
            throw QuotaFailure.authentication("Codex 未使用可查询额度的 ChatGPT 登录")
        }
        return Credentials(accessToken: accessToken, accountID: tokens["account_id"] as? String)
    }
}
