import XCTest
@testable import OwnscribeMenuBar

final class LibrarySelectionTests: XCTestCase {
    private func meeting(_ name: String) -> MeetingSummary {
        MeetingSummary(
            directory: URL(fileURLWithPath: "/tmp/\(name)"),
            hasTranscript: true,
            hasSummary: true
        )
    }

    func testSelectsFirstWhenCurrentIsNil() {
        let meetings = [meeting("a"), meeting("b"), meeting("c")]

        let selected = LibrarySelection.resolve(current: nil, shown: meetings)

        XCTAssertEqual(selected, meetings[0])
    }

    func testReturnsNilWhenListIsEmpty() {
        let selected = LibrarySelection.resolve(current: nil, shown: [])

        XCTAssertNil(selected)
    }

    func testKeepsCurrentSelectionWhenStillVisible() {
        let meetings = [meeting("a"), meeting("b"), meeting("c")]
        let current = meetings[1]

        let selected = LibrarySelection.resolve(current: current, shown: meetings)

        XCTAssertEqual(selected, current, "Should preserve user's selection when still visible")
    }

    func testSelectsFirstWhenCurrentIsFilteredOut() {
        let all = [meeting("a"), meeting("b"), meeting("c")]
        let filtered = [meeting("a"), meeting("c")]
        let current = all[1]

        let selected = LibrarySelection.resolve(current: current, shown: filtered)

        XCTAssertEqual(selected, filtered[0], "Should select first visible when current is filtered out")
        XCTAssertNotEqual(selected, current)
    }

    func testReturnsNilWhenCurrentFilteredOutAndListBecomesEmpty() {
        let current = meeting("a")

        let selected = LibrarySelection.resolve(current: current, shown: [])

        XCTAssertNil(selected, "Should return nil when filter leaves list empty")
    }
}
