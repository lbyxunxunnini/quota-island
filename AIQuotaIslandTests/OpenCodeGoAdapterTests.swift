import Foundation
import XCTest
@testable import AIQuotaIsland

final class OpenCodeGoAdapterTests: XCTestCase {
    func testThreeWindowsUseShortestPeriodForRing() throws {
        let data = Data(#"{"usage":{"rolling":{"percent":28,"resetsAt":"2026-11-01T12:00:00Z"},"weekly":{"percent":57,"resetsAt":"2026-11-03T12:00:00Z"},"monthly":{"percent":20,"resetsAt":"2026-11-20T12:00:00Z"}}}"#.utf8)
        let snapshot = try OpenCodeGoAdapter.parseUsage(data)

        XCTAssertEqual(snapshot.windows.map(\.id), ["rolling", "weekly", "monthly"])
        XCTAssertEqual(snapshot.windows[0].remainingFraction, 0.72, accuracy: 0.0001)
        XCTAssertEqual(snapshot.windows[1].remainingFraction, 0.43, accuracy: 0.0001)
        XCTAssertEqual(snapshot.windows[2].remainingFraction, 0.8, accuracy: 0.0001)
        XCTAssertEqual(snapshot.ringWindow?.id, "rolling")
        XCTAssertEqual(snapshot.remainingFraction ?? -1, 0.72, accuracy: 0.0001)
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
    }

    func testDisplayedPercentAlwaysFloorsAndOmitsHundredSign() {
        XCTAssertEqual(QuotaPercentage.text(0.9942), "99%")
        XCTAssertEqual(QuotaPercentage.text(0.9999), "99%")
        XCTAssertEqual(QuotaPercentage.text(0.9301), "93%")
        XCTAssertEqual(QuotaPercentage.text(0.9399), "93%")
        XCTAssertEqual(QuotaPercentage.text(1), "100")
    }

    func testMalformedWindowIsSkippedAndUnusedWindowHasNoResetCountdown() throws {
        let data = Data(#"{"usage":{"rolling":{"percent":0,"resetsAt":"2026-11-01T12:00:00Z"},"weekly":{"percent":"bad"},"monthly":{"percent":true}}}"#.utf8)
        let snapshot = try OpenCodeGoAdapter.parseUsage(data)

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].remainingFraction, 1)
        XCTAssertNil(snapshot.windows[0].resetsAt)
    }

    func testUnrecognizedResponseFailsInsteadOfShowingEmptyQuota() {
        let data = Data(#"{"usage":{"rolling":{"status":"ok"},"weekly":{"percent":120}}}"#.utf8)
        XCTAssertThrowsError(try OpenCodeGoAdapter.parseUsage(data)) { error in
            guard let failure = error as? QuotaFailure else {
                return XCTFail("Expected QuotaFailure")
            }
            guard case .unavailable = failure.kind else {
                return XCTFail("Expected unavailable failure")
            }
        }
    }
}
