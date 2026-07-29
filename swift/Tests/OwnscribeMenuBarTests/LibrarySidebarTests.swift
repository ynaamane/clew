import XCTest
@testable import OwnscribeMenuBar

final class LibrarySidebarTests: XCTestCase {
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

    func testSidebarStaysWithinTwoLevelsOfHierarchy() {
        let sections = LibrarySidebar.sections(for: [], enrolledSpeakers: ["Sam"])

        for section in sections {
            for item in section.items {
                XCTAssertTrue(
                    item.children.isEmpty,
                    "A sidebar may show at most two levels (group + item); deeper hierarchies belong in the content list")
            }
        }
    }

    func testAllMeetingsCountsEverything() {
        let meetings = [meeting("a"), meeting("b"), meeting("c")]

        let all = LibrarySidebar.sections(for: meetings, enrolledSpeakers: [])
            .flatMap(\.items)
            .first { $0.filter == .all }

        XCTAssertEqual(all?.count, 3)
    }

    func testNotIndexedCountsMeetingsSearchWouldSilentlySkip() {
        let meetings = [meeting("with"), meeting("without", summary: false)]

        let notIndexed = LibrarySidebar.sections(for: meetings, enrolledSpeakers: [])
            .flatMap(\.items)
            .first { $0.filter == .notIndexed }

        XCTAssertEqual(
            notIndexed?.count, 1,
            "Search skips meetings with no summary, so a confident 'not found' can be a lie; the count must be visible")
    }

    func testUnanchoredCountsMeetingsWithClaimsLackingEvidence() {
        let meetings = [meeting("clean"), meeting("suspect", unanchored: 2)]

        let unanchored = LibrarySidebar.sections(for: meetings, enrolledSpeakers: [])
            .flatMap(\.items)
            .first { $0.filter == .unanchored }

        XCTAssertEqual(unanchored?.count, 1)
    }

    func testEnrolledSpeakersBecomeTheirOwnSection() {
        let sections = LibrarySidebar.sections(for: [], enrolledSpeakers: ["Sam", "Idris"])

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[1].items.compactMap(\.speakerName), ["Sam", "Idris"])
    }

    func testEnrollActionIsAlwaysOfferedEvenWithNoVoicesYet() {
        let sections = LibrarySidebar.sections(for: [], enrolledSpeakers: [])

        let hasEnroll = sections.flatMap(\.items).contains { $0.filter == .enroll }

        XCTAssertTrue(hasEnroll, "Enrolling the first voice must be reachable from an empty library")
    }

    func testFilteringByNotIndexedReturnsOnlyThoseMeetings() {
        let meetings = [meeting("with"), meeting("without", summary: false)]

        let shown = LibraryFilter.notIndexed.apply(to: meetings)

        XCTAssertEqual(shown.count, 1)
        XCTAssertEqual(shown.first?.directory.lastPathComponent, "without")
    }

    func testFilteringByWithActionsUsesTheActionCount() {
        let meetings = [meeting("none"), meeting("five", actions: 5)]

        let shown = LibraryFilter.withActions.apply(to: meetings)

        XCTAssertEqual(shown.map(\.directory.lastPathComponent), ["five"])
    }

    func testBadgeForSpeakerItemIsNil() {
        let sections = LibrarySidebar.sections(for: [], enrolledSpeakers: ["Sam"])
        let speakerItem = sections.flatMap(\.items).first { $0.speakerName == "Sam" }!

        let badge = BadgeText.badgeText(for: speakerItem)

        XCTAssertNil(badge, "Speaker items have no count and must show no badge")
    }

    func testBadgeForEnrollItemIsNil() {
        let sections = LibrarySidebar.sections(for: [], enrolledSpeakers: [])
        let enrollItem = sections.flatMap(\.items).first { $0.filter == .enroll }!

        let badge = BadgeText.badgeText(for: enrollItem)

        XCTAssertNil(badge, "Enroll action has no count and must show no badge")
    }

    func testBadgeForZeroCountShowsZero() {
        let sections = LibrarySidebar.sections(for: [], enrolledSpeakers: [])
        let allItem = sections.flatMap(\.items).first { $0.filter == .all }!

        let badge = BadgeText.badgeText(for: allItem)

        XCTAssertEqual(badge, "0", "A real zero count renders as '0'")
    }

    func testBadgeForPositiveCountShowsNumber() {
        let meetings = [meeting("one"), meeting("two"), meeting("three")]
        let sections = LibrarySidebar.sections(for: meetings, enrolledSpeakers: [])
        let allItem = sections.flatMap(\.items).first { $0.filter == .all }!

        let badge = BadgeText.badgeText(for: allItem)

        XCTAssertEqual(badge, "3")
    }

    func testAnUncheckedMeetingIsNotFilteredInAsIfItHadActions() {
        let unchecked = meeting("never-summarised", summary: false, actions: nil, unanchored: nil)
        let real = meeting("has-one", actions: 1, unanchored: 1)

        XCTAssertEqual(
            LibraryFilter.withActions.apply(to: [unchecked, real]).map(\.displayTitle),
            [real.displayTitle],
            "actionItemCount is Int? so that a meeting nobody indexed reads as UNKNOWN; letting nil "
                + "into 'has actions' would assert a count that was never computed")
        XCTAssertEqual(
            LibraryFilter.unanchored.apply(to: [unchecked, real]).map(\.displayTitle),
            [real.displayTitle],
            "same for unanchored claims: nil means anchoring never ran, which is not the same as "
                + "'this meeting has unverified claims'")
    }

    func testAZeroCountIsFilteredOutJustLikeNilButMeansSomethingDifferent() {
        let checkedAndClean = meeting("checked-none-found", actions: 0, unanchored: 0)
        let unchecked = meeting("never-summarised", summary: false, actions: nil, unanchored: nil)

        XCTAssertTrue(LibraryFilter.withActions.apply(to: [checkedAndClean, unchecked]).isEmpty)
        let checkedItem = LibrarySidebarItem(
            id: "checked", title: "Actions", filter: .withActions, count: 0, children: [])
        let uncheckedItem = LibrarySidebarItem(
            id: "unchecked", title: "Actions", filter: .withActions, count: nil, children: [])

        XCTAssertEqual(
            BadgeText.badgeText(for: checkedItem), "0",
            "a checked meeting with no action items renders 0")
        XCTAssertNil(
            BadgeText.badgeText(for: uncheckedItem),
            "an unchecked meeting renders NO badge, because 0 would claim a count nobody computed")
    }
}
