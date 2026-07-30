import Testing
import Foundation
@testable import OwnscribeMenuBar

@Suite("MeetingSearchFilter")
struct MeetingSearchFilterTests {
    let meeting1 = MeetingSummary(
        directory: URL(fileURLWithPath: "/tmp/2026-07-28_1000_project-review"),
        hasTranscript: true,
        hasSummary: true
    )

    let meeting2 = MeetingSummary(
        directory: URL(fileURLWithPath: "/tmp/2026-07-29_1100_weekly-standup"),
        hasTranscript: true,
        hasSummary: true
    )

    let meeting3 = MeetingSummary(
        directory: URL(fileURLWithPath: "/tmp/2026-07-30_1200_design-discussion"),
        hasTranscript: true,
        hasSummary: false
    )

    @Test("Empty query returns all meetings")
    func testEmptyQuery() {
        let meetings = [meeting1, meeting2, meeting3]
        let filtered = MeetingSearchFilter.filter(meetings, query: "")

        #expect(filtered.count == 3)
    }

    @Test("Filters by title substring (case-insensitive)")
    func testFilterByTitle() {
        let meetings = [meeting1, meeting2, meeting3]
        let filtered = MeetingSearchFilter.filter(meetings, query: "PROJECT")

        #expect(filtered.count == 1)
        #expect(filtered.first?.id == meeting1.id)
    }

    @Test("Filters by date substring")
    func testFilterByDate() {
        let meetings = [meeting1, meeting2, meeting3]
        let filtered = MeetingSearchFilter.filter(meetings, query: "29")

        #expect(filtered.count == 1)
        #expect(filtered.first?.id == meeting2.id)
    }

    @Test("Multiple meetings match query")
    func testMultipleMatches() {
        let meetings = [meeting1, meeting2, meeting3]
        let filtered = MeetingSearchFilter.filter(meetings, query: "design")

        #expect(filtered.count == 1)
        #expect(filtered.first?.id == meeting3.id)
    }

    @Test("No meetings match query")
    func testNoMatches() {
        let meetings = [meeting1, meeting2, meeting3]
        let filtered = MeetingSearchFilter.filter(meetings, query: "nonexistent")

        #expect(filtered.isEmpty)
    }

    @Test("Whitespace-only query returns all")
    func testWhitespaceQuery() {
        let meetings = [meeting1, meeting2, meeting3]
        let filtered = MeetingSearchFilter.filter(meetings, query: "   ")

        #expect(filtered.count == 3)
    }

    @Test("Search normalizes special characters")
    func testNormalizedSearch() {
        let meetings = [meeting1, meeting2, meeting3]
        let filtered = MeetingSearchFilter.filter(meetings, query: "réview")

        #expect(filtered.count == 1)
        #expect(filtered.first?.id == meeting1.id)
    }
}
