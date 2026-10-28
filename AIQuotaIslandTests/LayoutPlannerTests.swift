import XCTest
@testable import AIQuotaIsland

final class LayoutPlannerTests: XCTestCase {
    func testOddCountEndsInFullWidthRow() {
        for count in [1, 3, 5] {
            let rows = LayoutPlanner.boardRows(Array(0..<count))
            XCTAssertEqual(rows.flatMap { $0 }, Array(0..<count))
            XCTAssertEqual(rows.last?.count, 1)
            XCTAssertTrue(rows.dropLast().allSatisfy { $0.count == 2 })
        }
    }

    func testEvenCountUsesPairs() {
        for count in [2, 4, 6] {
            let rows = LayoutPlanner.boardRows(Array(0..<count))
            XCTAssertEqual(rows.flatMap { $0 }, Array(0..<count))
            XCTAssertTrue(rows.allSatisfy { $0.count == 2 })
        }
    }

    func testCompactLayoutCapsAtFourAndKeepsFirstTwoLeft() {
        let two = LayoutPlanner.compactSides([0, 1])
        XCTAssertEqual(two.left, [0, 1])
        XCTAssertTrue(two.right.isEmpty)
        let three = LayoutPlanner.compactSides([0, 1, 2])
        XCTAssertEqual(three.left, [0, 1])
        XCTAssertEqual(three.right, [2])

        let six = LayoutPlanner.compactSides([0, 1, 2, 3, 4, 5])
        XCTAssertEqual(six.left, [0, 1])
        XCTAssertEqual(six.right, [2, 3])
    }

    func testCompactSymbolsStayWithProvidersAfterRenaming() {
        XCTAssertEqual(ProviderConfig(id: .opencodeGo, displayName: "自定义名称").compactSymbol, "O")
        XCTAssertEqual(ProviderConfig(id: .codex, displayName: "自定义名称").compactSymbol, "G")
        XCTAssertEqual(ProviderConfig(id: .glm, displayName: "自定义名称").compactSymbol, "智")
        XCTAssertEqual(ProviderConfig(id: .spark, displayName: "自定义名称").compactSymbol, "讯")
    }
}
