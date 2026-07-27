import XCTest
@testable import OwnscribeMenuBar

final class MeetingDisplayTests: XCTestCase {
    private func meeting(_ folder: String) -> MeetingSummary {
        MeetingSummary(
            directory: URL(fileURLWithPath: "/tmp/\(folder)"),
            hasTranscript: true,
            hasSummary: true
        )
    }

    func testTitleComesFromTheSlugNotTheTimestamp() {
        let shown = meeting("2026-07-27_1536_project-technical-review-key-points").displayTitle

        XCTAssertEqual(shown, "Project technical review key points")
    }

    func testTitleFallsBackWhenThereIsNoSlug() {
        XCTAssertEqual(meeting("2026-07-27_1531").displayTitle, "Sans titre")
    }

    func testDateIsReadableRatherThanAFolderName() {
        let shown = meeting("2026-07-27_1536_project-technical-review").displayDate

        XCTAssertTrue(shown.contains("15:36"), "The recording time matters when several meetings share a day; got \(shown)")
        XCTAssertFalse(shown.contains("_"), "A folder name is not a date; got \(shown)")
    }

    func testMalformedFolderNameDoesNotCrashOrLie() {
        let odd = meeting("not-a-meeting")

        XCTAssertEqual(odd.displayTitle, "Not a meeting")
        XCTAssertEqual(odd.displayDate, "")
    }
}
