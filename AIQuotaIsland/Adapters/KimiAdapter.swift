import Foundation

struct KimiAdapter: QuotaAdapter {
    let provider: ProviderID = .kimi
    let key: String
    func fetch() async throws -> QuotaSnapshot {
        try Self.parse(await QuotaHTTPClient.get("https://api.kimi.com/coding/v1/usages", key: key, label: "Kimi Code"))
    }

    static func parse(_ data: Data, now: Date = Date()) throws -> QuotaSnapshot {
        let root = try QuotaJSON.object(data)
        var windows: [QuotaWindow] = []
        if let pools = root["usages"] as? [String: Any] {
            for (name, seconds) in [("limit_5h", 18_000), ("limit_7d", 604_800), ("limit_month_total", 2_592_000)] {
                guard let pool = pools[name] as? [String: Any],
                      let used = QuotaJSON.number(pool["used_ratio"]), (0...1).contains(used) else { continue }
                windows.append(QuotaWindow(id: name, title: QuotaJSON.title(seconds), durationSeconds: seconds,
                                           remainingFraction: 1 - used, resetsAt: QuotaJSON.date(pool["reset_time"])))
            }
        }
        if windows.isEmpty {
            if let usage = root["usage"] as? [String: Any],
               let window = window(usage, id: "weekly", seconds: 604_800) { windows.append(window) }
            for (index, limit) in (root["limits"] as? [[String: Any]] ?? []).enumerated() {
                guard let spec = limit["window"] as? [String: Any],
                      let amount = QuotaJSON.number(spec["duration"]), amount > 0, amount < 365,
                      let unit = spec["timeUnit"] as? String,
                      let multiplier = ["TIME_UNIT_MINUTE": 60, "TIME_UNIT_HOUR": 3600, "TIME_UNIT_DAY": 86400][unit],
                      let detail = limit["detail"] as? [String: Any],
                      let parsed = window(detail, id: "limit-\(index)", seconds: Int(amount) * multiplier) else { continue }
                windows.append(parsed)
            }
        }
        return try QuotaJSON.snapshot(.kimi, windows: windows.sorted { ($0.durationSeconds ?? 0) < ($1.durationSeconds ?? 0) }, now: now)
    }

    private static func window(_ value: [String: Any], id: String, seconds: Int) -> QuotaWindow? {
        guard let total = QuotaJSON.number(value["limit"]), total > 0 else { return nil }
        let remaining = QuotaJSON.number(value["remaining"]) ?? QuotaJSON.number(value["used"]).map { total - $0 }
        guard let remaining, remaining >= 0, remaining <= total else { return nil }
        let reset = QuotaJSON.date(value["resetTime"] ?? value["resetAt"] ?? value["reset_time"] ?? value["reset_at"])
        // These counts are upstream credits, not tokens.
        return QuotaWindow(id: id, title: QuotaJSON.title(seconds), durationSeconds: seconds,
                           remainingFraction: remaining / total, resetsAt: reset)
    }
}
