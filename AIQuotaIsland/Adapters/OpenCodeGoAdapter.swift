import Foundation

/// Reads the Go workspace key saved by OpenCode, then queries its usage endpoint.
struct OpenCodeGoAdapter: QuotaAdapter {
    let provider: ProviderID = .opencodeGo

    private let session: URLSession
    private let authFileURL: URL

    init(session: URLSession = .shared, authFileURL: URL? = nil) {
        self.session = session
        self.authFileURL = authFileURL ?? Self.defaultAuthFileURL()
    }

    func fetch() async throws -> QuotaSnapshot {
        let key = try KeychainStore.readOpenCodeGoKey() ?? Self.readGoKey(at: authFileURL)
        return try await validate(key: key)
    }

    func validate(key: String) async throws -> QuotaSnapshot {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw QuotaFailure.authentication("请输入有效的 OpenCode Go Key")
        }
        var request = URLRequest(url: URL(string: "https://opencode.ai/zen/go/v1/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw QuotaFailure.temporary("OpenCode Go 暂时无法连接，请稍后重试")
        }

        guard let http = response as? HTTPURLResponse else {
            throw QuotaFailure.temporary("OpenCode Go 返回了无效响应")
        }
        switch http.statusCode {
        case 200..<300:
            return try Self.parseUsage(data, fetchedAt: Date())
        case 401:
            throw QuotaFailure.authentication("OpenCode Go API Key 已失效，请在 OpenCode 中重新登录")
        case 403:
            throw QuotaFailure.unavailable("当前 OpenCode 工作区没有 Go 订阅")
        case 429:
            throw QuotaFailure.temporary("OpenCode Go 查询过于频繁，请稍后重试")
        default:
            throw QuotaFailure.temporary("OpenCode Go 查询失败（HTTP \(http.statusCode)）")
        }
    }

    static func parseUsage(_ data: Data, fetchedAt: Date = Date()) throws -> QuotaSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = root["usage"] as? [String: Any] else {
            throw QuotaFailure.unavailable("OpenCode Go 额度响应格式已变化")
        }

        let definitions = [
            (key: "rolling", title: "5 小时", duration: 18_000),
            (key: "weekly", title: "本周", duration: 604_800),
            (key: "monthly", title: "本月", duration: 2_592_000)
        ]
        let windows = definitions.compactMap { definition -> QuotaWindow? in
            guard let window = usage[definition.key] as? [String: Any],
                  let usedPercent = numericPercent(window["percent"]) else { return nil }
            // The upstream endpoint uses a placeholder reset timestamp for an unused window.
            let reset = usedPercent == 0 ? nil : QuotaDateParser.parse(window["resetsAt"] as? String)
            return QuotaWindow(
                id: definition.key,
                title: definition.title,
                durationSeconds: definition.duration,
                remainingFraction: 1 - usedPercent / 100,
                resetsAt: reset
            )
        }
        guard !windows.isEmpty else {
            throw QuotaFailure.unavailable("OpenCode Go 未返回可识别的额度周期")
        }
        return QuotaSnapshot(
            provider: .opencodeGo,
            windows: windows,
            totalQuota: nil,
            resetCredits: nil,
            fetchedAt: fetchedAt
        )
    }

    private static func numericPercent(_ value: Any?) -> Double? {
        let number: Double
        switch value {
        case let value as NSNumber where CFGetTypeID(value) != CFBooleanGetTypeID():
            number = value.doubleValue
        case let value as String:
            number = Double(value) ?? .nan
        default:
            return nil
        }
        guard number.isFinite, (0...100).contains(number) else { return nil }
        return number
    }

    private static func defaultAuthFileURL() -> URL {
        let dataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
        let base: URL
        if let dataHome, dataHome.hasPrefix("/") {
            base = URL(fileURLWithPath: dataHome, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/share", isDirectory: true)
        }
        return base.appendingPathComponent("opencode/auth.json")
    }

    private static func readGoKey(at url: URL) throws -> String {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["opencode-go"] as? [String: Any],
              account["type"] as? String == "api",
              let key = account["key"] as? String,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QuotaFailure.unavailable("未找到 OpenCode Go 登录信息，请先在 OpenCode 中连接 Go")
        }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
