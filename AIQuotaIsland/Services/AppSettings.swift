import Foundation

struct ProviderConfig: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    let provider: ProviderID
    var customName: String
    var remark: String
    var isVisible: Bool
    var showInCompact: Bool
    var template: CardTemplate
    var baseURL: String
    var script: String
    var timeout: Double
    var currency: String?
    var isLegacy: Bool

    init(provider: ProviderID, name: String = "", id: UUID = UUID()) {
        self.id = id
        self.provider = provider
        customName = name.isEmpty ? provider.defaultName : name
        remark = ""
        isVisible = true
        showInCompact = provider == .codex
        template = provider.defaultTemplate
        baseURL = ""
        script = ""
        timeout = 10
        currency = nil
        isLegacy = false
    }

    init(id: ProviderID, displayName: String? = nil, isVisible: Bool = true, showInCompact: Bool = true) {
        self.init(provider: id, name: displayName ?? "")
        self.isVisible = isVisible
        self.showInCompact = showInCompact
    }

    var displayName: String {
        get { provider == .custom ? customName : provider.defaultName }
        set { if provider == .custom { customName = newValue } }
    }
    var title: String { remark.isEmpty ? displayName : "\(displayName) · \(remark)" }
    var compactSymbol: String {
        provider == .custom ? String(displayName.prefix(1)).uppercased() : provider.compactSymbol
    }

    private enum CodingKeys: String, CodingKey {
        case id, provider, displayName, customName, remark, isVisible, showInCompact
        case template, baseURL, script, timeout, currency, isLegacy
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let provider = try values.decodeIfPresent(ProviderID.self, forKey: .provider) {
            self.init(provider: provider, id: try values.decode(UUID.self, forKey: .id))
            isLegacy = try values.decodeIfPresent(Bool.self, forKey: .isLegacy) ?? false
        } else {
            let provider = try values.decode(ProviderID.self, forKey: .id)
            self.init(provider: provider)
            isLegacy = true
        }
        customName = try values.decodeIfPresent(String.self, forKey: .customName)
            ?? values.decodeIfPresent(String.self, forKey: .displayName) ?? provider.defaultName
        remark = try values.decodeIfPresent(String.self, forKey: .remark) ?? ""
        if !values.contains(.remark) && isLegacy && customName != provider.defaultName
            && !["Codex", "讯飞星火 X2.6"].contains(customName) { remark = customName }
        isVisible = try values.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        showInCompact = try values.decodeIfPresent(Bool.self, forKey: .showInCompact) ?? false
        template = try values.decodeIfPresent(CardTemplate.self, forKey: .template) ?? provider.defaultTemplate
        baseURL = try values.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        script = try values.decodeIfPresent(String.self, forKey: .script) ?? ""
        timeout = try values.decodeIfPresent(Double.self, forKey: .timeout) ?? 10
        currency = try values.decodeIfPresent(String.self, forKey: .currency)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(provider, forKey: .provider)
        try values.encode(customName, forKey: .customName)
        try values.encode(remark, forKey: .remark)
        try values.encode(isVisible, forKey: .isVisible)
        try values.encode(showInCompact, forKey: .showInCompact)
        try values.encode(template, forKey: .template)
        try values.encode(baseURL, forKey: .baseURL)
        try values.encode(script, forKey: .script)
        try values.encode(timeout, forKey: .timeout)
        try values.encodeIfPresent(currency, forKey: .currency)
        try values.encode(isLegacy, forKey: .isLegacy)
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private struct StoredProvider: Decodable {
        let config: ProviderConfig?

        private enum CodingKeys: String, CodingKey { case provider, id }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let rawProvider = try values.decodeIfPresent(String.self, forKey: .provider)
                ?? values.decode(String.self, forKey: .id)
            // Removed providers must not invalidate the remaining saved instances.
            config = ProviderID(rawValue: rawProvider) == nil ? nil : try ProviderConfig(from: decoder)
        }
    }

    static let refreshChoices = [1, 3, 5, 10, 15, 30]
    private let defaults: UserDefaults
    @Published var providers: [ProviderConfig] { didSet { save() } }
    @Published var desktopVisible: Bool { didSet { defaults.set(desktopVisible, forKey: "desktopVisible") } }
    @Published var refreshMinutes: Int { didSet { defaults.set(refreshMinutes, forKey: "refreshMinutes") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var initial: [ProviderConfig]
        if let data = defaults.data(forKey: "providerConfigs"),
           let stored = try? JSONDecoder().decode([StoredProvider].self, from: data) {
            let saved = stored.compactMap(\.config)
            var seen = Set<UUID>()
            var hasChatGPT = false
            initial = saved.filter { item in
                guard seen.insert(item.id).inserted else { return false }
                if item.provider == .codex {
                    guard !hasChatGPT else { return false }
                    hasChatGPT = true
                }
                return true
            }
            if !hasChatGPT { initial.insert(ProviderConfig(provider: .codex), at: 0) }
        } else {
            initial = [ProviderConfig(provider: .codex)]
        }
        providers = initial
        desktopVisible = defaults.object(forKey: "desktopVisible") as? Bool ?? true
        let minutes = defaults.integer(forKey: "refreshMinutes")
        refreshMinutes = Self.refreshChoices.contains(minutes) ? minutes : 3
        save()
    }

    var visibleProviders: [ProviderConfig] { providers.filter(\.isVisible) }
    var compactProviders: [ProviderConfig] {
        Array(visibleProviders.filter(\.showInCompact).prefix(4))
    }
    func config(_ id: UUID) -> ProviderConfig? { providers.first { $0.id == id } }
    func add(_ config: ProviderConfig) {
        guard config.provider != .codex, !providers.contains(where: { $0.id == config.id }) else { return }
        var added = config
        added.showInCompact = compactProviders.count == 1
        providers.append(added)
    }
    func update(_ config: ProviderConfig) {
        guard let index = providers.firstIndex(where: { $0.id == config.id }) else { return }
        providers[index] = config
    }
    func remove(_ id: UUID) {
        providers.removeAll { $0.id == id && $0.provider != .codex }
    }
    func move(_ source: UUID, to destination: UUID) {
        guard source != destination,
              let from = providers.firstIndex(where: { $0.id == source }),
              let to = providers.firstIndex(where: { $0.id == destination }) else { return }
        var reordered = providers
        let value = reordered.remove(at: from)
        reordered.insert(value, at: to)
        providers = reordered
    }
    private func save() {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        defaults.set(data, forKey: "providerConfigs")
    }
}
