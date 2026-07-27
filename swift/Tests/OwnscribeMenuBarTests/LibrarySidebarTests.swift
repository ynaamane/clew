import XCTest
@testable import OwnscribeMenuBar

final class LibrarySidebarTests: XCTestCase {
    private func meeting(
        _ name: String,
        transcript: Bool = true,
        summary: Bool = true,
        actions: Int = 0,
        unanchored: Int = 0
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
}
