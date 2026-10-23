import Foundation

struct SparkAdapter: QuotaAdapter {
    let provider: ProviderID = .spark

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch() async throws -> QuotaSnapshot {
        guard let cookie = try KeychainStore.readSparkCookie(), !cookie.isEmpty else {
            throw QuotaFailure.authentication("请先设置讯飞 Cookie")
        }
        return try await requestQuota(cookie: cookie)
    }

    /// Checks a replacement Cookie without changing the saved credential.
    func validate(cookie: String) async throws -> QuotaSnapshot {
        try await requestQuota(cookie: cookie)
    }

    private func requestQuota(cookie: String) async throws -> QuotaSnapshot {
        let cookie = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cookie.isEmpty, !cookie.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw QuotaFailure.authentication("请输入有效的讯飞 Cookie")
        }

        var request = URLRequest(url: Self.quotaURL)
        request.httpMethod = "GET"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(Self.referer, forHTTPHeaderField: "Referer")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw QuotaFailure.temporary("讯飞额度查询暂时失败，请稍后重试")
        }

        guard let http = response as? HTTPURLResponse else {
            throw QuotaFailure.temporary("讯飞额度查询未返回 HTTP 响应")
        }
        if http.statusCode == 401 || http.statusCode == 403 || Self.isLoginRedirect(http.url) {
            throw QuotaFailure.authentication("讯飞 Cookie 已失效，请点击更换")
        }
        if http.statusCode == 429 || (500...599).contains(http.statusCode) {
            throw QuotaFailure.temporary("讯飞服务暂时不可用，请稍后重试")
        }
        guard (200...299).contains(http.statusCode) else {
            throw QuotaFailure.unavailable("讯飞额度查询失败（HTTP \(http.statusCode)）")
        }

        if http.mimeType?.lowercased().contains("html") == true {
            throw QuotaFailure.authentication("讯飞 Cookie 已失效，请点击更换")
        }

        return try Self.parseQuota(data)
    }

    static func parseQuota(_ data: Data, now: Date = Date()) throws -> QuotaSnapshot {
        let payload: QuotaResponse
        do {
            payload = try JSONDecoder().decode(QuotaResponse.self, from: data)
        } catch {
            throw QuotaFailure.unavailable("讯飞额度返回格式异常")
        }

        guard let code = payload.code else {
            throw QuotaFailure.unavailable("讯飞额度返回格式异常")
        }
        guard code == 0, payload.failed != true, payload.succeed != false else {
            if Self.isExpiredMessage(payload.message) {
                throw QuotaFailure.expired("讯飞额度已到期")
            }
            if Self.isTemporaryMessage(payload.message) {
                throw QuotaFailure.temporary("讯飞服务暂时不可用，请稍后重试")
            }
            throw QuotaFailure.authentication("讯飞 Cookie 已失效，请点击更换")
        }
        guard let quota = payload.data?.claim?.freeQuota else {
            throw QuotaFailure.unavailable("讯飞未返回免费额度")
        }

        if quota.quotaStatus == "EXPIRED" {
            throw QuotaFailure.expired("讯飞额度已到期")
        }
        guard let expiryText = quota.expiresAt,
              let expiresAt = QuotaDateParser.parse(expiryText) else {
            throw QuotaFailure.unavailable("讯飞额度到期时间格式异常")
        }
        if expiresAt <= now {
            throw QuotaFailure.expired("讯飞额度已到期")
        }
        guard quota.quotaStatus == "ACTIVE", quota.usageAvailable == true else {
            throw QuotaFailure.unavailable("讯飞免费额度不可用")
        }
        guard let total = quota.totalTokens,
              let used = quota.usedTokens,
              let remaining = quota.remainingTokens,
              total.isFinite, used.isFinite, remaining.isFinite,
              total > 0, used >= 0, remaining >= 0,
              remaining <= total else {
            throw QuotaFailure.unavailable("讯飞额度字段格式异常")
        }

        return QuotaSnapshot(
            provider: .spark,
            windows: [],
            totalQuota: TotalQuota(
                remaining: remaining,
                total: total,
                unit: "tokens",
                expiresAt: expiresAt
            ),
            resetCredits: nil,
            fetchedAt: now
        )
    }

    private static let quotaURL = URL(string: "https://maas.xfyun.cn/api/v1/gpt-finetune/api-services/free-quota?channel=spark-x2.6")!
    private static let referer = "https://maas.xfyun.cn/modelService?apiCallModel=spark-x2.6&apiCallName=Spark-X2.6"

    private static func isLoginRedirect(_ url: URL?) -> Bool {
        guard let url else { return false }
        let text = url.absoluteString.lowercased()
        return text.contains("/login") || text.contains("/sso/") || text.contains("passport")
    }

    private static func isTemporaryMessage(_ message: String?) -> Bool {
        guard let message = message?.lowercased() else { return false }
        return ["rate limit", "too many", "busy", "频繁", "限流", "繁忙", "稍后", "系统异常", "服务异常"].contains {
            message.contains($0)
        }
    }

    private static func isExpiredMessage(_ message: String?) -> Bool {
        guard let message = message?.lowercased() else { return false }
        return ["quota expired", "额度到期", "额度已过期", "免费额度过期"].contains {
            message.contains($0)
        }
    }
}

private struct QuotaResponse: Decodable {
    let code: Int?
    let failed: Bool?
    let succeed: Bool?
    let message: String?
    let data: QuotaData?
}

private struct QuotaData: Decodable {
    let claim: QuotaClaim?
}

private struct QuotaClaim: Decodable {
    let freeQuota: SparkFreeQuota?
}

private struct SparkFreeQuota: Decodable {
    let expiresAt: String?
    let quotaStatus: String?
    let remainingTokens: Double?
    let totalTokens: Double?
    let usageAvailable: Bool?
    let usedTokens: Double?
}
