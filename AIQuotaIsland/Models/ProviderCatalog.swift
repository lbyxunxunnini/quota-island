import Foundation

enum CardTemplate: String, Codable, CaseIterable, Identifiable, Sendable {
    case multi, chatGPT, single
    var id: String { rawValue }
    var title: String {
        switch self {
        case .multi: "多额度"
        case .chatGPT: "ChatGPT"
        case .single: "单额度"
        }
    }
}

extension ProviderID {
    var website: String {
        switch self {
        case .codex: "chatgpt.com"
        case .opencodeGo: "opencode.ai"
        case .spark: "maas.xfyun.cn"
        case .deepSeek: "platform.deepseek.com"
        case .kimi: "kimi.com/code"
        case .glm: "open.bigmodel.cn"
        case .miniMax: "minimax.cn"
        case .openRouter: "openrouter.ai"
        case .stepFun: "platform.stepfun.com"
        case .custom: "HTTP 请求与提取脚本"
        }
    }

    var credentialTitle: String {
        switch self {
        case .codex: "本机 Codex 登录"
        case .spark: "Cookie"
        case .openRouter: "Management key"
        case .stepFun: "Oasis-Token"
        case .kimi: "Kimi Code API Key"
        case .glm, .miniMax: "套餐 API Key"
        default: "API Key"
        }
    }

    var credentialHint: String {
        switch self {
        case .codex: "自动读取本机 Codex 的 ChatGPT 登录，不能添加其他实例。"
        case .spark: "仅查询讯飞-x2.6临时免费 tokens，粘贴该页面的完整 Cookie。"
        case .openRouter: "使用 Management key 查询账户余额，普通推理 Key 不适用。"
        case .stepFun: "使用网页 Oasis-Token 查询 Step Plan 套餐。"
        case .kimi: "使用 Kimi Code 套餐 Key；开放平台和网页会员凭据不互通。"
        case .glm, .miniMax: "使用对应 Coding Plan 的套餐 Key 查询额度。"
        default: "先查询验证，成功后仅保存在本 App 的 Keychain。"
        }
    }

    var defaultTemplate: CardTemplate {
        switch self {
        case .codex: .chatGPT
        case .spark, .deepSeek, .openRouter, .custom: .single
        default: .multi
        }
    }

    var isBalance: Bool { self == .deepSeek || self == .openRouter }
    var availableTemplates: [CardTemplate] {
        if self == .codex { return [.chatGPT] }
        if isBalance || self == .spark { return [.single] }
        return [.multi, .single]
    }
}

enum QuotaFormat {
    static func compact(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let absolute = abs(value)
        let divisor: Double
        let suffix: String
        if absolute >= 100_000_000 { divisor = 100_000_000; suffix = "亿" }
        else if absolute >= 1_000_000 { divisor = 1_000_000; suffix = "M" }
        else if absolute >= 1_000 { divisor = 1_000; suffix = "K" }
        else { divisor = 1; suffix = "" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        return (formatter.string(from: NSNumber(value: value / divisor)) ?? "—") + suffix
    }

    static func currencySymbol(_ currency: String?) -> String {
        currency?.uppercased() == "USD" ? "$" : "￥"
    }

    static func money(_ amount: Double, currency: String?) -> String {
        guard amount.isFinite else { return "—" }
        return currencySymbol(currency) + String(format: "%.2f", amount)
    }

    static func waterLevel(_ amount: Double) -> Double {
        if amount <= 0 { return 0 }
        if amount <= 10 { return 0.14 }
        if amount <= 100 { return 0.5 }
        return 0.8
    }

    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    static func countdown(_ date: Date, now: Date) -> String {
        guard date > now else { return "即将重置" }
        let seconds = Int(date.timeIntervalSince(now))
        if seconds >= 86_400 { return "\(seconds / 86_400)天 \((seconds % 86_400) / 3600)小时" }
        if seconds >= 3600 { return "\(seconds / 3600)小时 \((seconds % 3600) / 60)分钟" }
        return "\(max(1, seconds / 60))分钟"
    }

    static func elapsed(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(seconds / 60)分钟前" }
        if seconds < 86_400 { return "\(seconds / 3600)小时前" }
        return "\(seconds / 86_400)天前"
    }
}
