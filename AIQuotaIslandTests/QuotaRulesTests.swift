import XCTest
@testable import AIQuotaIsland

final class QuotaRulesTests: XCTestCase {
    func testWaterLevelBoundariesAndCurrencies() {
        XCTAssertEqual(QuotaFormat.waterLevel(0), 0)
        XCTAssertEqual(QuotaFormat.waterLevel(0.01), 0.14)
        XCTAssertEqual(QuotaFormat.waterLevel(10), 0.14)
        XCTAssertEqual(QuotaFormat.waterLevel(10.01), 0.5)
        XCTAssertEqual(QuotaFormat.waterLevel(100), 0.5)
        XCTAssertEqual(QuotaFormat.waterLevel(100.01), 0.8)
        XCTAssertEqual(QuotaFormat.currencySymbol(nil), "￥")
        XCTAssertEqual(QuotaFormat.currencySymbol("USD"), "$")
        XCTAssertEqual(QuotaFormat.compact(123_456_789), "1.23亿")
        XCTAssertEqual(QuotaFormat.compact(1_200_000), "1.2M")
        XCTAssertEqual(QuotaFormat.compact(12_345), "12.35K")
    }

    func testCircleAndResetUseDifferentPeriodsEvenWhenWeekResetsSooner() {
        let five = QuotaWindow(id: "5h", title: "5 小时", durationSeconds: 18_000,
                               remainingFraction: 0.8, resetsAt: Date(timeIntervalSince1970: 1000))
        let week = QuotaWindow(id: "week", title: "本周", durationSeconds: 604_800,
                               remainingFraction: 0.6, resetsAt: Date(timeIntervalSince1970: 500))
        let snapshot = QuotaSnapshot(provider: .codex, windows: [week, five],
                                     totalQuota: nil, resetCredits: nil, fetchedAt: Date())
        XCTAssertEqual(snapshot.ringWindow?.id, "5h")
        XCTAssertEqual(snapshot.resetWindow?.id, "week")
    }

