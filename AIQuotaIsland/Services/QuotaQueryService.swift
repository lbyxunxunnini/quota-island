import Foundation

enum QuotaQueryService {
    static func fetch(_ config: ProviderConfig, credentials: KeychainStore.Credentials) async throws -> QuotaSnapshot {
        switch config.provider {
        case .codex:
            return try await CodexAdapter().fetch()
        case .opencodeGo:
            if config.isLegacy && credentials.apiKey.isEmpty { return try await OpenCodeGoAdapter().fetch() }
            return try await OpenCodeGoAdapter().validate(key: credentials.apiKey)
        case .deepSeek:
            return try await DeepSeekAdapter(key: credentials.apiKey).fetch()
        case .kimi:
            return try await KimiAdapter(key: credentials.apiKey).fetch()
        case .glm:
            return try await GLMAdapter(key: credentials.apiKey).fetch()
        case .miniMax:
            return try await MiniMaxAdapter(key: credentials.apiKey).fetch()
        case .openRouter:
            return try await OpenRouterAdapter(key: credentials.apiKey).fetch()
        case .stepFun:
            return try await StepFunAdapter(token: credentials.apiKey).fetch()
        case .custom:
            return try await CustomScriptEngine.fetch(config, credentials: credentials)
        }
    }
}
