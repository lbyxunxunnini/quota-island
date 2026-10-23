import XCTest
@testable import AIQuotaIsland

private final class InMemoryCredentials {
    var values: [UUID: KeychainStore.Credentials] = [:]
    var vault: CredentialVault {
        CredentialVault(read: { self.values[$0.id] ?? KeychainStore.Credentials() },
                        write: { self.values[$1] = $0 }, remove: { self.values[$0] = nil })
    }
}

final class CoordinatorIsolationTests: XCTestCase {
    private static func snapshot(_ config: ProviderConfig, amount: Double) -> QuotaSnapshot {
        var result = QuotaSnapshot(provider: config.provider, windows: [], totalQuota: nil,
                                   resetCredits: nil, fetchedAt: Date())
        result.balance = BalanceQuota(remaining: amount, currency: "USD")
        return result
    }

    @MainActor func testRejectedCredentialKeepsExistingSnapshotAndOtherInstance() async throws {
        let name = "AIQuotaIslandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        let one = ProviderConfig(provider: .deepSeek)
        let two = ProviderConfig(provider: .deepSeek)
        settings.add(one); settings.add(two)
        let memory = InMemoryCredentials()
        memory.values[one.id] = .init(apiKey: "fixture-one")
        memory.values[two.id] = .init(apiKey: "fixture-two")
        let coordinator = QuotaCoordinator(settings: settings, query: { config, credentials in
            if credentials.apiKey == "fixture-rejected" { throw QuotaFailure.authentication("测试凭据拒绝") }
            return Self.snapshot(config, amount: 25)
        }, vault: memory.vault)
        await coordinator.refresh(one.id, force: true)
        do {
            try await coordinator.save(one, credentials: .init(apiKey: "fixture-rejected"))
            XCTFail("Invalid credentials must not be saved")
        } catch {}
        XCTAssertEqual(memory.values[one.id]?.apiKey, "fixture-one")
        XCTAssertEqual(memory.values[two.id]?.apiKey, "fixture-two")
        XCTAssertEqual(coordinator.states[one.id]?.snapshot?.balance?.remaining, 25)
        try await coordinator.save(one, credentials: .init(apiKey: "fixture-replacement"))
        XCTAssertEqual(memory.values[one.id]?.apiKey, "fixture-replacement")
        XCTAssertEqual(memory.values[two.id]?.apiKey, "fixture-two")
    }

    @MainActor func testOlderRefreshCannotOverwriteNewCredentialResult() async throws {
        let name = "AIQuotaIslandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        let config = ProviderConfig(provider: .deepSeek)
        settings.add(config)
        let memory = InMemoryCredentials()
        memory.values[config.id] = .init(apiKey: "fixture-old")
        let coordinator = QuotaCoordinator(settings: settings, query: { config, credentials in
            if credentials.apiKey == "fixture-old" {
                try await Task.sleep(for: .milliseconds(200))
                return Self.snapshot(config, amount: 10)
            }
            return Self.snapshot(config, amount: 80)
        }, vault: memory.vault)
        let old = Task { await coordinator.refresh(config.id, force: true) }
        try await Task.sleep(for: .milliseconds(30))
        try await coordinator.save(config, credentials: .init(apiKey: "fixture-new"))
        await old.value
        XCTAssertEqual(coordinator.states[config.id]?.snapshot?.balance?.remaining, 80)
        XCTAssertEqual(memory.values[config.id]?.apiKey, "fixture-new")
    }

    @MainActor func testDeletingDuringValidationCannotResurrectInstanceOrCredential() async throws {
        let name = "AIQuotaIslandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        let config = ProviderConfig(provider: .deepSeek)
        settings.add(config)
        let memory = InMemoryCredentials()
        let coordinator = QuotaCoordinator(settings: settings, query: { config, _ in
            try await Task.sleep(for: .milliseconds(150))
            return Self.snapshot(config, amount: 10)
        }, vault: memory.vault)
        let saving = Task { try await coordinator.save(config, credentials: .init(apiKey: "fixture-new")) }
        try await Task.sleep(for: .milliseconds(30))
        try coordinator.remove(config.id)
        do { try await saving.value; XCTFail("Deleted instance must not be restored") } catch {}
        XCTAssertNil(settings.config(config.id))
        XCTAssertNil(memory.values[config.id])
        XCTAssertNil(coordinator.states[config.id])
    }

    @MainActor func testAddingWhileOtherSettingsChangeDoesNotLoseValidation() async throws {
        let name = "AIQuotaIslandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        let config = ProviderConfig(provider: .deepSeek)
        let memory = InMemoryCredentials()
        let coordinator = QuotaCoordinator(settings: settings, query: { config, _ in
            try await Task.sleep(for: .milliseconds(120))
            return Self.snapshot(config, amount: 10)
        }, vault: memory.vault)
        let saving = Task { try await coordinator.save(config, credentials: .init(apiKey: "fixture-new")) }
        try await Task.sleep(for: .milliseconds(30))
        settings.providers[0].remark = "测试"
        try await saving.value
        XCTAssertNotNil(settings.config(config.id))
        XCTAssertNotNil(memory.values[config.id])
    }

    @MainActor func testReorderingKeepsSnapshotAndIdentity() async throws {
        let name = "AIQuotaIslandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        let first = ProviderConfig(provider: .deepSeek)
        let second = ProviderConfig(provider: .deepSeek)
        settings.add(first); settings.add(second)
        let memory = InMemoryCredentials()
        let coordinator = QuotaCoordinator(settings: settings, query: { config, _ in
            Self.snapshot(config, amount: 25)
        }, vault: memory.vault)
        await coordinator.refresh(first.id, force: true)
        settings.move(first.id, to: second.id)
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(settings.providers.last?.id, first.id)
        XCTAssertEqual(coordinator.states[first.id]?.snapshot?.balance?.remaining, 25)
    }
}
