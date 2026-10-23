import Foundation

struct DeepSeekAdapter: QuotaAdapter {
    let provider: ProviderID = .deepSeek
    let key: String
    func fetch() async throws -> QuotaSnapshot {
        try Self.parse(await QuotaHTTPClient.get("https://api.deepseek.com/user/balance", key: key, label: "DeepSeek"))
    }
    static func parse(_ data: Data, now: Date = Date()) throws -> QuotaSnapshot {
        let root = try QuotaJSON.object(data)
        guard let balances = root["balance_infos"] as? [[String: Any]],
              let info = balances.first(where: { ["CNY", "USD"].contains(($0["currency"] as? String ?? "").uppercased()) }),
              let amount = QuotaJSON.number(info["total_balance"]), let currency = info["currency"] as? String else {
            throw QuotaFailure.unavailable("DeepSeek 未返回可识别的余额")
        }
        var snapshot = QuotaSnapshot(provider: .deepSeek, windows: [], totalQuota: nil, resetCredits: nil, fetchedAt: now)
        snapshot.balance = BalanceQuota(remaining: amount, currency: currency.uppercased())
        return snapshot
    }
}

struct OpenRouterAdapter: QuotaAdapter {
    let provider: ProviderID = .openRouter
    let key: String
    func fetch() async throws -> QuotaSnapshot {
        try Self.parse(await QuotaHTTPClient.get("https://openrouter.ai/api/v1/credits", key: key, label: "OpenRouter"))
    }
    static func parse(_ data: Data, now: Date = Date()) throws -> QuotaSnapshot {
        let root = try QuotaJSON.object(data)
        guard let data = root["data"] as? [String: Any],
              let purchased = QuotaJSON.number(data["total_credits"]),
              let used = QuotaJSON.number(data["total_usage"]),
              (purchased - used).isFinite else {
            throw QuotaFailure.unavailable("OpenRouter 未返回可识别的余额，请使用 Management key")
        }
        var snapshot = QuotaSnapshot(provider: .openRouter, windows: [], totalQuota: nil, resetCredits: nil, fetchedAt: now)
        snapshot.balance = BalanceQuota(remaining: purchased - used, currency: "USD")
        return snapshot
    }
}
