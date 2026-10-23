import AppKit
import Foundation
import Network

struct ProviderState {
    var snapshot: QuotaSnapshot?
    var failure: QuotaFailure?
    var isRefreshing = false

    func effectiveFailure(at date: Date) -> QuotaFailure? {
        if let snapshot, let expiry = snapshot.totalQuota?.expiresAt, expiry <= date {
            return .expired("已到期")
        }
        return failure
    }
}

@MainActor
final class QuotaCoordinator: ObservableObject {
    @Published private(set) var states: [ProviderID: ProviderState] = [:]
    @Published private(set) var now = Date()
    @Published private(set) var isRefreshing = false

    let settings = AppSettings()
    private let adapters: [ProviderID: any QuotaAdapter]
    private var refreshTimer: Timer?
    private var clockTimer: Timer?
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "AIQuotaIsland.network")
    private var lastNetworkSatisfied = true
    private var retryAfter: [ProviderID: Date] = [:]
    private var wakeObserver: NSObjectProtocol?

    init(adapters: [any QuotaAdapter]) {
        self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.provider, $0) })
        for id in ProviderID.allCases { states[id] = ProviderState() }
    }

    func start() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAll() }
        }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshAll(force: true) }
        }
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

    func refreshAll(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        for id in ProviderID.allCases where adapters[id] != nil {
            await refresh(id, force: force)
        }
    }

    func refresh(_ id: ProviderID, force: Bool = false) async {
        guard let adapter = adapters[id] else { return }
        if !force, let retry = retryAfter[id], retry > Date() { return }
        if !force, states[id]?.failure?.kind == .authentication { return }
        states[id, default: ProviderState()].isRefreshing = true
        defer { states[id, default: ProviderState()].isRefreshing = false }
        do {
            let snapshot = try await adapter.fetch()
            states[id] = ProviderState(snapshot: snapshot, failure: nil, isRefreshing: false)
            retryAfter[id] = nil
        } catch let error as QuotaFailure {
            states[id, default: ProviderState()].failure = error
            if error.kind == .temporary { retryAfter[id] = Date().addingTimeInterval(120) }
        } catch {
            states[id, default: ProviderState()].failure = .temporary("查询暂时失败")
            retryAfter[id] = Date().addingTimeInterval(120)
        }
    }

    func replaceSparkCookie(_ cookie: String) async throws {
        let adapter = SparkAdapter()
        let snapshot = try await adapter.validate(cookie: cookie)
        try KeychainStore.saveSparkCookie(cookie)
        states[.spark] = ProviderState(snapshot: snapshot)
        retryAfter[.spark] = nil
    }

    func replaceOpenCodeGoKey(_ key: String) async throws {
        let snapshot = try await OpenCodeGoAdapter().validate(key: key)
        try KeychainStore.saveOpenCodeGoKey(key)
        states[.opencodeGo] = ProviderState(snapshot: snapshot)
        retryAfter[.opencodeGo] = nil
    }
}
