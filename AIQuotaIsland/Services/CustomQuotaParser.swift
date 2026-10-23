import Foundation

enum CustomQuotaParser {
    static func parse(_ value: [String: Any], now: Date = Date()) throws -> QuotaSnapshot {
        try validateNumbers(value)
        if let valid = value["isValid"], !(valid is NSNull) {
            guard let flag = valid as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID() else {
                throw QuotaFailure.unavailable("isValid 必须是布尔值")
            }
            if !flag.boolValue {
                throw QuotaFailure.unavailable(String((value["invalidMessage"] as? String ?? "套餐无效").prefix(160)))
            }
        }
        var snapshot = QuotaSnapshot(provider: .custom, windows: [], totalQuota: nil, resetCredits: nil, fetchedAt: now)
        if let rawWindows = value["windows"] {
            guard let items = rawWindows as? [[String: Any]], !items.isEmpty, items.count <= 3 else {
                throw QuotaFailure.unavailable("windows 必须包含1至3个真实额度周期")
            }
            var ids = Set<String>()
            var windows: [QuotaWindow] = []
            for item in items {
                try validateNumbers(item)
                guard let id = item["id"] as? String, !id.isEmpty, ids.insert(id).inserted,
                      let title = item["title"] as? String, !title.isEmpty,
                      let duration = QuotaJSON.number(item["durationSeconds"]),
                      let seconds = Int(exactly: duration), seconds > 0 else {
                    throw QuotaFailure.unavailable("每个窗口需有唯一id、名称和有效durationSeconds")
                }
                let fraction: Double
                let amount = QuotaJSON.number(item["remaining"])
                let total = QuotaJSON.number(item["total"])
                if let amount, let total, total > 0, (0...total).contains(amount) { fraction = amount / total }
                else if let percent = QuotaJSON.number(item["remainingPercent"]), (0...100).contains(percent) { fraction = percent / 100 }
                else { throw QuotaFailure.unavailable("窗口需提供有效remaining/total或remainingPercent") }
                var window = QuotaWindow(id: id, title: String(title.prefix(12)), durationSeconds: seconds,
                                         remainingFraction: fraction, resetsAt: try time(item["resetsAt"]))
                if let amount, amount >= 0, let unit = item["unit"] as? String {
                    window.remainingAmount = amount
                    window.totalAmount = total
                    window.unit = unit
                }
                windows.append(window)
            }
            snapshot = QuotaSnapshot(provider: .custom, windows: windows.sorted { $0.durationSeconds! < $1.durationSeconds! },
                                     totalQuota: nil, resetCredits: nil, fetchedAt: now)
        } else {
            let unit = value["unit"] as? String ?? "额度"
            let multiplier: Double = ["K": 1_000, "M": 1_000_000, "亿": 100_000_000][unit] ?? 1
            let total = QuotaJSON.number(value["total"]).map { $0 * multiplier }
            let used = QuotaJSON.number(value["used"]).map { $0 * multiplier }
            let remaining = QuotaJSON.number(value["remaining"]).map { $0 * multiplier }
                ?? total.flatMap { total in used.map { total - $0 } }
            guard let remaining, remaining.isFinite else { throw QuotaFailure.unavailable("未返回有效的remaining剩余数量") }
            if let total, (!total.isFinite || total < 0 || remaining < 0 || remaining > total) {
                throw QuotaFailure.unavailable("剩余与总量字段不一致")
            }
            if ["CNY", "RMB", "￥", "¥", "元", "USD", "$"].contains(unit.uppercased()) {
                snapshot.balance = BalanceQuota(remaining: remaining, currency: ["USD", "$"].contains(unit.uppercased()) ? "USD" : "CNY")
            } else {
                let rawUnit = multiplier == 1 ? unit : "tokens"
                var quota = TotalQuota(remaining: remaining, total: total, unit: rawUnit, expiresAt: try time(value["expiresAt"]))
                quota.resetsAt = try time(value["resetsAt"])
                snapshot = QuotaSnapshot(provider: .custom, windows: [], totalQuota: quota, resetCredits: nil, fetchedAt: now)
            }
        }
        snapshot.planName = (value["planName"] as? String).map { String($0.prefix(60)) }
        snapshot.extra = (value["extra"] as? String).map { String($0.prefix(160)) }
        return snapshot
    }

    private static func time(_ raw: Any?) throws -> Date? {
        guard let raw, !(raw is NSNull) else { return nil }
        guard let date = QuotaJSON.date(raw) else {
            throw QuotaFailure.unavailable("时间字段应为带时区的ISO 8601字符串或Unix秒时间戳")
        }
        return date
    }

    private static func validateNumbers(_ value: [String: Any]) throws {
        for key in ["remaining", "total", "used", "remainingPercent"] {
            if let raw = value[key], !(raw is NSNull), QuotaJSON.number(raw) == nil {
                throw QuotaFailure.unavailable("额度字段必须是有限数，不能是布尔值或无效文本")
            }
        }
    }
}
