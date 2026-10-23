import Foundation

private final class QuotaRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        let original = task.originalRequest?.url
        guard original?.host == request.url?.host, original?.scheme == request.url?.scheme,
              original?.port == request.url?.port else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

enum QuotaHTTPClient {
    private static let redirectGuard = QuotaRedirectGuard()
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        return URLSession(configuration: config, delegate: redirectGuard, delegateQueue: nil)
    }()

    static func validateCredential(_ key: String, label: String) throws {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !key.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw QuotaFailure.authentication("请输入有效的 \(label)")
        }
    }

    static func get(_ url: String, key: String, label: String) async throws -> Data {
        try validateCredential(key, label: label)
        guard let url = URL(string: url) else { throw QuotaFailure.unavailable("查询地址无效") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request, label: label)
    }

    static func send(_ request: URLRequest, label: String) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw QuotaFailure.temporary("\(label)未返回有效响应")
            }
            switch http.statusCode {
            case 200..<300: break
            case 401, 403: throw QuotaFailure.authentication("\(label)凭据无效或无查询权限，请更换")
            case 408, 429, 500...599: throw QuotaFailure.temporary("\(label)暂时不可用（HTTP \(http.statusCode)）")
            default: throw QuotaFailure.unavailable("\(label)查询失败（HTTP \(http.statusCode)）")
            }
            guard data.count <= 4_194_304 else { throw QuotaFailure.unavailable("查询响应过大") }
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch let failure as QuotaFailure { throw failure }
        catch { throw QuotaFailure.temporary("\(label)网络连接失败") }
    }
}

enum QuotaJSON {
    static func object(_ data: Data) throws -> [String: Any] {
        guard let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaFailure.unavailable("额度响应格式无法识别")
        }
        return result
    }
    static func number(_ value: Any?) -> Double? {
        let result: Double?
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { result = number.doubleValue }
        else if let text = value as? String { result = Double(text) }
        else { result = nil }
        return result.flatMap { $0.isFinite ? $0 : nil }
    }
    static func date(_ value: Any?) -> Date? {
        if let timestamp = number(value), timestamp > 0 {
            return Date(timeIntervalSince1970: timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp)
        }
        return (value as? String).flatMap(QuotaDateParser.parse)
    }
    static func title(_ seconds: Int) -> String {
        switch seconds {
        case 18_000: "5 小时"
        case 604_800: "本周"
        case 2_592_000: "本月"
        default: seconds >= 86_400 ? "\(seconds / 86_400) 天" : "\(seconds / 3600) 小时"
        }
    }
    static func snapshot(_ provider: ProviderID, windows: [QuotaWindow], now: Date) throws -> QuotaSnapshot {
        guard !windows.isEmpty else { throw QuotaFailure.unavailable("未返回可识别的套餐额度") }
        return QuotaSnapshot(provider: provider, windows: windows, totalQuota: nil, resetCredits: nil, fetchedAt: now)
    }
}