    func testBalanceIsNotInventedAsTotalCapacity() throws {
        let deepSeek = try DeepSeekAdapter.parse(Data(#"{"balance_infos":[{"currency":"CNY","total_balance":"0.00"}]}"#.utf8))
        XCTAssertEqual(deepSeek.balance?.remaining, 0)
        XCTAssertNil(deepSeek.remainingFraction)
        XCTAssertNil(deepSeek.totalQuota)
        let router = try OpenRouterAdapter.parse(Data(#"{"data":{"total_credits":100,"total_usage":25}}"#.utf8))
        XCTAssertEqual(router.balance?.remaining, 75)
        XCTAssertNil(router.remainingFraction)
    }

    func testCustomZeroValidAndMalformedNumbersRejected() throws {
        let zero = try CustomQuotaParser.parse(["remaining": 0, "unit": "USD"])
        XCTAssertEqual(zero.balance?.remaining, 0)
        XCTAssertEqual(zero.balance?.currency, "USD")
        XCTAssertThrowsError(try CustomQuotaParser.parse(["remaining": true, "unit": "tokens"]))
        XCTAssertThrowsError(try CustomQuotaParser.parse(["remaining": Double.nan]))
        XCTAssertThrowsError(try CustomQuotaParser.parse(["total": "invalid", "remaining": 10]))
        XCTAssertThrowsError(try CustomQuotaParser.parse(["isValid": false, "invalidMessage": "套餐已到期"]))
        let scaled = try CustomQuotaParser.parse(["remaining": 9.96, "total": 10, "unit": "亿"])
        XCTAssertEqual(try XCTUnwrap(scaled.totalQuota?.remaining), 996_000_000, accuracy: 0.001)
        XCTAssertEqual(scaled.totalQuota?.unit, "tokens")
    }

    func testKimiRatioPoolsAndGLMExplicitPeriods() throws {
        let kimi = try KimiAdapter.parse(Data(#"{"usages":{"limit_5h":{"used_ratio":0.2},"limit_7d":{"used_ratio":0.4}}}"#.utf8))
        XCTAssertEqual(kimi.windows.count, 2)
        XCTAssertEqual(kimi.ringWindow!.remainingFraction, 0.8, accuracy: 0.0001)
        let glm = try GLMAdapter.parse(Data(#"{"success":true,"data":{"limits":[{"type":"TOKENS_LIMIT","unit":6,"percentage":40,"nextResetTime":1000000000000},{"type":"TOKENS_LIMIT","unit":3,"percentage":20,"nextResetTime":2000000000000}]}}"#.utf8))
        XCTAssertEqual(glm.ringWindow?.durationSeconds, 18_000)
        XCTAssertEqual(glm.resetWindow?.durationSeconds, 604_800)
    }

    func testMiniMaxUsageCountMeansRemaining() throws {
        let data = Data(#"{"model_remains":[{"model_name":"MiniMax-M2","current_interval_total_count":100,"current_interval_usage_count":80,"current_weekly_total_count":1000,"current_weekly_usage_count":600}]}"#.utf8)
        let snapshot = try MiniMaxAdapter.parse(data)
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(snapshot.ringWindow!.remainingFraction, 0.8, accuracy: 0.0001)
    }

    func testStepFunCreditBucketsAreCreditsAndDifferentExpiriesAreNotInventedAsOne() throws {
        let data = Data(#"{"status":1,"five_hour_usage_reset_time":"0","weekly_usage_reset_time":"0","plan_credit_rate_limit":{"credit_buckets":[{"credit_total":"100","credit_residual":"10","expire_at":"1800000000"},{"credit_total":"100","credit_residual":"40","expire_at":"1800100000"}]}}"#.utf8)
        let snapshot = try StepFunAdapter.parse(data)
        XCTAssertNil(snapshot.balance)
        XCTAssertEqual(snapshot.totalQuota?.unit, "credits")
        XCTAssertEqual(snapshot.totalQuota?.remaining, 50)
        XCTAssertNil(snapshot.totalQuota?.expiresAt)
        let exhausted = try StepFunAdapter.parse(Data(#"{"status":1,"five_hour_usage_left_rate":0,"weekly_usage_left_rate":0.5,"five_hour_usage_reset_time":"1800000000","weekly_usage_reset_time":"1800100000"}"#.utf8))
        XCTAssertEqual(exhausted.windows.count, 2)
        XCTAssertEqual(exhausted.ringWindow?.remainingFraction, 0)
    }

    func testCustomExtremeDurationFailsWithoutIntegerOverflow() {
        XCTAssertThrowsError(try CustomQuotaParser.parse(["windows": [
            ["id": "large", "title": "周期", "durationSeconds": Double(Int.max), "remainingPercent": 50]
        ]]))
    }
}

final class DynamicSettingsTests: XCTestCase {
    @MainActor func testDefaultAndNewNotchRulesPersistWithoutDuplicateChatGPT() throws {
        let name = "AIQuotaIslandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.providers.map(\.provider), [.codex])
        XCTAssertEqual(settings.refreshMinutes, 3)
        let deepSeek = ProviderConfig(provider: .deepSeek)
        settings.add(deepSeek)
        XCTAssertEqual(settings.compactProviders.count, 2)
        settings.add(ProviderConfig(provider: .opencodeGo))
        XCTAssertEqual(settings.compactProviders.count, 2)
        settings.add(ProviderConfig(provider: .codex))
        XCTAssertEqual(settings.providers.count, 3)
        settings.remove(settings.providers[0].id)
        XCTAssertEqual(settings.providers[0].provider, .codex)
        for index in settings.providers.indices { settings.providers[index].showInCompact = false }
        let another = ProviderConfig(provider: .deepSeek)
        settings.add(another)
        XCTAssertFalse(settings.config(another.id)!.showInCompact)
        settings.providers[1].remark = "工作"
        let loaded = AppSettings(defaults: defaults)
        XCTAssertEqual(loaded.providers, settings.providers)
        XCTAssertNotEqual(loaded.providers[1].id, another.id)
        let firstID = settings.providers[0].id
        let lastID = settings.providers.last!.id
        settings.move(firstID, to: lastID)
        XCTAssertEqual(settings.providers.last!.id, firstID)
        settings.move(firstID, to: settings.providers[0].id)
        XCTAssertEqual(settings.providers[0].id, firstID)
    }

    @MainActor func testLegacyConfigurationGetsInstanceIDsAndKeepsRemarks() {
        let name = "AIQuotaIslandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data(#"[{"id":"codex","displayName":"Codex","isVisible":true,"showInCompact":true},{"id":"spark","displayName":"工作账号","isVisible":true,"showInCompact":false}]"#.utf8), forKey: "providerConfigs")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.providers.count, 2)
        XCTAssertEqual(settings.providers[1].remark, "工作账号")
        XCTAssertEqual(settings.providers[1].displayName, "讯飞-x2.6临时")
        XCTAssertTrue(settings.providers[1].isLegacy)
        settings.providers[1].remark = "新的备注"
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.providers.map(\.id), reloaded.providers.map(\.id))
        XCTAssertEqual(reloaded.providers[1].remark, "新的备注")
    }
}

final class ScriptWorkerTests: XCTestCase {
    func testFormatterAndRealWorkerExtraction() async throws {
        let script = "({request:{url:'https://example.invalid/usage'},extractor:r=>({remaining:r.balance,unit:'USD'})})"
        let formatted = try await CustomScriptEngine.format(script, timeout: 10)
        XCTAssertTrue(formatted.contains("extractor"))
        let output = try await ScriptProcessRunner.run(
            ["action": "extract", "script": formatted, "response": ["balance": 0]], timeout: 5)
        let value = try XCTUnwrap(output["result"] as? [String: Any])
        let parsed = try CustomQuotaParser.parse(value)
        XCTAssertEqual(parsed.balance?.remaining, 0)
    }

    func testPlaceholderReplacementIsDataAndLiteralCredentialsAreRejected() async throws {
        var config = ProviderConfig(provider: .custom)
        config.baseURL = "https://example.invalid"
        config.script = """
        ({ request: {url:"{{baseUrl}}/usage", method:"POST",
          headers:{Authorization:"Bearer {{apiKey}}"},
          body:{label:'a"b',key:"{{apiKey}}"} },
          extractor:r=>({remaining:r.balance,unit:"USD"}) })
        """
        let credential = KeychainStore.Credentials(apiKey: "test-fixture-only")
        let request = try await CustomScriptEngine.makeRequest(config, credentials: credential)
        XCTAssertEqual(request.url?.absoluteString, "https://example.invalid/usage")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-fixture-only")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["label"] as? String, "a\"b")
        config.script = #"({request:{url:"https://example.invalid",headers:{Authorization:"Bearer hardcoded-example"}},extractor:r=>r})"#
        do {
            _ = try await CustomScriptEngine.makeRequest(config, credentials: KeychainStore.Credentials())
            XCTFail("A literal authorization value must not be persisted")
        } catch let failure as QuotaFailure { XCTAssertTrue(failure.message.contains("不要写入脚本")) }
    }

    func testDeadLoopTimesOutAndNextOperationStillWorks() async throws {
        var config = ProviderConfig(provider: .custom)
        config.timeout = 1
        config.script = "({request:(function(){while(true){}})(),extractor:r=>r})"
        let start = Date()
        do {
            _ = try await CustomScriptEngine.makeRequest(config, credentials: KeychainStore.Credentials())
            XCTFail("The worker must be terminated")
        } catch let failure as QuotaFailure { XCTAssertTrue(failure.message.contains("超时")) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        let formatted = try await CustomScriptEngine.format(CustomScriptGuide.starter, timeout: 10)
        XCTAssertTrue(formatted.contains("extractor"))
    }
}
