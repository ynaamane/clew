import XCTest
@testable import OwnscribeMenuBar

final class BadgeTextTests: XCTestCase {
    private func meeting(
        _ name: String,
        transcript: Bool = true,
        summary: Bool = true,
        actions: Int? = 0,
        unanchored: Int? = 0
    ) -> MeetingSummary {
        MeetingSummary(
            directory: URL(fileURLWithPath: "/tmp/\(name)"),
            hasTranscript: transcript,
            hasSummary: summary,
            actionItemCount: actions,
            unanchoredClaimCount: unanchored
        )
    }

    func testBadgeForNilCountReturnsNil() {
        let item = LibrarySidebarItem(
            id: "test", title: "Test", filter: .all, count: nil, hasUnknowns: false, children: [])

        let badge = BadgeText.badgeText(for: item)

        XCTAssertNil(badge, "No count means no badge")
    }

    func testBadgeForZeroCountShowsZero() {
        let item = LibrarySidebarItem(
            id: "test", title: "Test", filter: .all, count: 0, hasUnknowns: false, children: [])

        let badge = BadgeText.badgeText(for: item)

        XCTAssertEqual(badge, "0", "A real zero count renders as '0'")
    }

    func testBadgeForPositiveCountShowsNumber() {
        let item = LibrarySidebarItem(
            id: "test", title: "Test", filter: .all, count: 3, hasUnknowns: false, children: [])

        let badge = BadgeText.badgeText(for: item)

        XCTAssertEqual(badge, "3")
    }

    private func badge(for filter: LibraryFilter, in meetings: [MeetingSummary]) -> String? {
        let item = LibrarySidebar.sections(for: meetings, enrolledSpeakers: [])
            .flatMap(\.items)
            .first { $0.filter == filter }
        return item.flatMap(BadgeText.badgeText(for:))
    }

    func testUnanchoredBadgeShowsPlusWhenSomeMeetingsLackAnchoringData() {
        let badge = badge(
            for: .unanchored,
            in: [meeting("checked", unanchored: 1), meeting("unchecked", unanchored: nil)])

        XCTAssertEqual(
            badge, "1+",
            "When some meetings lack anchoring data, the badge must show '1+' not '1' — a bare number claims completeness")
    }

    func testUnanchoredBadgeShowsPlainNumberWhenAllMeetingsAreChecked() {
        let badge = badge(
            for: .unanchored,
            in: [
                meeting("checked1", unanchored: 1),
                meeting("checked2", unanchored: 0),
                meeting("checked3", unanchored: 2)
            ])

        XCTAssertEqual(badge, "2", "When all meetings have anchoring data, show the plain count")
    }

    func testUnanchoredBadgeShowsZeroWhenAllCheckedAndNoneHaveIssues() {
        let badge = badge(
            for: .unanchored,
            in: [meeting("checked1", unanchored: 0), meeting("checked2", unanchored: 0)])

        XCTAssertEqual(badge, "0", "When all meetings are checked and clean, show '0' not nil")
    }

    func testActionsBadgeShowsPlusWhenSomeMeetingsLackActionData() {
        let badge = badge(
            for: .withActions,
            in: [meeting("checked", actions: 2), meeting("unchecked", actions: nil)])

        XCTAssertEqual(
            badge, "1+",
            "Same principle applies to action items: nil means unknown, not zero")
    }

    func testTheRealLibraryOnDiskWouldNotClaimCompleteness() {
        let sixMeetingsLikeTheUsersDisk = (1...6).map { meeting("m\($0)", unanchored: nil) }

        XCTAssertNil(
            badge(for: .unanchored, in: sixMeetingsLikeTheUsersDisk),
            "no meeting on the real disk has usable anchors, so a '0+' badge would read as 'zero problems' when the truth is that nothing was checked")
    }

    func testZeroKnownWithUnknownsIsSilentButZeroKnownWithNoUnknownsIsAnAnswer() {
        let noneChecked = badge(for: .unanchored, in: [meeting("a", unanchored: nil)])
        let allCheckedAndClean = badge(for: .unanchored, in: [meeting("a", unanchored: 0)])

        XCTAssertNil(noneChecked, "a count of zero over unchecked meetings is not a finding")
        XCTAssertEqual(
            allCheckedAndClean, "0",
            "but a real zero, measured over meetings that were all checked, is information worth showing")
    }
}
