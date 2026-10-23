import Foundation

struct MiniMaxAdapter: QuotaAdapter {
    let provider: ProviderID = .miniMax
    let key: String
    func fetch() async throws -> QuotaSnapshot {
        do {
            return try Self.parse(await QuotaHTTPClient.get("https://www.minimax.cn/v1/token_plan/remains", key: key, label: "MiniMax"))
        } catch let failure as QuotaFailure where failure.kind == .unavailable {
            return try Self.parse(await QuotaHTTPClient.get("https://www.minimax.cn/v1/api/openplatform/coding_plan/remains", key: key, label: "MiniMax"))
        }
    }
    static func parse(_ data: Data, now: Date = Date()) throws -> QuotaSnapshot {
        let root = try QuotaJSON.object(data)
        let body = root["data"] as? [String: Any] ?? root
        let base = body["base_resp"] as? [String: Any] ?? root["base_resp"] as? [String: Any]
        if let status = QuotaJSON.number(base?["status_code"]), status != 0 {
            if status == 1004 { throw QuotaFailure.authentication("MiniMax 套餐 Key 无效，请更换") }
            throw QuotaFailure.unavailable("MiniMax 套餐查询失败，请确认订阅有效")
        }
        guard let items = body["model_remains"] as? [[String: Any]], !items.isEmpty else {
            throw QuotaFailure.unavailable("MiniMax 未返回可识别的套餐额度")
        }
        let item = items.first {
            let name = ($0["model_name"] as? String ?? "").lowercased()
            return name.contains("m2") || name.contains("text")
        } ?? items[0]
        var windows: [QuotaWindow] = []
        for (prefix, seconds, endKey) in [("current_interval", 18_000, "end_time"), ("current_weekly", 604_800, "weekly_end_time")] {
            let total = QuotaJSON.number(item[prefix + "_total_count"])
            let remaining = QuotaJSON.number(item[prefix + "_usage_count"])
            let fraction: Double?
            if let percent = QuotaJSON.number(item[prefix + "_remaining_percent"]), (0...100).contains(percent) {
                fraction = percent / 100
            } else if let total, total > 0, let remaining, (0...total).contains(remaining) {
                fraction = remaining / total
            } else { fraction = nil }
            guard let fraction else { continue }
            var window = QuotaWindow(id: prefix, title: QuotaJSON.title(seconds), durationSeconds: seconds,
                                     remainingFraction: fraction, resetsAt: QuotaJSON.date(item[endKey]))
            if let unit = item["unit"] as? String, let total, total > 0, let remaining, (0...total).contains(remaining) {
                window.remainingAmount = remaining
                window.totalAmount = total
                window.unit = unit
            }
            windows.append(window)
        }
        var snapshot = try QuotaJSON.snapshot(.miniMax, windows: windows, now: now)
        snapshot.planName = body["current_subscribe_title"] as? String ?? body["plan_name"] as? String
        return snapshot
    }
}
