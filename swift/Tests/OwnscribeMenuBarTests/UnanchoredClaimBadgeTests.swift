import XCTest
@testable import OwnscribeMenuBar

final class UnanchoredClaimBadgeTests: XCTestCase {
    private func state(unanchored: Int?) -> UnanchoredClaimBadge {
        let meeting = MeetingSummary(
            directory: URL(fileURLWithPath: "/tmp/m"),
            hasTranscript: true,
            hasSummary: true,
            actionItemCount: 0,
            unanchoredClaimCount: unanchored
        )
        return UnanchoredClaimBadge.state(unanchoredClaimCount: meeting.unanchoredClaimCount)
    }

    func testTheThreeStatesAreNotCollapsedIntoTwo() {
        XCTAssertEqual(state(unanchored: nil), .neverChecked)
        XCTAssertEqual(state(unanchored: 0), .allAnchored)
        XCTAssertEqual(state(unanchored: 3), .unanchored(count: 3))

        XCTAssertNotEqual(
            state(unanchored: nil), state(unanchored: 0),
            "anchoring never ran is not the same fact as anchoring ran and found nothing; the row rendered both identically before this")
    }

    func testAnUncheckedMeetingSaysSoRatherThanLookingClean() {
        XCTAssertEqual(
            state(unanchored: nil).rowText, "non vérifiée",
            "every meeting on the real disk is in this state, so rendering nothing made the whole library look verified")
    }

    func testACheckedAndCleanMeetingCarriesNoText() {
        XCTAssertNil(
            state(unanchored: 0).rowText,
            "a meeting whose claims all have evidence is the quiet case and must not be decorated")
    }

    func testTheCountKeepsItsInflectionMarkup() {
        XCTAssertEqual(
            state(unanchored: 1).rowText, "^[1 non ancré](inflect: true)",
            "SwiftUI does the pluralisation; asserting the rendered string here would pass on markup that never inflects")
    }
}
