import Foundation

struct StepFunAdapter: QuotaAdapter {
    let provider: ProviderID = .stepFun
    let token: String
    func fetch() async throws -> QuotaSnapshot {
        try QuotaHTTPClient.validateCredential(token, label: "Oasis-Token")
        guard let device = Self.deviceID(token) else {
            throw QuotaFailure.authentication("Oasis-Token 缺少设备信息，请复制完整令牌")
        }
        var request = URLRequest(url: URL(string: "https://platform.stepfun.com/api/step.openapi.devcenter.Dashboard/QueryStepPlanRateLimit")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("10300", forHTTPHeaderField: "oasis-appid")
        request.setValue("web", forHTTPHeaderField: "oasis-platform")
        request.setValue(device, forHTTPHeaderField: "oasis-webid")
        request.setValue("Oasis-Token=\(token); Oasis-Webid=\(device)", forHTTPHeaderField: "Cookie")
        return try Self.parse(await QuotaHTTPClient.send(request, label: "阶跃星辰"))
    }

    static func parse(_ data: Data, now: Date = Date()) throws -> QuotaSnapshot {
        let root = try QuotaJSON.object(data)
        guard QuotaJSON.number(root["status"]) == 1 else {
            throw QuotaFailure.authentication("阶跃星辰查询失败，请检查令牌或套餐状态")
        }
        var windows: [QuotaWindow] = []
        for (key, resetKey, seconds) in [
            ("five_hour_usage_left_rate", "five_hour_usage_reset_time", 18_000),
            ("weekly_usage_left_rate", "weekly_usage_reset_time", 604_800)
        ] {
            guard let reset = QuotaJSON.date(root[resetKey]),
                  let fraction = QuotaJSON.number(root[key]), (0...1).contains(fraction) else { continue }
            windows.append(QuotaWindow(id: key, title: QuotaJSON.title(seconds), durationSeconds: seconds,
                                       remainingFraction: fraction, resetsAt: reset))
        }
        if !windows.isEmpty { return try QuotaJSON.snapshot(.stepFun, windows: windows, now: now) }
        guard let pool = root["plan_credit_rate_limit"] as? [String: Any] else {
            throw QuotaFailure.unavailable("阶跃星辰未返回可识别的套餐额度")
        }
        if let buckets = pool["credit_buckets"] as? [[String: Any]], !buckets.isEmpty {
            var total = 0.0
            var remaining = 0.0
            for bucket in buckets {
                guard let capacity = QuotaJSON.number(bucket["credit_total"]), capacity > 0,
                      let value = QuotaJSON.number(bucket["credit_residual"]), (0...capacity).contains(value) else {
                    throw QuotaFailure.unavailable("阶跃 credits 字段格式异常")
                }
                total += capacity; remaining += value
            }
            guard total.isFinite, remaining.isFinite else { throw QuotaFailure.unavailable("阶跃 credits 数量无效") }
            let expiries = buckets.compactMap { QuotaJSON.date($0["expire_at"]) }
            let resets = buckets.compactMap { QuotaJSON.date($0["next_reset_at"]) }
            let expiry = expiries.count == buckets.count && Set(expiries).count == 1 ? expiries.first : nil
            var quota = TotalQuota(remaining: remaining, total: total, unit: "credits", expiresAt: expiry)
            quota.resetsAt = resets.count == buckets.count && Set(resets).count == 1 ? resets.first : nil
            return QuotaSnapshot(provider: .stepFun, windows: [], totalQuota: quota, resetCredits: nil, fetchedAt: now)
        }
        guard let fraction = QuotaJSON.number(pool["subscription_credit_left_rate"] ?? pool["topup_credit_left_rate"]),
              (0...1).contains(fraction) else {
            throw QuotaFailure.unavailable("阶跃星辰未返回剩余额度")
        }
        let window = QuotaWindow(id: "credit", title: "本月", durationSeconds: 2_592_000,
                                 remainingFraction: fraction, resetsAt: QuotaJSON.date(pool["subscription_credit_reset_time"]))
        return try QuotaJSON.snapshot(.stepFun, windows: [window], now: now)
    }

    private static func deviceID(_ token: String) -> String? {
        for half in token.components(separatedBy: "...").reversed() {
            let parts = half.split(separator: ".")
            guard parts.count >= 2 else { continue }
            var text = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            text += String(repeating: "=", count: (4 - text.count % 4) % 4)
            guard let data = Data(base64Encoded: text),
                  let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = value["device_id"] as? String, !id.isEmpty,
                  !id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { continue }
            return id
        }
        return nil
    }
}
