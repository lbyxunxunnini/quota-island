import Foundation
import XCTest
@testable import AIQuotaIsland

final class SparkAdapterTests: XCTestCase {
    func testTotalQuotaAndExpiryAreParsed() throws {
        let data = Data(#"{"code":0,"data":{"claim":{"freeQuota":{"remainingTokens":998863985,"totalTokens":1000000000,"usedTokens":1136015,"expiresAt":"2099-11-23 07:56:11","quotaStatus":"ACTIVE","usageAvailable":true}}},"failed":false,"succeed":true}"#.utf8)

        let snapshot = try SparkAdapter.parseQuota(data, now: .distantPast)

        XCTAssertEqual(snapshot.provider, .spark)
        XCTAssertTrue(snapshot.windows.isEmpty)
        XCTAssertNil(snapshot.resetCredits)
        XCTAssertEqual(snapshot.totalQuota?.remaining, 998_863_985)
        XCTAssertEqual(snapshot.totalQuota?.total, 1_000_000_000)
        XCTAssertEqual(snapshot.remainingFraction ?? -1, 0.998863985, accuracy: 0.000000001)
        XCTAssertNotNil(snapshot.totalQuota?.expiresAt)
    }

    func testExpiredQuotaUsesExpiredFailure() {
        let data = Data(#"{"code":0,"data":{"claim":{"freeQuota":{"remainingTokens":500,"totalTokens":1000,"usedTokens":500,"expiresAt":"2026-11-23 07:56:11","quotaStatus":"EXPIRED","usageAvailable":false}}}}"#.utf8)

        XCTAssertThrowsError(try SparkAdapter.parseQuota(data)) { error in
            guard let failure = error as? QuotaFailure,
                  case .expired = failure.kind else {
                return XCTFail("Expected expired failure")
            }
        }
    }

    func testDatePastExpiryUsesExpiredFailureEvenIfStatusIsActive() {
        let data = Data(#"{"code":0,"data":{"claim":{"freeQuota":{"remainingTokens":500,"totalTokens":1000,"usedTokens":500,"expiresAt":"2026-11-23 07:56:11","quotaStatus":"ACTIVE","usageAvailable":true}}}}"#.utf8)

        XCTAssertThrowsError(try SparkAdapter.parseQuota(data, now: .distantFuture)) { error in
            guard let failure = error as? QuotaFailure,
                  case .expired = failure.kind else {
                return XCTFail("Expected expired failure")
            }
        }
    }

    func testNonzeroCodeUsesAuthenticationFailure() {
        let data = Data(#"{"code":401,"message":"Unauthorized"}"#.utf8)

        XCTAssertThrowsError(try SparkAdapter.parseQuota(data)) { error in
            guard let failure = error as? QuotaFailure,
                  case .authentication = failure.kind else {
                return XCTFail("Expected authentication failure")
            }
        }
    }

    func testMissingTotalIsRejectedWithoutInventingPercentage() {
        let data = Data(#"{"code":0,"data":{"claim":{"freeQuota":{"remainingTokens":500,"usedTokens":500,"expiresAt":"2099-11-23 07:56:11","quotaStatus":"ACTIVE","usageAvailable":true}}}}"#.utf8)

        XCTAssertThrowsError(try SparkAdapter.parseQuota(data, now: .distantPast)) { error in
            guard let failure = error as? QuotaFailure,
                  case .unavailable = failure.kind else {
                return XCTFail("Expected unavailable failure")
            }
        }
    }
}
