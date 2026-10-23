import Foundation

struct ProviderConfig: Codable, Identifiable, Equatable {
    let id: ProviderID
    var displayName: String
    var isVisible: Bool
    var showInCompact: Bool

    init(id: ProviderID, displayName: String? = nil, isVisible: Bool = true, showInCompact: Bool = true) {
        self.id = id
        self.displayName = displayName ?? id.defaultName
        self.isVisible = isVisible
        self.showInCompact = showInCompact
    }

    var compactSymbol: String {
        id.compactSymbol
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var providers: [ProviderConfig] {
        didSet { save() }
    }
    @Published var desktopVisible: Bool {
        didSet { UserDefaults.standard.set(desktopVisible, forKey: "desktopVisible") }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "providerConfigs"),
           let saved = try? JSONDecoder().decode([ProviderConfig].self, from: data) {
            var merged = saved.filter { ProviderID.allCases.contains($0.id) }
            for id in ProviderID.allCases where !merged.contains(where: { $0.id == id }) {
                merged.append(ProviderConfig(id: id))
            }
            if let index = merged.firstIndex(where: { $0.id == .codex }), merged[index].displayName == "Codex" {
                merged[index].displayName = ProviderID.codex.defaultName
                if let migrated = try? JSONEncoder().encode(merged) {
                    UserDefaults.standard.set(migrated, forKey: "providerConfigs")
                }
            }
            providers = merged
        } else {
            providers = [.init(id: .opencodeGo), .init(id: .codex), .init(id: .spark)]
        }
        desktopVisible = UserDefaults.standard.object(forKey: "desktopVisible") as? Bool ?? true
    }

    var visibleProviders: [ProviderConfig] { providers.filter(\.isVisible) }
    var compactProviders: [ProviderConfig] { visibleProviders.filter(\.showInCompact).prefix(3).map { $0 } }

    func move(_ id: ProviderID, by offset: Int) {
        guard let oldIndex = providers.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = oldIndex + offset
        guard providers.indices.contains(newIndex) else { return }
        providers.swapAt(oldIndex, newIndex)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        UserDefaults.standard.set(data, forKey: "providerConfigs")
    }
}
