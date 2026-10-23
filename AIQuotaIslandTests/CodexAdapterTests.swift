import Foundation
import XCTest
@testable import AIQuotaIsland

final class CodexAdapterTests: XCTestCase {
    func testTwoWindowsAndBankedResetCount() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let usage = Data(#"""
        {
            "rate_limit": {
                "primary_window": {"used_percent": 28, "limit_window_seconds": 18000, "reset_at": 1800001000},
                "secondary_window": {"used_percent": 55, "limit_window_seconds": 604800, "reset_at": 1800100000}
            },
            "rate_limit_reset_credits": {"available_count": 2}
        }
        """#.utf8)
        let details = Data(#"""
        {
            "available_count": 2,
            "credits": [
                {"status": "available", "expires_at": "2027-01-16T08:00:00Z"},
                {"status": "available", "expires_at": null},
                {"status": "redeemed", "expires_at": "2027-01-01T00:00:00Z"}
            ]
        }
        """#.utf8)

        let snapshot = try CodexAdapter.parseUsage(usage, fetchedAt: now, resetDetails: details)
        XCTAssertEqual(snapshot.windows.map(\.title), ["5 小时", "本周"])
        XCTAssertEqual(snapshot.ringWindow?.title, "5 小时")
        XCTAssertEqual(snapshot.remainingFraction!, 0.72, accuracy: 0.000001)
        XCTAssertEqual(snapshot.resetCredits?.availableCount, 2)
        XCTAssertNotNil(snapshot.resetCredits?.expiresAt)
        XCTAssertTrue(snapshot.isLargeCard)
    }

    func testWeeklyOnlyKeepsCountWhenDetailsUnavailable() throws {
        let usage = Data(#"""
        {
            "rate_limit": {"primary_window": {
                "used_percent": 40, "limit_window_seconds": 604800, "reset_at": 1800100000
            }},
            "rate_limit_reset_credits": {"available_count": 2}
        }
        """#.utf8)

        let snapshot = try CodexAdapter.parseUsage(
            usage, fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].title, "本周")
        XCTAssertEqual(snapshot.remainingFraction!, 0.6, accuracy: 0.000001)
        XCTAssertEqual(snapshot.resetCredits?.availableCount, 2)
        XCTAssertNil(snapshot.resetCredits?.expiresAt)
    }

    func testMalformedWindowsNeverBecomeFakeQuota() {
        let usage = Data(#"{"rate_limit":{"primary_window":{"used_percent":"unknown"}}}"#.utf8)
        XCTAssertThrowsError(try CodexAdapter.parseUsage(usage, fetchedAt: Date())) { error in
            XCTAssertEqual((error as? QuotaFailure)?.kind, .unavailable)
        }
    }

    func testOutOfRangePercentNeverBecomesQuota() {
        let usage = Data(#"{"rate_limit":{"primary_window":{"used_percent":150}}}"#.utf8)
        XCTAssertThrowsError(try CodexAdapter.parseUsage(usage, fetchedAt: Date())) { error in
            XCTAssertEqual((error as? QuotaFailure)?.kind, .unavailable)
        }
    }
}
