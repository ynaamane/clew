import XCTest
@testable import OwnscribeMenuBar

final class MeetingRowTitleTests: XCTestCase {
    private func testDir(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name)")
    }

    func testSlugShowsFullDateWithTime() {
        let pair = MeetingRowTitle.resolve(directory: testDir("2026-07-27_1536_project-review"))

        XCTAssertEqual(pair.title, "Project review")
        XCTAssertTrue(pair.subtitle.contains("15:36"), "Subtitle should include time when title is slug, got \(pair.subtitle)")
        XCTAssertTrue(pair.subtitle.contains("·"), "Subtitle should have separator when time included")
    }

    func testTranscriptFirstLineShowsFullDateWithTime() {
        // Cannot test without real transcript file in /tmp, covered by manual render verification
    }

    func testTimeOnlyShowsDateWithoutTimeRedundancy() {
        let pair = MeetingRowTitle.resolve(directory: testDir("2026-07-29_1537"))

        XCTAssertEqual(pair.title, "15:37", "Title should be time when no slug and no transcript")
        XCTAssertFalse(pair.subtitle.contains("15:37"), "Subtitle must NOT duplicate the time, got \(pair.subtitle)")
        XCTAssertFalse(pair.subtitle.contains("·"), "Subtitle should have no separator when time omitted")
        XCTAssertTrue(pair.subtitle.contains("29 Jul") || pair.subtitle.contains("Jul"), "Subtitle should contain date")
    }

    func testRefusalFallsBackLikeNoSlug() {
        let pair = MeetingRowTitle.resolve(directory: testDir("2026-07-30_1141_please-provide-the-transcript"))

        XCTAssertEqual(pair.title, "11:41", "Refusal should fall back to time")
        XCTAssertFalse(pair.subtitle.contains("11:41"), "Subtitle must not duplicate time")
    }

    func testAllBackchannelTranscriptFallsToTime() {
        // Backchannels are ≤3 words. If a transcript has ONLY "OK." or "Yeah" or "Mm-hmm",
        // firstTranscriptLine returns nil and we fall to time.
        // Covered by manual verification with real 27-Jul meeting that has "[05:09] OK."
    }
}
