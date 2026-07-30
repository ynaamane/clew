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

    func testTheCountIsPluralisedWithoutLeakingMarkup() {
        XCTAssertEqual(state(unanchored: 1).rowText, "1 non ancré")
        XCTAssertEqual(state(unanchored: 3).rowText, "3 non ancrés")

        for count in [1, 3] {
            let text = state(unanchored: count).rowText ?? ""
            XCTAssertFalse(
                text.contains("^["),
                "This assertion used to REQUIRE the markup, which locked the bug in place: SwiftUI resolves ^[…](inflect:) only in a literal or LocalizedStringKey, never in a String variable handed to Text(_:). The sibling site rendered it verbatim to the user.")
        }
    }
}
