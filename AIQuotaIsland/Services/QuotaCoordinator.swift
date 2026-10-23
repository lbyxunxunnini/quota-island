import AppKit
import Combine
import Foundation
import Network

struct ProviderState {
    var snapshot: QuotaSnapshot?
    var failure: QuotaFailure?
    var isRefreshing = false

    func effectiveFailure(at date: Date) -> QuotaFailure? {
        if let expiry = snapshot?.totalQuota?.expiresAt, expiry <= date { return .expired("已到期") }
        return failure
    }
}

@MainActor
final class QuotaCoordinator: ObservableObject {
    @Published private(set) var states: [UUID: ProviderState] = [:]
    @Published private(set) var now = Date()
    @Published private(set) var isRefreshing = false
    @Published private(set) var expansionID = UUID()
    let settings: AppSettings
    typealias Query = @Sendable (ProviderConfig, KeychainStore.Credentials) async throws -> QuotaSnapshot
    private let query: Query
    private let vault: CredentialVault
    private var refreshTimer: Timer?
    private var clockTimer: Timer?
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "AIQuotaIsland.network")
    private var lastNetworkSatisfied = true
    private var retryAfter: [UUID: Date] = [:]
    private var generations: [UUID: UUID] = [:]
    private var saveTokens: [UUID: UUID] = [:]
    private var wakeObserver: NSObjectProtocol?
    private var observations = Set<AnyCancellable>()

    init(settings: AppSettings? = nil,
         query: @escaping Query = { config, credentials in try await QuotaQueryService.fetch(config, credentials: credentials) },
         vault: CredentialVault = .keychain) {
        self.settings = settings ?? AppSettings()
        self.query = query
        self.vault = vault
        for config in self.settings.providers { states[config.id] = ProviderState() }
        self.settings.$refreshMinutes.dropFirst().sink { [weak self] minutes in
            self?.installRefreshTimer(minutes)
        }.store(in: &observations)
        self.settings.$providers.sink { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let ids = Set(self.settings.providers.map(\.id))
                self.states = self.states.filter { ids.contains($0.key) }
                self.generations = self.generations.filter { ids.contains($0.key) }
                self.retryAfter = self.retryAfter.filter { ids.contains($0.key) }
            }
        }.store(in: &observations)
    }

    func start() {
        guard clockTimer == nil else { return }
        installRefreshTimer(settings.refreshMinutes)
        clockTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in await self?.refreshAll(force: true) } }
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let satisfied = path.status == .satisfied
                if satisfied && !self.lastNetworkSatisfied { await self.refreshAll(force: true) }
                self.lastNetworkSatisfied = satisfied
            }
        }
        networkMonitor.start(queue: networkQueue)
        Task { await refreshAll(force: true) }
    }

    private func installRefreshTimer(_ minutes: Int) {
        refreshTimer?.invalidate()
        guard AppSettings.refreshChoices.contains(minutes) else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Double(minutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAll() }
        }
    }

    func didExpand() { expansionID = UUID() }

    func refreshAll(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await withTaskGroup(of: Void.self) { group in
            for config in settings.providers {
                group.addTask { await self.refresh(config.id, force: force) }
            }
        }
    }

    func refresh(_ id: UUID, force: Bool = false) async {
        guard let config = settings.config(id), states[id]?.isRefreshing != true else { return }
        if !force, let retry = retryAfter[id], retry > Date() { return }
        if !force, states[id]?.failure?.kind == .authentication { return }
        let generation = UUID()
        generations[id] = generation
        states[id, default: ProviderState()].isRefreshing = true
        defer {
            if generations[id] == generation { states[id, default: ProviderState()].isRefreshing = false }
        }
        do {
            let credentials = config.provider == .codex ? KeychainStore.Credentials()
                : try vault.read(config)
            let snapshot = try await query(config, credentials)
            guard settings.config(id) != nil, generations[id] == generation else { return }
            states[id] = ProviderState(snapshot: snapshot)
            retryAfter[id] = nil
            rememberCurrency(snapshot, for: id)
        } catch {
            guard settings.config(id) != nil, generations[id] == generation else { return }
            let failure = error as? QuotaFailure ?? .temporary("查询暂时失败，请稍后重试")
            states[id, default: ProviderState()].failure = failure
            if failure.kind == .temporary { retryAfter[id] = Date().addingTimeInterval(120) }
        }
    }

    func validate(_ config: ProviderConfig, credentials: KeychainStore.Credentials) async throws -> QuotaSnapshot {
        try await query(config, credentials)
    }

    func credentials(for config: ProviderConfig) throws -> KeychainStore.Credentials { try vault.read(config) }

    func save(_ config: ProviderConfig, credentials: KeychainStore.Credentials) async throws {
        guard config.provider != .codex else { return }
        let existed = settings.config(config.id) != nil
        let token = UUID()
        saveTokens[config.id] = token
        defer { if saveTokens[config.id] == token { saveTokens[config.id] = nil } }
        let snapshot = try await validate(config, credentials: credentials)
        try Task.checkCancellation()
        guard saveTokens[config.id] == token, !existed || settings.config(config.id) != nil else {
            throw QuotaFailure.unavailable("模型已删除或有更新的保存操作，请重新打开配置")
        }
        try vault.write(credentials, config.id)
        generations[config.id] = UUID()
        if settings.config(config.id) == nil { settings.add(config) } else { settings.update(config) }
        states[config.id] = ProviderState(snapshot: snapshot)
        retryAfter[config.id] = nil
        rememberCurrency(snapshot, for: config.id)
    }

    func remove(_ id: UUID) throws {
        guard settings.config(id)?.provider != .codex else { return }
        try vault.remove(id)
        saveTokens[id] = nil
        generations[id] = UUID()
        settings.remove(id)
        states[id] = nil
        retryAfter[id] = nil
    }

    private func rememberCurrency(_ snapshot: QuotaSnapshot, for id: UUID) {
        guard let currency = snapshot.balance?.currency,
              var config = settings.config(id), config.currency != currency else { return }
        config.currency = currency
        settings.update(config)
    }
}
