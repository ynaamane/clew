import XCTest
@testable import OwnscribeMenuBar

final class MeetingHeaderDetailTests: XCTestCase {
    func testSpeakerCountDoesNotLeakInflectionMarkupToTheUser() {
        let detail = MeetingHeaderDetail.text(
            date: "30 Jul · 11:41",
            duration: 5,
            language: "en",
            speakerCount: 1
        )

        XCTAssertFalse(
            detail.contains("^["),
            "Inflection markup reached the user verbatim: \(detail). Text(String) renders a String variable literally — only a literal or LocalizedStringKey resolves ^[…](inflect:).")
        XCTAssertFalse(detail.contains("inflect"), "Rendered detail must not name the inflection API: \(detail)")
        XCTAssertTrue(detail.contains("1 voix"), "Singular speaker count must still read naturally: \(detail)")
    }

    func testPluralSpeakerCountReadsNaturally() {
        let detail = MeetingHeaderDetail.text(date: "27 Jul · 15:36", duration: 1050, language: "fr", speakerCount: 3)

        XCTAssertTrue(detail.contains("3 voix"), "Expected a plural speaker count in: \(detail)")
        XCTAssertFalse(detail.contains("^["), "Plural path must not leak markup either: \(detail)")
    }

    func testAbsentTranscriptFactsAreOmittedRatherThanShownAsZero() {
        let detail = MeetingHeaderDetail.text(date: "29 Jul · 15:37", duration: nil, language: "", speakerCount: nil)

        XCTAssertEqual(detail, "29 Jul · 15:37", "A meeting with no transcript must show its date alone, never 0:00 or 0 voix")
    }

    func testDurationIsFormattedAsMinutesAndSeconds() {
        let detail = MeetingHeaderDetail.text(date: "27 Jul · 15:36", duration: 1050, language: "", speakerCount: nil)

        XCTAssertTrue(detail.contains("17:30"), "Expected 1050s to read as 17:30 in: \(detail)")
    }
}
