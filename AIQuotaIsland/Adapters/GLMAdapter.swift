import Foundation

struct GLMAdapter: QuotaAdapter {
    let provider: ProviderID = .glm
    let key: String
    func fetch() async throws -> QuotaSnapshot {
        try QuotaHTTPClient.validateCredential(key, label: "智谱GLM套餐 Key")
        var request = URLRequest(url: URL(string: "https://open.bigmodel.cn/api/monitor/usage/quota/limit")!)
        request.timeoutInterval = 15
        request.setValue(key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try Self.parse(await QuotaHTTPClient.send(request, label: "智谱GLM"))
    }
    static func parse(_ data: Data, now: Date = Date()) throws -> QuotaSnapshot {
        let root = try QuotaJSON.object(data)
        guard root["success"] as? Bool != false,
              let body = root["data"] as? [String: Any],
              let limits = body["limits"] as? [[String: Any]] else {
            throw QuotaFailure.unavailable("智谱GLM 未返回套餐额度，请确认已开通 Coding Plan")
        }
        let modelLimits = limits.filter {
            ["TOKENS_LIMIT", "CREDIT_LIMIT"].contains(($0["type"] as? String ?? "").uppercased())
        }
        var windows: [QuotaWindow] = []
        for (index, item) in limits.enumerated() {
            let type = (item["type"] as? String ?? "").uppercased()
            guard let used = QuotaJSON.number(item["percentage"]), (0...100).contains(used) else { continue }
            let period: Int
            let title: String
            if type == "TIMES_LIMIT" {
                period = 2_592_000; title = "月工具"
            } else if ["TOKENS_LIMIT", "CREDIT_LIMIT"].contains(type) {
                switch QuotaJSON.number(item["unit"]) {
                case 3: period = 18_000
                case 6: period = 604_800
                default:
                    guard modelLimits.count == 1 else { continue }
                    period = 18_000
                }
                title = QuotaJSON.title(period)
            } else { continue }
            guard !windows.contains(where: { $0.durationSeconds == period }) else { continue }
            windows.append(QuotaWindow(id: "glm-\(index)", title: title, durationSeconds: period,
                                       remainingFraction: 1 - used / 100,
                                       resetsAt: QuotaJSON.date(item["nextResetTime"])))
        }
        return try QuotaJSON.snapshot(.glm, windows: windows.sorted { ($0.durationSeconds ?? 0) < ($1.durationSeconds ?? 0) }, now: now)
    }
}
