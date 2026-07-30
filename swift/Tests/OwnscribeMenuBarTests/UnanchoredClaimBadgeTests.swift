import XCTest
@testable import OwnscribeMenuBar

final class UnanchoredClaimBadgeTests: XCTestCase {

    func testNeverCheckedReturnsNil() {
        let result = UnanchoredClaimBadge.badge(unanchoredClaimCount: nil)
        XCTAssertNil(result, "When a meeting has never been checked, no badge should appear")
    }

    func testAllAnchoredReturnsNil() {
        let result = UnanchoredClaimBadge.badge(unanchoredClaimCount: 0)
        XCTAssertNil(result, "When all claims are anchored (count = 0), no badge should appear")
    }

    func testSomeUnanchoredReturnsBadge() {
        let result = UnanchoredClaimBadge.badge(unanchoredClaimCount: 3)
        XCTAssertNotNil(result, "When some claims are unanchored, a badge should appear")
        XCTAssertEqual(result, "3 non ancré")
    }

    func testOneUnanchoredReturnsSingular() {
        let result = UnanchoredClaimBadge.badge(unanchoredClaimCount: 1)
        XCTAssertNotNil(result, "When one claim is unanchored, a badge should appear")
        XCTAssertEqual(result, "1 non ancré")
    }
}
