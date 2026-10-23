import Foundation

enum ProviderID: String, CaseIterable, Codable, Sendable, Identifiable {
    case codex
    case opencodeGo
    case spark

    var id: String { rawValue }

    var defaultName: String {
        switch self {
        case .codex: "ChatGPT"
        case .opencodeGo: "OpenCode Go"
        case .spark: "讯飞星火 X2.6"
        }
    }

    var compactSymbol: String {
        switch self {
        case .codex: "G"
        case .opencodeGo: "O"
        case .spark: "讯"
        }
    }
}

struct QuotaWindow: Identifiable, Sendable {
    let id: String
    let title: String
    let durationSeconds: Int?
    let remainingFraction: Double
    let resetsAt: Date?

    var clampedFraction: Double { min(1, max(0, remainingFraction)) }
}

struct TotalQuota: Sendable {
    let remaining: Double
    let total: Double
    let unit: String
    let expiresAt: Date?

    var remainingFraction: Double? {
        guard total > 0 else { return nil }
        return min(1, max(0, remaining / total))
    }
}

struct ResetCredits: Sendable {
    let availableCount: Int
    let expiresAt: Date?
}

struct QuotaSnapshot: Sendable {
    let provider: ProviderID
    let windows: [QuotaWindow]
    let totalQuota: TotalQuota?
    let resetCredits: ResetCredits?
    let fetchedAt: Date

    var ringWindow: QuotaWindow? {
        windows.min { ($0.durationSeconds ?? .max) < ($1.durationSeconds ?? .max) }
    }

    var remainingFraction: Double? {
        ringWindow?.clampedFraction ?? totalQuota?.remainingFraction
    }

    var isLargeCard: Bool { windows.count > 1 || resetCredits != nil }
}

enum QuotaPercentage {
    static func whole(_ fraction: Double) -> Int? {
        guard fraction.isFinite else { return nil }
        return Int((min(1, max(0, fraction)) * 100).rounded(.down))
    }

    static func text(_ fraction: Double) -> String {
        guard let value = whole(fraction) else { return "—" }
        return value == 100 ? "100" : "\(value)%"
    }
}

enum QuotaFailureKind: Sendable, Equatable {
    case authentication
    case expired
    case unavailable
    case temporary
}

struct QuotaFailure: Error, Sendable {
    let kind: QuotaFailureKind
    let message: String

    static func authentication(_ message: String) -> Self { .init(kind: .authentication, message: message) }
    static func expired(_ message: String) -> Self { .init(kind: .expired, message: message) }
    static func unavailable(_ message: String) -> Self { .init(kind: .unavailable, message: message) }
    static func temporary(_ message: String) -> Self { .init(kind: .temporary, message: message) }
}

protocol QuotaAdapter: Sendable {
    var provider: ProviderID { get }
    func fetch() async throws -> QuotaSnapshot
}

enum QuotaDateParser {
    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = TimeZone(identifier: "Asia/Shanghai")
        local.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return local.date(from: value)
    }
}
