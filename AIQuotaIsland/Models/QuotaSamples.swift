import Foundation

enum QuotaSamples {
    static func snapshot(for config: ProviderConfig, now: Date = Date()) -> QuotaSnapshot {
        if config.provider.isBalance {
            var result = QuotaSnapshot(provider: config.provider, windows: [], totalQuota: nil,
                                       resetCredits: nil, fetchedAt: now)
            result.balance = BalanceQuota(remaining: 50, currency: config.provider == .openRouter ? "USD" : "CNY")
            return result
        }
        if config.template == .single {
            if config.provider != .spark && config.provider != .custom {
                return QuotaSnapshot(provider: config.provider,
                                     windows: [QuotaWindow(id: "5h", title: "5 小时", durationSeconds: 18_000,
                                                           remainingFraction: 0.8, resetsAt: now.addingTimeInterval(7200))],
                                     totalQuota: nil, resetCredits: nil, fetchedAt: now)
            }
            return QuotaSnapshot(provider: config.provider, windows: [],
                                 totalQuota: TotalQuota(remaining: 996_000_000, total: 1_000_000_000,
                                                       unit: "tokens", expiresAt: now.addingTimeInterval(2_592_000)),
                                 resetCredits: nil, fetchedAt: now)
        }
        let windows = [
            QuotaWindow(id: "5h", title: "5 小时", durationSeconds: 18_000, remainingFraction: 0.8,
                        resetsAt: now.addingTimeInterval(7_200)),
            QuotaWindow(id: "week", title: "本周", durationSeconds: 604_800, remainingFraction: 0.6,
                        resetsAt: now.addingTimeInterval(345_600))
        ]
        return QuotaSnapshot(provider: config.provider, windows: windows, totalQuota: nil,
                             resetCredits: config.provider == .codex ? ResetCredits(availableCount: 2, expiresAt: nil) : nil,
                             fetchedAt: now)
    }
}
