import Foundation
import XCTest
@testable import OwnscribeMenuBar

final class LineHighlightDecisionTests: XCTestCase {
    func testNoHighlightedIDMeansNothingIsHighlighted() {
        let lineID = UUID()
        XCTAssertFalse(LineHighlightDecision.isHighlighted(lineID: lineID, highlightedID: nil))
    }

    func testMatchingIDIsHighlighted() {
        let lineID = UUID()
        XCTAssertTrue(LineHighlightDecision.isHighlighted(lineID: lineID, highlightedID: lineID))
    }

    func testDifferentIDIsNotHighlighted() {
        XCTAssertFalse(LineHighlightDecision.isHighlighted(lineID: UUID(), highlightedID: UUID()))
    }

    func testOnlyOneLineAmongManyIsHighlighted() {
        let ids = (0..<5).map { _ in UUID() }
        let target = ids[2]

        let results = ids.map { LineHighlightDecision.isHighlighted(lineID: $0, highlightedID: target) }

        XCTAssertEqual(results, [false, false, true, false, false])
    }
}
