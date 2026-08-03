import XCTest
@testable import OwnscribeMenuBar

final class MeetingRowMetaTests: XCTestCase {
    func testComposesDateDurationAndVoiceCountLikeTheMockup() {
        // mockup.html:272 — "27 juil. 15:36 · 17:30 · 3 voix"
        let text = MeetingRowMeta.text(date: "27 juil. 15:36", duration: 1050, speakerCount: 3)

        XCTAssertEqual(text, "27 juil. 15:36 · 17:30 · 3 voix")
    }

    func testNeverShowsALanguageUnlikeTheDetailHeader() {
        // MeetingHeaderDetail.text does show a language when one is passed; the row must never
        // reach that branch, so it always calls through with an empty language.
        let text = MeetingRowMeta.text(date: "27 juil. 15:36", duration: 1050, speakerCount: 3)

        XCTAssertFalse(text.contains("français"))
        XCTAssertFalse(text.contains("fr"))
    }

    func testAnUnknownDurationOrVoiceCountRendersAsAbsentNeverZero() {
        let text = MeetingRowMeta.text(date: "29 Jul · 15:37", duration: nil, speakerCount: nil)

        XCTAssertEqual(text, "29 Jul · 15:37", "a meeting with no transcript must show its date alone, never 0:00 or 0 voix")
    }

    func testOnlyOneMissingFactStillOmitsJustThatPart() {
        let text = MeetingRowMeta.text(date: "24 juil. 10:05", duration: 1931, speakerCount: nil)

        XCTAssertEqual(text, "24 juil. 10:05 · 32:11", "speaker count absent must not render as 0 voix while duration still shows")
    }
}
