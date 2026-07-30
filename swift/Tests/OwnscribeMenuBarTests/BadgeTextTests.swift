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

    func testUnanchoredBadgeShowsPlusWhenSomeMeetingsLackAnchoringData() {
        let meetings = [
            meeting("checked", unanchored: 1),
            meeting("unchecked", unanchored: nil)
        ]

        let unanchoredCount = meetings.filter { ($0.unanchoredClaimCount ?? 0) > 0 }.count
        let allHaveAnchoringData = meetings.allSatisfy { $0.unanchoredClaimCount != nil }

        let item = LibrarySidebarItem(
            id: "unanchored",
            title: "Non ancrées",
            filter: .unanchored,
            count: unanchoredCount,
            hasUnknowns: !allHaveAnchoringData,
            children: []
        )

        let badge = BadgeText.badgeText(for: item)

        XCTAssertEqual(
            badge, "1+",
            "When some meetings lack anchoring data, the badge must show '1+' not '1' — a bare number claims completeness"
        )
    }

    func testUnanchoredBadgeShowsPlainNumberWhenAllMeetingsAreChecked() {
        let meetings = [
            meeting("checked1", unanchored: 1),
            meeting("checked2", unanchored: 0),
            meeting("checked3", unanchored: 2)
        ]

        let unanchoredCount = meetings.filter { ($0.unanchoredClaimCount ?? 0) > 0 }.count
        let allHaveAnchoringData = meetings.allSatisfy { $0.unanchoredClaimCount != nil }

        let item = LibrarySidebarItem(
            id: "unanchored",
            title: "Non ancrées",
            filter: .unanchored,
            count: unanchoredCount,
            hasUnknowns: !allHaveAnchoringData,
            children: []
        )

        let badge = BadgeText.badgeText(for: item)

        XCTAssertEqual(
            badge, "2",
            "When all meetings have anchoring data, show the plain count"
        )
    }

    func testUnanchoredBadgeShowsZeroWhenAllCheckedAndNoneHaveIssues() {
        let meetings = [
            meeting("checked1", unanchored: 0),
            meeting("checked2", unanchored: 0)
        ]

        let unanchoredCount = meetings.filter { ($0.unanchoredClaimCount ?? 0) > 0 }.count
        let allHaveAnchoringData = meetings.allSatisfy { $0.unanchoredClaimCount != nil }

        let item = LibrarySidebarItem(
            id: "unanchored",
            title: "Non ancrées",
            filter: .unanchored,
            count: unanchoredCount,
            hasUnknowns: !allHaveAnchoringData,
            children: []
        )

        let badge = BadgeText.badgeText(for: item)

        XCTAssertEqual(
            badge, "0",
            "When all meetings are checked and clean, show '0' not nil"
        )
    }

    func testActionsBadgeShowsPlusWhenSomeMeetingsLackActionData() {
        let meetings = [
            meeting("checked", actions: 2),
            meeting("unchecked", actions: nil)
        ]

        let actionCount = meetings.filter { ($0.actionItemCount ?? 0) > 0 }.count
        let allHaveActionData = meetings.allSatisfy { $0.actionItemCount != nil }

        let item = LibrarySidebarItem(
            id: "actions",
            title: "Avec actions",
            filter: .withActions,
            count: actionCount,
            hasUnknowns: !allHaveActionData,
            children: []
        )

        let badge = BadgeText.badgeText(for: item)

        XCTAssertEqual(
            badge, "1+",
            "Same principle applies to action items: nil means unknown, not zero"
        )
    }
}
